#!/usr/bin/env python3
"""
Set VPN Enhanced Link Selection (ELS) interfaces for either:
- Gaia Embedded (Spark) simple gateway, or
- Gaia Simple Cluster

Design:
- DB authoritative for ELS when rows exist in view 'vw_host_vpn_interfaces' (enabled=1):
    * keep redundancy-mode and priority as defined in DB (no auto-renumber/demotion)
    * validate and fail fast on rule violations
- Spark rule: exactly one IPv6 total, and it must be Active.
- Cluster policy (R82-friendly by default): keep one Active IPv6, drop other IPv6 entries
  from the payload (DB untouched). Adjustable via --cluster-ipv6-policy.

Fallback (only if --vpn-auto-select is given and the view has no rows):
- Build a minimal "Active" selection from host_interfaces.

Examples:
  # Cluster (auto-detect), DB is authoritative; default cluster IPv6 policy = single-active
  python3 set_vpn_interfaces.py --object cl1 \
    --mgmt-url https://x --api-key '...' \
    --db-host 127.0.0.1 --db-user root --db-pass ... --db-name netvars

  # Spark with manual VPN domain
  python3 set_vpn_interfaces.py --type spark --object vpn-gw-1 \
    --mgmt-url https://x --api-key '...' \
    --db-host 127.0.0.1 --db-user root --db-pass ... --db-name netvars \
    --vpn on --vpn-domain-type manual --vpn-domain "Spark1_EncDom46"
"""

from __future__ import annotations
import argparse, json, os, sys, ipaddress
from typing import List, Dict, Any, Optional, Tuple, Set

import requests
import mysql.connector
from cp_mgmt import CPMgmt


# ----------------------------- helpers -----------------------------

def env_or_arg(val: Optional[str], env_key: str, default: Optional[str] = None) -> Optional[str]:
    return val if (val is not None and str(val) != "") else os.environ.get(env_key, default)

def safe_int(v) -> Optional[int]:
    try:
        return int(str(v).strip())
    except Exception:
        return None

def _ip_family_ok(ipver: str, nh: str) -> bool:
    try:
        fam = ipaddress.ip_address(nh).version
        return (ipver == "ipv4" and fam == 4) or (ipver == "ipv6" and fam == 6)
    except Exception:
        return False

def str2bool(v):
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() in ("1","true","t","yes","y","on")


# ----------------------------- DB access -----------------------------

def db_connect(host, user, password, db):
    return mysql.connector.connect(host=host, user=user, password=password, database=db)

def q_all(cnx, sql: str, params: Tuple=()):
    cur = cnx.cursor(dictionary=True)
    cur.execute(sql, params)
    rows = cur.fetchall() or []
    cur.close()
    return rows

def q_one(cnx, sql: str, params: Tuple=()):
    rows = q_all(cnx, sql, params)
    return rows[0] if rows else None

def has_table(cnx, schema: str, table: str) -> bool:
    cur = cnx.cursor()
    cur.execute("SELECT 1 FROM information_schema.tables WHERE table_schema=%s AND table_name=%s LIMIT 1",
                (schema, table))
    ok = cur.fetchone() is not None
    cur.close()
    return ok

def has_column(cnx, table: str, column: str, schema: str) -> bool:
    cur = cnx.cursor()
    cur.execute(
        """SELECT 1 FROM information_schema.columns
           WHERE table_schema=%s AND table_name=%s AND column_name=%s LIMIT 1""",
        (schema, table, column),
    )
    ok = cur.fetchone() is not None
    cur.close()
    return ok

def detect_object_type(cnx, dbname: str, name: str) -> str:
    row = q_one(cnx, "SELECT template FROM hosts WHERE Name=%s", (name,))
    if row:
        t = (row.get("template") or "").strip().lower()
        if t in {"clusterobject", "cluster"}:
            return "cluster"
        if "spark" in t or "embedded" in t:
            return "spark"
    return "spark"


# ----------------------------- interface sources -----------------------------

def fetch_vpn_interfaces_from_db(cnx, dbname: str, name: str) -> List[Dict[str, Any]]:
    if not has_table(cnx, dbname, "vw_host_vpn_interfaces"):
        return []
    sql = """
      SELECT interface_name, ip_version, enabled, order_index,
             redundancy_mode, next_hop_ip, priority
        FROM vw_host_vpn_interfaces
       WHERE Name=%s AND enabled=1
       ORDER BY COALESCE(order_index,0), interface_name, ip_version
    """
    return q_all(cnx, sql, (name,))

def select_iface_cols(cnx, dbname: str) -> str:
    cols = [
        "interface", "vlan",
        "ipv4_addr", "`IPv4_mask-len` AS v4len",
        "ipv6_addr", "`prefix` AS v6len"
    ]
    cols.append("topology" if has_column(cnx, "host_interfaces", "topology", dbname) else "NULL AS topology")
    return ", ".join(cols)

def fetch_interfaces(cnx, dbname: str, name: str) -> List[Dict[str, Any]]:
    sql = f"""
      SELECT {select_iface_cols(cnx, dbname)}
        FROM host_interfaces
       WHERE Name=%s
       ORDER BY id
    """
    return q_all(cnx, sql, (name,))

def mk_ifname(base: str, vlan: Optional[str]) -> str:
    base = (base or "").strip()
    if not base:
        return ""
    return f"{base}.{str(vlan).strip()}" if vlan and str(vlan).strip() else base

def build_auto_for_spark(rows: List[Dict[str, Any]],
                         include_internal: bool,
                         include_mgmt: bool) -> List[Dict[str, Any]]:
    out = []
    ipv6_taken = False
    for r in rows:
        base = (r.get("interface") or "").strip()
        if not base:
            continue
        name = mk_ifname(base, r.get("vlan"))
        topo = (r.get("topology") or "").strip().upper()
        if not include_mgmt and base.lower() in {"mgmt","management"}:
            continue
        if not include_internal and topo == "INTERNAL":
            continue
        if (r.get("ipv6_addr") or "").strip() and not ipv6_taken:
            out.append({"interface-name": name, "ip-version": "ipv6", "redundancy-mode": "Active"})
            ipv6_taken = True
        if (r.get("ipv4_addr") or "").strip():
            out.append({"interface-name": name, "ip-version": "ipv4", "redundancy-mode": "Active"})
    return out

def build_auto_for_cluster(rows: List[Dict[str, Any]],
                           include_mgmt: bool,
                           include_sync: bool) -> List[Dict[str, Any]]:
    out = []
    for r in rows:
        base = (r.get("interface") or "").strip()
        if not base:
            continue
        name = mk_ifname(base, r.get("vlan"))
        b = base.lower()
        if b == "sync" and not include_sync:
            continue
        if b in {"mgmt","management"} and not include_mgmt:
            continue
        if (r.get("ipv6_addr") or "").strip():
            out.append({"interface-name": name, "ip-version": "ipv6", "redundancy-mode": "Active"})
        if (r.get("ipv4_addr") or "").strip():
            out.append({"interface-name": name, "ip-version": "ipv4", "redundancy-mode": "Active"})
    return out


# ----------------------------- validation (DB authoritative) -----------------------------

class ValidationError(Exception):
    pass

def validate_db_authoritative(mode: str, ifaces: List[Dict[str, Any]]) -> None:
    # next-hop family check
    nh_errs = []
    for it in ifaces:
        nh = (it.get("next-hop-ip") or "").strip()
        ver = (it.get("ip-version") or "").strip().lower()
        if nh and not _ip_family_ok(ver, nh):
            nh_errs.append(f"{it.get('interface-name')} {ver} -> next-hop {nh} family mismatch")
    if nh_errs:
        raise ValidationError("Next-hop IP family mismatch:\n  - " + "\n  - ".join(nh_errs))

    if mode == "spark":
        # exactly one IPv6 total, and must be Active
        v6 = [it for it in ifaces if (it.get("ip-version") or "").lower() == "ipv6"]
        if len(v6) != 1:
            lst = ", ".join([f"{x['interface-name']}({x.get('redundancy-mode','')})" for x in v6]) or "none"
            raise ValidationError(f"Spark requires exactly ONE IPv6 ELS interface, Active. Found: {len(v6)} -> {lst}")
        if str(v6[0].get("redundancy-mode") or "").lower() != "active":
            raise ValidationError(f"Spark: the single IPv6 entry must be Active (got '{v6[0].get('redundancy-mode')}').")

    # IPv4 Backup priorities must be ints and unique
    v4_backups = [it for it in ifaces
                  if (it.get("ip-version") or "").lower()=="ipv4"
                  and str(it.get("redundancy-mode") or "").lower()=="backup"]
    seen: Set[int] = set()
    dup: List[str] = []
    miss: List[str] = []
    for it in v4_backups:
        p = safe_int(it.get("priority"))
        if p is None:
            miss.append(it.get("interface-name"))
        elif p in seen:
            dup.append(f"{it.get('interface-name')} (priority {p})")
        else:
            seen.add(p)
    errs = []
    if miss:
        errs.append("Missing priority on IPv4 Backup entries: " + ", ".join(miss))
    if dup:
        errs.append("Duplicate priority values among IPv4 Backups: " + ", ".join(dup))
    if errs:
        raise ValidationError("\n".join(errs))


# ----------------------------- cluster IPv6 policy ---------------------------

def apply_cluster_ipv6_policy(ifaces: List[Dict[str, Any]], policy: str) -> List[Dict[str, Any]]:
    """
    policy:
      - 'single-active' (default): keep exactly one IPv6 (prefer first Active by DB order),
                                   drop all other IPv6; error if no IPv6 Active exists.
      - 'db': keep IPv6 entries exactly as DB says (no changes).
      - 'fail-if-multiple': raise if there is more than one IPv6.
    """
    v6_idx = [i for i,x in enumerate(ifaces) if (x.get("ip-version") or "").lower() == "ipv6"]
    if policy == "db":
        return ifaces
    if policy == "fail-if-multiple":
        if len(v6_idx) > 1:
            names = ", ".join(f"{ifaces[i]['interface-name']}({ifaces[i].get('redundancy-mode','')})" for i in v6_idx)
            raise ValidationError(f"Cluster: multiple IPv6 ELS entries found -> {names}")
        return ifaces

    # 'single-active'
    if not v6_idx:
        # zero IPv6 is acceptable
        return ifaces

    active_pick = next((i for i in v6_idx if str(ifaces[i].get("redundancy-mode","")).lower()=="active"), v6_idx[0])
    if str(ifaces[active_pick].get("redundancy-mode","")).lower() != "active":
        raise ValidationError("Cluster: no IPv6 entry marked Active in DB. "
                              "Either mark one IPv6 as Active or run with --cluster-ipv6-policy db.")
    keep = {active_pick}
    return [x for i,x in enumerate(ifaces) if (i not in v6_idx) or (i in keep)]


# ----------------------------- main -----------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Set VPN ELS from DB (authoritative) for Spark gateway or Simple Cluster.")
    # Mgmt
    ap.add_argument("--mgmt-url")
    ap.add_argument("--api-user")
    ap.add_argument("--api-pass")
    ap.add_argument("--api-key")
    ap.add_argument("--domain", default=None)
    ap.add_argument("--insecure", action="store_true")

    # DB
    ap.add_argument("--db-host")
    ap.add_argument("--db-user")
    ap.add_argument("--db-pass")
    ap.add_argument("--db-name", default="netvars")

    # Object
    ap.add_argument("--object", required=True, help="hosts.Name (gateway or cluster)")
    ap.add_argument("--type", choices=["auto","spark","cluster"], default="auto")

    # Cluster policy
    ap.add_argument("--cluster-ipv6-policy",
                    choices=["single-active","db","fail-if-multiple"],
                    default="single-active",
                    help="How to handle IPv6 ELS on clusters: "
                         "'single-active' (default) keeps one Active IPv6 and drops the rest; "
                         "'db' keeps IPv6 exactly as DB; "
                         "'fail-if-multiple' errors if DB contains >1 IPv6.")

    # Cluster option
    ap.add_argument("--vpn-domain-exclude-external-ip-addresses", action="store_true", default=False, 
                    help="[Cluster] Exclude external IPs from VPN domain")

    # Spark-only knobs
    ap.add_argument("--vpn", choices=["on","off"], default="on")
    ap.add_argument("--vpn-domain-type", choices=["manual","gateway"], default="manual")
    ap.add_argument("--vpn-domain", help="Required when Spark + manual")
    ap.add_argument("--allow-smb", dest="allow_smb", type=str2bool, nargs="?", const=True, default=True)
    ap.add_argument("--no-allow-smb", dest="allow_smb", action="store_false")

    # Fallback (only used if view has no rows)
    ap.add_argument("--vpn-auto-select", action="store_true")
    ap.add_argument("--vpn-include-internal", action="store_true", default=False)  # spark fallback
    ap.add_argument("--vpn-include-mgmt", action="store_true", default=False)      # both fallback
    ap.add_argument("--vpn-include-sync", action="store_true", default=False)      # cluster fallback

    # Task wait
    ap.add_argument("--task-timeout", type=int, default=900)
    ap.add_argument("--task-poll", type=float, default=2.0)

    ap.add_argument("--dry-run", action="store_true")

    args = ap.parse_args()

    # ENV fallback
    args.mgmt_url = env_or_arg(args.mgmt_url, "MGMT_URL")
    args.api_user = env_or_arg(args.api_user, "API_USER")
    args.api_pass = env_or_arg(args.api_pass, "API_PASS")
    args.api_key  = env_or_arg(args.api_key,  "API_KEY")
    args.domain   = env_or_arg(args.domain,   "API_DOMAIN")
    args.db_host  = env_or_arg(args.db_host,  "DB_HOST")
    args.db_user  = env_or_arg(args.db_user,  "DB_USER")
    args.db_pass  = env_or_arg(args.db_pass,  "DB_PASS")
    args.db_name  = env_or_arg(args.db_name,  "DB_NAME", "netvars")

    if not all([args.mgmt_url, (args.api_key or (args.api_user and args.api_pass)),
                args.db_host, args.db_user, args.db_pass, args.db_name, args.object]):
        missing = [k for k,v in {
            "mgmt-url": args.mgmt_url,
            "api-auth": (args.api_key or (args.api_user and args.api_pass)),
            "db-host": args.db_host, "db-user": args.db_user, "db-pass": args.db_pass,
            "db-name": args.db_name, "object": args.object
        }.items() if not v]
        raise SystemExit(f"[ERROR] Missing required args/ENV: {', '.join(missing)}")

    if args.type == "spark" and args.vpn == "on" and args.vpn_domain_type == "manual" and not args.vpn_domain:
        raise SystemExit("[ERROR] --vpn-domain is required when Spark + manual VPN domain and --vpn on")

    # DB connect
    cnx = db_connect(args.db_host, args.db_user, args.db_pass, args.db_name)

    # Mode
    mode = args.type
    if mode == "auto":
        mode = detect_object_type(cnx, args.db_name, args.object)  # 'spark' or 'cluster'

    # 1) Pull DB rows (authoritative)
    rows = fetch_vpn_interfaces_from_db(cnx, args.db_name, args.object)
    built_ifaces: List[Dict[str, Any]] = []
    for r in rows:
        name = (r.get("interface_name") or "").strip()
        ver  = (r.get("ip_version") or "").strip().lower()
        if not name or ver not in {"ipv4","ipv6"}:
            continue
        item: Dict[str, Any] = {
            "interface-name": name,
            "ip-version": ver,
            "redundancy-mode": (r.get("redundancy_mode") or "Active") or "Active",
        }
        nh = (r.get("next_hop_ip") or "").strip()
        if nh:
            item["next-hop-ip"] = nh
        # keep DB priority as-is (parse to int when valid, keep raw for error message otherwise)
        pri_raw = r.get("priority")
        if pri_raw is not None and str(pri_raw).strip() != "":
            p = safe_int(pri_raw)
            item["priority"] = p if p is not None else pri_raw
        built_ifaces.append(item)

    # 2) If no DB rows and fallback requested -> build minimal actives (no priorities)
    if not built_ifaces and args.vpn_auto_select:
        ifrows = fetch_interfaces(cnx, args.db_name, args.object)
        if mode == "spark":
            built_ifaces = build_auto_for_spark(ifrows, include_internal=args.vpn_include_internal,
                                                include_mgmt=args.vpn_include_mgmt)
        else:
            built_ifaces = build_auto_for_cluster(ifrows, include_mgmt=args.vpn_include_mgmt,
                                                  include_sync=args.vpn_include_sync)

    # 3) Apply cluster IPv6 policy before validation (so validation runs on final payload)
    if built_ifaces and mode == "cluster":
        built_ifaces = apply_cluster_ipv6_policy(built_ifaces, args.cluster_ipv6_policy)

    # 4) Validate against platform rules
    if built_ifaces:
        validate_db_authoritative(mode, built_ifaces)
    else:
        print("[INFO] No VPN interfaces found in DB and no auto-select fallback used.")

    # 5) Build payloads
    if mode == "spark":
        if args.vpn == "off":
            vpn_settings: Dict[str, Any] = {"vpn": False, "allow-smb": bool(args.allow_smb)}
        else:
            vpn_settings = {
                "vpn": True,
                "allow-smb": bool(args.allow_smb),
                "vpn-settings": {"vpn-domain-type": args.vpn_domain_type}
            }
            if args.vpn_domain_type == "manual":
                vpn_settings["vpn-settings"]["vpn-domain"] = args.vpn_domain or ""
            if built_ifaces:
                vpn_settings["vpn-settings"]["interfaces"] = built_ifaces
        payload = {"name": args.object, **vpn_settings}
        api_method = "set-simple-gateway"
    else:
        vpn_settings = {
            "vpn": True,
            "vpn-settings": {
                "vpn-domain-exclude-external-ip-addresses": bool(args.vpn_domain_exclude_external_ip_addresses)
            }
        }
        if built_ifaces:
            vpn_settings["vpn-settings"]["interfaces"] = built_ifaces
        payload = {"name": args.object, **vpn_settings}
        api_method = "set-simple-cluster"

    # print(f"\n=== Payload preview ({api_method}) ===")
    # print(json.dumps(payload, indent=2))

    if args.dry_run:
        print("\n[DRY RUN] No API calls made.")
        return

    api = CPMgmt(args.mgmt_url, args.api_user, args.api_pass, args.domain, verify_ssl=not args.insecure, api_key=args.api_key)

    try:
        api.login()
        print("[OK] Logged in.")

        # 1) set object and wait for its async task (if any)
        if api_method == "set-simple-gateway":
            r_set = api.set_simple_gateway(args.object, payload)
        else:
            r_set = api.set_simple_cluster(args.object, payload)
        # print(f"[OK] {api_method}:", json.dumps(r, indent=2))

        set_tid = api._extract_task_id(r_set)
        if set_tid:
            print(f"[INFO] Waiting for {api_method} task {set_tid} to finish ...")
            ok_set = api.wait_for_task_success(set_tid, timeout=args.task_timeout, poll_interval=args.task_poll)
            if not ok_set:
                raise SystemExit(1)

        # 2) publish and wait
        ok_pub, pub_doc = api.publish_and_wait(timeout=args.task_timeout, poll_interval=args.task_poll)
        if not ok_pub:
            raise SystemExit(1)

    except requests.HTTPError as e:
        try:
            print("[ERROR] server:", json.dumps(e.response.json(), indent=2))  # type: ignore[attr-defined]
        except Exception:
            pass
        raise
    finally:
        api.logout()
        print("[OK] Logged out.")

if __name__ == "__main__":
    try:
        main()
    except ValidationError as ve:
        print(f"[VALIDATION ERROR]\n{ve}")
        sys.exit(2)
    except KeyboardInterrupt:
        print("\n[INTERRUPTED]")
        sys.exit(130)
    except requests.HTTPError as e:
        print(f"[HTTP ERROR] {e}")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
