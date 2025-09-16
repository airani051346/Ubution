#!/usr/bin/env python3
"""
Create a classic Gaia Simple Cluster object from the 'netvars' DB, then publish & wait.

- Builds cluster interfaces (cluster/sync) from host_interfaces with per-row overrides.
- Resolves members (from CLI or hosts.member_of), builds member interface lists.
- This script creates the cluster; it does NOT set vpn-settings.interfaces (use set_cluster_vpn.py for that).
"""

from __future__ import annotations
import argparse, json, os, sys, re
from typing import List, Dict, Any, Optional, Set, Tuple

import requests, mysql.connector
from cp_mgmt import CPMgmt

# ----------------------------- Utilities -------------------------------------

def env_or_arg(val: Optional[str], env_key: str, default: Optional[str]=None) -> Optional[str]:
    return val if (val is not None and str(val) != "") else os.environ.get(env_key, default)

def env_bool(current: bool, env_key: str, default: Optional[bool] = None) -> bool:
    val = os.environ.get(env_key, None)
    if val is None:
        return current if default is None else default
    return str(val).strip().lower() in {"1","true","yes","on"}

def nonempty(v) -> bool:
    return v is not None and str(v).strip() != ""

def safe_int(s: Any) -> Optional[int]:
    try:
        return int(str(s).strip())
    except Exception:
        return None

def mk_ifname(base: str, vlan: Optional[str]) -> str:
    base = (base or "").strip()
    if not base:
        return ""
    return f"{base}.{str(vlan).strip()}" if vlan and str(vlan).strip() else base

def is_mgmt_interface_name(name: str) -> bool:
    return (name or "").strip().lower() in {"mgmt", "management"}

def find_sync_interfaces(rows: List[Dict[str, Any]], sync_regex: str) -> Set[str]:
    pat = re.compile(sync_regex, re.IGNORECASE)
    return { (r.get("interface") or "").strip() for r in rows if pat.search((r.get("interface") or "")) }

# ----------------------------- DB Access -------------------------------------

def db_connect(host, user, password, db):
    return mysql.connector.connect(host=host, user=user, password=password, database=db)

def has_column(cnx, table: str, column: str, schema: str) -> bool:
    q = """
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema=%s AND table_name=%s AND column_name=%s
        LIMIT 1
    """
    cur = cnx.cursor()
    cur.execute(q, (schema, table, column))
    out = cur.fetchone() is not None
    cur.close()
    return out

def fetch_cluster_row(cnx, cluster_name: str):
    q = """
        SELECT Name, `HW-Type` AS hw_type, template,
               mgmt_IPv4_addr, mgmt_IPv6_addr, mgmt_IPv6_prefix
          FROM hosts
         WHERE Name = %s
    """
    cur = cnx.cursor(dictionary=True)
    cur.execute(q, (cluster_name,))
    row = cur.fetchone()
    cur.close()
    if not row:
        raise SystemExit(f"[ERROR] Cluster '{cluster_name}' not found in hosts.")
    return row

def select_for_interfaces(cnx, dbname: str) -> str:
    cols = [
        "interface", "vlan",
        "ipv4_addr", "`IPv4_mask-len` AS v4len",
        "ipv6_addr", "`prefix` AS v6len"
    ]
    cols.append("topology" if has_column(cnx, "host_interfaces", "topology", dbname) else "NULL AS topology")
    cols.append("leads_to_dmz" if has_column(cnx, "host_interfaces", "leads_to_dmz", dbname) else "0 AS leads_to_dmz")
    cols.append("anti_spoof_action" if has_column(cnx, "host_interfaces", "anti_spoof_action", dbname) else "'detect' AS anti_spoof_action")
    return ", ".join(cols)

def fetch_cluster_interfaces(cnx, dbname: str, cluster_name: str):
    q = f"""
        SELECT {select_for_interfaces(cnx, dbname)}
          FROM host_interfaces
         WHERE Name = %s
         ORDER BY id
    """
    cur = cnx.cursor(dictionary=True)
    cur.execute(q, (cluster_name,))
    rows = cur.fetchall() or []
    cur.close()
    return rows

def fetch_members_from_names(cnx, names: List[str]):
    q = "SELECT Name, mgmt_IPv4_addr, mgmt_IPv6_addr, otp, member_of FROM hosts WHERE Name IN (" + ",".join(["%s"]*len(names)) + ") ORDER BY Name"
    cur = cnx.cursor(dictionary=True)
    cur.execute(q, tuple(names))
    rows = cur.fetchall() or []
    cur.close()
    return rows

def fetch_members(cnx, cluster_name: str):
    q = """
        SELECT Name, mgmt_IPv4_addr, mgmt_IPv6_addr, otp, member_of
          FROM hosts
         WHERE member_of = %s
         ORDER BY Name
    """
    cur = cnx.cursor(dictionary=True)
    cur.execute(q, (cluster_name,))
    rows = cur.fetchall() or []
    cur.close()
    return rows

def fetch_member_interfaces(cnx, dbname: str, member_name: str):
    q = f"""
        SELECT {select_for_interfaces(cnx, dbname)}
          FROM host_interfaces
         WHERE Name = %s
         ORDER BY id
    """
    cur = cnx.cursor(dictionary=True)
    cur.execute(q, (member_name,))
    rows = cur.fetchall() or []
    cur.close()
    return rows

# ----------------------------- Builders --------------------------------------

def _normalize_topology(row_topo: Optional[str], default_external: bool, base_if_name: str) -> str:
    if row_topo and str(row_topo).strip().upper() in {"INTERNAL","EXTERNAL"}:
        return str(row_topo).strip().upper()
    if is_mgmt_interface_name(base_if_name):
        return "INTERNAL"
    return "EXTERNAL" if default_external else "INTERNAL"

def _antispoof_settings(row_action: Optional[str]) -> (bool, Optional[str]):
    val = (row_action or "detect").strip().lower()
    if val == "off":
        return False, None
    if val not in {"detect","prevent"}:
        val = "detect"
    return True, val

def build_cluster_interfaces(
    c_rows: List[Dict[str, Any]],
    default_topology_external: bool,
    sync_names: Set[str],
) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    seen: Set[str] = set()

    for r in c_rows:
        base_if = (r.get("interface") or "").strip()
        name = mk_ifname(base_if, r.get("vlan"))
        if not name or name in seen:
            continue
        seen.add(name)

        # Sync interfaces at cluster-level
        if name in sync_names or re.match(r"^sync$", base_if, flags=re.I):
            out.append({"name": name, "interface-type": "sync"})
            continue

        entry: Dict[str, Any] = {"name": name, "interface-type": "cluster"}

        v4len = safe_int(r.get("v4len"))
        if nonempty(r.get("ipv4_addr")) and v4len is not None:
            entry["ipv4-address"] = str(r["ipv4_addr"]).strip()
            entry["ipv4-mask-length"] = v4len

        v6len = safe_int(r.get("v6len"))
        if nonempty(r.get("ipv6_addr")) and v6len is not None:
            entry["ipv6-address"] = str(r["ipv6_addr"]).strip()
            entry["ipv6-mask-length"] = v6len

        if not any(k in entry for k in ("ipv4-address", "ipv6-address")) and not is_mgmt_interface_name(base_if):
            continue

        topo = _normalize_topology(r.get("topology"), default_topology_external, base_if)
        leads_dmz = bool(int(r.get("leads_to_dmz") or 0))

        entry["topology"] = topo
        entry["topology-settings"] = {
            "ip-address-behind-this-interface": "network defined by the interface ip and net mask",
            "interface-leads-to-dmz": leads_dmz
        }

        as_enabled, as_action = _antispoof_settings(r.get("anti_spoof_action"))
        entry["anti-spoofing"] = as_enabled
        if as_enabled:
            entry["anti-spoofing-settings"] = {"action": as_action}

        out.append(entry)

    return out

def build_member_interfaces(m_rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    seen: Set[str] = set()
    for r in m_rows:
        name = mk_ifname(r.get("interface"), r.get("vlan"))
        if not name or name in seen:
            continue
        seen.add(name)
        ent: Dict[str, Any] = {"name": name}
        v4len = safe_int(r.get("v4len"))
        if nonempty(r.get("ipv4_addr")) and v4len is not None:
            ent["ipv4-address"] = str(r["ipv4_addr"]).strip()
            ent["ipv4-mask-length"] = v4len
        v6len = safe_int(r.get("v6len"))
        if nonempty(r.get("ipv6_addr")) and v6len is not None:
            ent["ipv6-address"] = str(r["ipv6_addr"]).strip()
            ent["ipv6-mask-length"] = v6len
        out.append(ent)
    return out

# ----------------------------- Main ------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Create a Check Point Simple Cluster from MySQL 'netvars' DB.")
    # Management
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

    # Object selection
    ap.add_argument("--cluster")

    # Defaults / features
    ap.add_argument("--version", default="R82")
    ap.add_argument("--os-name", default="Gaia")
    ap.add_argument("--cluster-mode", default="cluster-xl-ha")
    ap.add_argument("--color", default="Yellow")
    ap.add_argument("--firewall", choices=["on","off"], default="on")
    ap.add_argument("--vpn", choices=["on","off"], default="on")
    ap.add_argument("--ips", choices=["on","off"], default="on")
    ap.add_argument("--use-virtual-mac", action="store_true")
    ap.add_argument("--member-recovery-mode", default="according-to-priority")
    ap.add_argument("--state-sync-delayed", action="store_true")
    ap.add_argument("--hardware-value")

    # Members
    ap.add_argument("--members", help="Comma-separated gateway names (override DB hosts.member_of).")
    ap.add_argument("--enforce-member-of", action="store_true", default=False)

    # Inference knobs
    ap.add_argument("--topology-default", choices=["external","internal"], default="external")
    ap.add_argument("--sync-match", default=r"^sync$")

    # Task wait
    ap.add_argument("--task-timeout", type=int, default=900)
    ap.add_argument("--task-poll", type=float, default=2.0)

    ap.add_argument("--dry-run", action="store_true")

    args = ap.parse_args()

    # ENV fallbacks
    args.mgmt_url = env_or_arg(args.mgmt_url, "MGMT_URL")
    args.api_user = env_or_arg(args.api_user, "API_USER")
    args.api_pass = env_or_arg(args.api_pass, "API_PASS")
    args.api_key  = env_or_arg(args.api_key,  "API_KEY")
    args.domain   = env_or_arg(args.domain,   "API_DOMAIN")
    args.db_host  = env_or_arg(args.db_host,  "DB_HOST")
    args.db_user  = env_or_arg(args.db_user,  "DB_USER")
    args.db_pass  = env_or_arg(args.db_pass,  "DB_PASS")
    args.db_name  = env_or_arg(args.db_name,  "DB_NAME", "netvars")
    args.cluster  = env_or_arg(args.cluster,  "CLUSTER")
    args.members  = env_or_arg(args.members,  "MEMBERS")
    args.enforce_member_of = env_bool(args.enforce_member_of, "ENFORCE_MEMBER_OF")

    if not all([args.mgmt_url, (args.api_key or (args.api_user and args.api_pass)),
                args.db_host, args.db_user, args.db_pass, args.db_name, args.cluster]):
        missing = [k for k,v in {
            "mgmt-url": args.mgmt_url,
            "api-auth": (args.api_key or (args.api_user and args.api_pass)),
            "db-host": args.db_host, "db-user": args.db_user, "db-pass": args.db_pass,
            "db-name": args.db_name, "cluster": args.cluster
        }.items() if not v]
        raise SystemExit(f"[ERROR] Missing required args/ENV: {', '.join(missing)}")

    # DB
    cnx = db_connect(args.db_host, args.db_user, args.db_pass, args.db_name)

    # Cluster + interfaces
    cl = fetch_cluster_row(cnx, args.cluster)
    cl_if_rows = fetch_cluster_interfaces(cnx, args.db_name, args.cluster)

    # Members (explicit or from DB)
    if args.members:
        selected = [n.strip() for n in args.members.split(",") if n.strip()]
        m_rows = fetch_members_from_names(cnx, selected)
        missing = set(selected) - {m["Name"] for m in m_rows}
        if missing:
            raise SystemExit(f"[ERROR] Not found in hosts: {', '.join(sorted(missing))}")
        if args.enforce_member_of:
            bad = [m["Name"] for m in m_rows if (m.get("member_of") or "").strip() != args.cluster]
            if bad:
                raise SystemExit(f"[ERROR] Not marked member_of={args.cluster}: {', '.join(bad)}")
        members = m_rows
    else:
        members = fetch_members(cnx, args.cluster)
        if len(members) < 2:
            print(f"[WARN] Cluster '{args.cluster}' has {len(members)} member(s); expected >= 2.")

    # Member interfaces
    all_member_if_rows: Dict[str, List[Dict[str, Any]]] = {
        m["Name"]: fetch_member_interfaces(cnx, args.db_name, m["Name"]) for m in members
    }

    # Sync candidates (intersection across members)
    sync_sets = [find_sync_interfaces(rows, args.sync_match) for rows in all_member_if_rows.values()]
    sync_candidates: Set[str] = set.intersection(*sync_sets) if sync_sets else set()

    # Build cluster interfaces and ensure sync present
    cluster_interfaces = build_cluster_interfaces(
        cl_if_rows,
        default_topology_external=(args.topology_default == "external"),
        sync_names=sync_candidates
    )
    cluster_if_names = {i["name"] for i in cluster_interfaces}
    for sname in sync_candidates:
        if sname not in cluster_if_names:
            cluster_interfaces.append({"name": sname, "interface-type": "sync"})

    # Member entries
    member_entries = []
    for m in members:
        m_if = build_member_interfaces(all_member_if_rows[m["Name"]])
        ent: Dict[str, Any] = {
            "name": m["Name"],
            **({"ipv4-address": m["mgmt_IPv4_addr"]} if nonempty(m.get("mgmt_IPv4_addr")) else {}),
            **({"ipv6-address": m["mgmt_IPv6_addr"]} if nonempty(m.get("mgmt_IPv6_addr")) else {}),
            "one-time-password": m["otp"],
            "interfaces": m_if
        }
        member_entries.append(ent)

    hardware = (args.hardware_value or (cl.get("hw_type") or "")).strip()

    add_payload: Dict[str, Any] = {
        "name": cl["Name"],
        "color": args.color,
        "version": args.version,
        "os-name": args.os_name,
        **({"hardware": hardware} if hardware else {}),
        "cluster-mode": args.cluster_mode,
        "firewall": args.firewall == "on",
        "vpn": args.vpn == "on",
        "ips": args.ips == "on",
        **({"ipv4-address": cl["mgmt_IPv4_addr"]} if nonempty(cl.get("mgmt_IPv4_addr")) else {}),
        **({"ipv6-address": cl["mgmt_IPv6_addr"]} if nonempty(cl.get("mgmt_IPv6_addr")) else {}),
        "cluster-settings": {
            "use-virtual-mac": bool(args.use_virtual_mac),
            "member-recovery-mode": args.member_recovery_mode,
            "state-synchronization": {"delayed": bool(args.state_sync_delayed)},
        },
        "interfaces": cluster_interfaces,
        "members": member_entries,
    }

    print("\n=== add-simple-cluster payload ===")
    print(json.dumps(add_payload, indent=2))

    if args.dry_run:
        print("\n[DRY RUN] No API calls made.")
        return

    api = CPMgmt(args.mgmt_url, args.api_user, args.api_pass, args.domain, verify_ssl=not args.insecure, api_key=args.api_key)
    try:
        api.login()
        print("[OK] Logged in.")

        resp = api.add_simple_cluster(add_payload)
        print("[OK] add-simple-cluster:", json.dumps(resp, indent=2))

        ok, _ = api.publish_and_wait(timeout=args.task_timeout, poll_interval=args.task_poll)
        if not ok:
            raise SystemExit(1)
    finally:
        api.logout()
        print("[OK] Logged out.")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[INTERRUPTED]")
        sys.exit(130)
    except requests.HTTPError as e:
        print(f"[HTTP ERROR] {e}")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
