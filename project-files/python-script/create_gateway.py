#!/usr/bin/env python3
"""
Create a Gaia Embedded (Spark) simple-gateway from the 'netvars' DB, then publish and wait.

- Pulls base IPs and interface table from MySQL 'hosts' and 'host_interfaces'
- Sets allow-smb, firewall, hardware, portal URL, interfaces
- (Optional) flips securityBladesTopologyMode to TOPOLOGY_TABLE on the proper UID
"""

from __future__ import annotations
import argparse, os, sys, json
from typing import List, Dict, Any, Optional, Tuple, Set

import mysql.connector
from cp_mgmt import CPMgmt

# ---------- small helpers ----------
def str2bool(v):
    if isinstance(v, bool):
        return v
    return str(v).strip().lower() in ("1", "true", "t", "yes", "y", "on")

def env_or_arg(val: Optional[str], env: str, default: Optional[str]=None) -> Optional[str]:
    return val if (val is not None and str(val) != "") else os.environ.get(env, default)

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

def has_column(cnx, table: str, column: str, schema: str) -> bool:
    cur = cnx.cursor()
    cur.execute(
        """
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema=%s AND table_name=%s AND column_name=%s
        LIMIT 1
        """,
        (schema, table, column),
    )
    ok = cur.fetchone() is not None
    cur.close()
    return ok

def mk_ifname(base: str, vlan: Optional[str]) -> str:
    base = (base or "").strip()
    if not base:
        return ""
    return f"{base}.{str(vlan).strip()}" if vlan and str(vlan).strip() else base

def is_mgmt_name(n: str) -> bool:
    return (n or "").strip().lower() in {"mgmt", "management"}

def default_topology_for_name(base_if: str, vlan: Optional[str]) -> str:
    b = (base_if or "").strip().lower()
    if is_mgmt_name(base_if) or b.startswith("lan"):
        return "INTERNAL"
    if (b.startswith("wan") or b.startswith("eth")) and (vlan and str(vlan).strip()):
        return "EXTERNAL"
    return "EXTERNAL"

def antispoof_from_val(v: Optional[str]) -> Tuple[bool, Optional[str]]:
    vv = (v or "detect").strip().lower()
    if vv == "off":
        return False, None
    if vv not in {"detect", "prevent"}:
        vv = "detect"
    return True, vv

# ---------- DB fetch ----------
def fetch_gateway_row(cnx, name: str):
    sql = """
      SELECT Name, `HW-Type` AS hw_type, template, mgmt_IPv4_addr, mgmt_IPv6_addr,
             mgmt_IPv6_prefix, otp
        FROM hosts
       WHERE Name=%s
    """
    row = q_one(cnx, sql, (name,))
    if not row:
        raise SystemExit(f"[ERROR] Gateway '{name}' not found in hosts.")
    return row

def select_iface_cols(cnx, dbname: str) -> str:
    cols = [
        "interface", "vlan",
        "ipv4_addr", "`IPv4_mask-len` AS v4len",
        "ipv6_addr", "`prefix` AS v6len",
        "topology" if has_column(cnx, "host_interfaces", "topology", dbname) else "NULL AS topology",
        "leads_to_dmz" if has_column(cnx, "host_interfaces", "leads_to_dmz", dbname) else "0 AS leads_to_dmz",
        "anti_spoof_action" if has_column(cnx, "host_interfaces", "anti_spoof_action", dbname) else "'detect' AS anti_spoof_action",
    ]
    return ", ".join(cols)

def fetch_interfaces(cnx, dbname: str, gw_name: str) -> List[Dict[str, Any]]:
    sql = f"""
      SELECT {select_iface_cols(cnx, dbname)}
        FROM host_interfaces
       WHERE Name=%s
       ORDER BY id
    """
    return q_all(cnx, sql, (gw_name,))

def build_interface_entries(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    seen: Set[str] = set()
    for r in rows:
        base = (r.get("interface") or "").strip()
        if not base:
            continue
        name = mk_ifname(base, r.get("vlan"))
        if not name or name in seen:
            continue
        seen.add(name)

        ent: Dict[str, Any] = {"name": name}

        v4 = (r.get("ipv4_addr") or "").strip()
        v6 = (r.get("ipv6_addr") or "").strip()
        if v4 and str(r.get("v4len") or "").strip().isdigit():
            ent["ipv4-address"] = v4
            ent["ipv4-mask-length"] = int(r["v4len"])
        if v6 and str(r.get("v6len") or "").strip().isdigit():
            ent["ipv6-address"] = v6
            ent["ipv6-mask-length"] = int(r["v6len"])

        topo = (r.get("topology") or "").strip().upper()
        if topo not in {"INTERNAL", "EXTERNAL"}:
            topo = default_topology_for_name(base, r.get("vlan"))
        ent["topology"] = topo
        ent["topology-settings"] = {
            "ip-address-behind-this-interface": "network defined by the interface ip and net mask",
            "interface-leads-to-dmz": bool(int(r.get("leads_to_dmz") or 0)),
        }
        as_enabled, as_action = antispoof_from_val(r.get("anti_spoof_action"))
        ent["anti-spoofing"] = as_enabled
        if as_enabled:
            ent["anti-spoofing-settings"] = {"action": as_action}
        out.append(ent)
    return out

# ---------- main ----------
def main():
    ap = argparse.ArgumentParser(description="Create Gaia Embedded (Spark) simple-gateway from MySQL 'netvars'.")
    # Mgmt
    ap.add_argument("--mgmt-url")
    ap.add_argument("--api-user")
    ap.add_argument("--api-pass")
    ap.add_argument("--api-key", help="Alternative to user/password")
    ap.add_argument("--domain", default=None, help="For MDS / domains")
    ap.add_argument("--insecure", action="store_true")

    # DB
    ap.add_argument("--db-host")
    ap.add_argument("--db-user")
    ap.add_argument("--db-pass")
    ap.add_argument("--db-name", default="netvars")

    # Object selection
    ap.add_argument("--gateway", help="Gateway name in hosts.Name (e.g., vpn-gw-1)")

    # Properties
    ap.add_argument("--version", default="R82")
    ap.add_argument("--os-name", default="Gaia Embedded")
    ap.add_argument("--color", default="Red")
    ap.add_argument("--firewall", choices=["on","off"], default="on")
    ap.add_argument("--hardware-value", help="Override hardware string (else hosts.`HW-Type`).")
    ap.add_argument("--allow-smb", dest="allow_smb", type=str2bool, nargs="?", const=True, default=True)
    ap.add_argument("--no-allow-smb", dest="allow_smb", action="store_false")

    # Task wait knobs
    ap.add_argument("--task-timeout", type=int, default=900, help="Seconds to wait for publish task")
    ap.add_argument("--task-poll", type=float, default=2.0, help="Seconds between show-task polls")

    # Behavior
    ap.add_argument("--flip-topology-table", action="store_true", default=True,
                    help="Flip securityBladesTopologyMode to TOPOLOGY_TABLE (default true).")
    ap.add_argument("--no-flip-topology-table", dest="flip_topology_table", action="store_false")
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
    args.gateway  = env_or_arg(args.gateway,  "GATEWAY")

    required = [
        args.mgmt_url,
        (args.api_key or (args.api_user and args.api_pass)),
        args.db_host, args.db_user, args.db_pass, args.db_name,
        args.gateway
    ]
    if not all(required):
        missing = [k for k,v in {
            "mgmt-url": args.mgmt_url,
            "api-auth": (args.api_key or (args.api_user and args.api_pass)),
            "db-host": args.db_host, "db-user": args.db_user, "db-pass": args.db_pass,
            "db-name": args.db_name, "gateway": args.gateway
        }.items() if not v]
        raise SystemExit(f"[ERROR] Missing required args/ENV: {', '.join(missing)}")

    # DB
    cnx = db_connect(args.db_host, args.db_user, args.db_pass, args.db_name)
    gw = fetch_gateway_row(cnx, args.gateway)
    iface_rows = fetch_interfaces(cnx, args.db_name, args.gateway)
    iface_entries = build_interface_entries(iface_rows)

    # Determine IPs
    ipv4_top = gw.get("mgmt_IPv4_addr") or ""
    ipv6_top = gw.get("mgmt_IPv6_addr") or ""
    if not ipv4_top:
        for e in iface_entries:
            if "ipv4-address" in e:
                ipv4_top = e["ipv4-address"]; break
    if not ipv6_top:
        for e in iface_entries:
            if "ipv6-address" in e:
                ipv6_top = e["ipv6-address"]; break

    portal_url = f"https://[{ipv6_top}]/" if ipv6_top else (f"https://{ipv4_top}/" if ipv4_top else "https://0.0.0.0/")

    hardware = (args.hardware_value or gw.get("hw_type") or "").strip()

    add_payload: Dict[str, Any] = {
        "name": gw["Name"],
        "color": args.color,
        "version": args.version,
        "allow-smb": bool(args.allow_smb),
        "os-name": args.os_name,
        **({"hardware": hardware} if hardware else {}),
        **({"ipv4-address": ipv4_top} if ipv4_top else {}),
        **({"ipv6-address": ipv6_top} if ipv6_top else {}),
        "firewall": (args.firewall == "on"),
        "one-time-password": gw["otp"],
        "trust-settings": {"initiation-phase": "now"},
        "platform-portal-settings": {"portal-web-settings": {"main-url": portal_url}},
        "interfaces": iface_entries
    }

    print("\n=== add-simple-gateway payload ===")
    print(json.dumps(add_payload, indent=2))

    if args.dry_run:
        print("\n[DRY RUN] No API calls made.")
        return

    api = CPMgmt(
        args.mgmt_url,
        user=args.api_user,
        password=args.api_pass,
        domain=args.domain,
        verify_ssl=not args.insecure,
        api_key=args.api_key,
    )

    try:
        api.login()
        print("[OK] Logged in.")

        r_add = api.add_simple_gateway(add_payload)
        print("[OK] add-simple-gateway:", json.dumps(r_add, indent=2))
        
        # Optional: flip topology mode to TOPOLOGY_TABLE on the correct UID
        if args.flip_topology_table:
            try:
                sg = api.show_simple_gateway(gw["Name"])
                gw_uid = sg.get("uid")
                flipped = 0
                if gw_uid:
                    try:
                        api.set_generic_object(gw_uid, securityBladesTopologyMode="TOPOLOGY_TABLE")
                        flipped += 1
                    except Exception as e:
                        print(f"[WARN] set-generic-object (primary uid) failed: {e}")

                if flipped == 0:
                    g = api.show_generic_objects(name=gw["Name"])
                    objects = g.get("objects", [])
                    for obj in objects:
                        if (obj.get("name") == gw["Name"]) and (obj.get("class-name") in {"simple-gateway", "gateway"}):
                            uid = obj.get("uid")
                            if uid:
                                try:
                                    api.set_generic_object(uid, securityBladesTopologyMode="TOPOLOGY_TABLE")
                                    flipped += 1
                                except Exception as e:
                                    print(f"[WARN] set-generic-object failed for uid {uid}: {e}")
                    if flipped == 0 and objects:
                        uid = objects[0].get("uid")
                        if uid:
                            try:
                                api.set_generic_object(uid, securityBladesTopologyMode="TOPOLOGY_TABLE")
                                flipped += 1
                            except Exception as e:
                                print(f"[WARN] set-generic-object failed for fallback uid {uid}: {e}")
                print(f"[OK] securityBladesTopologyMode updated on {flipped} object(s).")
            except Exception as e:
                print(f"[WARN] Could not flip securityBladesTopologyMode: {e}")

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
    except requests.HTTPError as e:  # type: ignore[name-defined]
        print(f"[HTTP ERROR] {e}")
        sys.exit(1)
    except Exception as e:
        print(f"[ERROR] {e}")
        sys.exit(1)
