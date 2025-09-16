#!/usr/bin/env python3
import argparse, os, re, sys
from typing import Any, Dict, List, Optional, Tuple

# ---------- DB helpers (mysql-connector-python OR PyMySQL) ----------
def _connect_mysql(host: str, port: int, db: str, user: str, password: str):
    try:
        import mysql.connector  # type: ignore
        conn = mysql.connector.connect(
            host=host, port=port, database=db, user=user, password=password
        )
        def _query(sql: str, params: Tuple[Any, ...] = ()):
            cur = conn.cursor(dictionary=True)
            cur.execute(sql, params)
            rows = cur.fetchall()
            cur.close()
            return rows
        return conn, _query
    except ImportError:
        try:
            import pymysql  # type: ignore
            from pymysql.cursors import DictCursor  # type: ignore
            conn = pymysql.connect(
                host=host, port=port, db=db, user=user, password=password,
                autocommit=True, cursorclass=DictCursor
            )
            def _query(sql: str, params: Tuple[Any, ...] = ()):
                with conn.cursor() as cur:
                    cur.execute(sql, params)
                    return cur.fetchall()
            return conn, _query
        except ImportError:
            print("ERROR: Install either 'mysql-connector-python' or 'PyMySQL'.", file=sys.stderr)
            sys.exit(2)

# ---------- utils ----------
_norm_re = re.compile(r'[^0-9A-Za-z_]+')
def norm_key(s: str) -> str:
    return _norm_re.sub('_', s.strip()).lower()

def has_col(cols: List[str], name: str) -> Optional[str]:
    name_l = name.lower()
    for c in cols:
        if c.lower() == name_l:
            return c
    return None

def describe_columns(query, table: str) -> List[str]:
    rows = query(f"SHOW COLUMNS FROM `{table}`")
    return [r['Field'] for r in rows]

def pick_name_column(cols: List[str]) -> Optional[str]:
    for cand in ('Name', 'name'):
        c = has_col(cols, cand)
        if c:
            return c
    return None

def build_row_view(row: Dict[str, Any]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for k, v in row.items():
        s = '' if v is None else str(v)
        out[k] = s
        out[norm_key(k)] = s
    return out

# ---------- template lookup (using query() helper) ----------
def get_template_name_from_host_q(query, host_name: str) -> str:
    rows = query("SELECT `template` FROM `hosts` WHERE `Name`=%s LIMIT 1", (host_name,))
    tpl = (rows and rows[0].get('template')) or ''
    if not tpl:
        raise SystemExit(f"[ERROR] Host '{host_name}' not found or 'template' empty in hosts table.")
    return tpl

def fetch_template_text_q(query, tpl_name: str) -> str:
    rows = query(
        "SELECT `content` AS content FROM `templates` "
        "WHERE LOWER(TRIM(`name`))=LOWER(TRIM(%s)) LIMIT 1",
        (tpl_name,)
    )
    if rows and rows[0].get('content'):
        return str(rows[0]['content'])
    rows = query(
        "SELECT `Content` AS content FROM `Templates` "
        "WHERE LOWER(TRIM(`Name`))=LOWER(TRIM(%s)) LIMIT 1",
        (tpl_name,)
    )
    if rows and rows[0].get('content'):
        return str(rows[0]['content'])
    raise SystemExit(f"[ERROR] Template '{tpl_name}' not found (in templates or Templates).")

# ---------- parsing/rendering ----------
RE_LOOP_FULL    = re.compile(r'(?s)[ \t]*::Loop[^\n]*\n.*?\n[ \t]*::LoopEND')
RE_LOOP_INNER   = re.compile(r'(?s)[ \t]*::Loop(?:\s+table=([A-Za-z0-9_]+))?[^\n]*\n(.*?)\n[ \t]*::LoopEND')

RE_TOK_3        = re.compile(r'\{\{\s*([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_]+)\s*:\s*([^}\s]+)\s*\}\}')
RE_TOK_2        = re.compile(r'\{\{\s*([A-Za-z0-9_]+)\s*:\s*([^}\s]+)\s*\}\}')
RE_TOK_BARE     = re.compile(r'\{\{\s*([A-Za-z0-9_\-]+)\s*\}\}')
RE_TOK_EXPERTPW = re.compile(r"\{\{\s*expertpw\s*:\s*([A-Za-z0-9_\-]+)\s*\}\}")

def resolve_expertpw_shortcuts(query, text: str) -> str:
    """
    Replace {{expertpw:NAME}} using table `expertpw`.
    Accepts value column among: secret, value, password, pwd. Keyed by Name/name.
    """
    needed = {m for (m,) in RE_TOK_EXPERTPW.findall(text)}
    if not needed:
        return text

    cols = describe_columns(query, 'expertpw')
    for want in ['secret', 'value', 'password', 'pwd']:
        if has_col(cols, want):
            value_col = has_col(cols, want)
            break
    else:
        raise SystemExit("[ERROR] Table 'expertpw' must have one of: secret/value/password/pwd")

    name_col = has_col(cols, 'Name') or has_col(cols, 'name') or 'Name'

    placeholders = ",".join(["%s"] * len(needed))
    sql = f"SELECT `{name_col}` AS k, `{value_col}` AS v FROM `expertpw` WHERE `{name_col}` IN ({placeholders})"
    rows = query(sql, tuple(needed))
    m = {r['k']: ('' if r['v'] is None else str(r['v'])) for r in rows}

    def repl(match):
        key = match.group(1)
        return m.get(key, '')

    return RE_TOK_EXPERTPW.sub(repl, text)

def replace_with_row(text: str, row_view: Dict[str, str],
                     chosen_table: Optional[str], db_name: str) -> str:
    out = text
    # 3-part inside loop (only if table matches)
    for db, tbl, col in RE_TOK_3.findall(out):
        if db.lower() != db_name.lower():
            continue
        if not chosen_table or tbl.lower() != chosen_table.lower():
            continue
        key_raw, key_norm = col, norm_key(col)
        if key_raw in row_view or key_norm in row_view:
            val = row_view.get(key_raw, row_view.get(key_norm, ''))
            patt = re.compile(r'\{\{\s*'+re.escape(db)+r'\s*:\s*'+re.escape(tbl)+r'\s*:\s*'+re.escape(col)+r'\s*\}\}')
            out = patt.sub(val, out)
    # 2-part inside loop (only if table matches)
    for tbl, col in RE_TOK_2.findall(out):
        if chosen_table and tbl.lower() == chosen_table.lower():
            key_raw, key_norm = col, norm_key(col)
            if key_raw in row_view or key_norm in row_view:
                val = row_view.get(key_raw, row_view.get(key_norm, ''))
                patt = re.compile(r'\{\{\s*'+re.escape(tbl)+r'\s*:\s*'+re.escape(col)+r'\s*\}\}')
                out = patt.sub(val, out)
    # bare
    for col in RE_TOK_BARE.findall(out):
        key_raw, key_norm = col, norm_key(col)
        if key_raw in row_view or key_norm in row_view:
            val = row_view.get(key_raw, row_view.get(key_norm, ''))
            patt = re.compile(r'\{\{\s*'+re.escape(col)+r'\s*\}\}')
            out = patt.sub(val, out)
    return out

def render_template(query, db_name: str, host: str, template_text: str) -> str:
    # 1) Expand loops
    segs = RE_LOOP_FULL.findall(template_text) or []
    expanded_map: List[Tuple[str, str]] = []
    for seg in segs:
        m = RE_LOOP_INNER.findall(seg)
        chosen_table = (m and m[0][0]) or ''
        inner = (m and m[0][1]) or ''
        if not inner:
            expanded_map.append((seg, '')); continue
        table = chosen_table or 'hosts'
        cols = describe_columns(query, table)
        name_col = pick_name_column(cols)
        if name_col:
            rows = query(f"SELECT * FROM `{table}` WHERE `{name_col}`=%s ORDER BY 1", (host,))
        else:
            rows = query(f"SELECT * FROM `{table}`")
        block_lines: List[str] = []
        for r in rows:
            rv = build_row_view(r)
            txt = replace_with_row(inner, rv, chosen_table or None, db_name)
            block_lines.append(txt)
        expanded_map.append((seg, "\n".join(block_lines).rstrip()))
    out = template_text
    for seg, rep in expanded_map:
        out = out.replace(seg, rep)

    # 2) Resolve remaining 3-part tokens globally
    for db, tbl, col in set(RE_TOK_3.findall(out)):
        if tbl.lower() == 'expertpw':
            continue
        if db.lower() != db_name.lower():
            continue
        cols = describe_columns(query, tbl)
        name_col = pick_name_column(cols)
        col_actual = has_col(cols, col) or col
        if name_col:
            rows = query(f"SELECT `{col_actual}` AS v FROM `{tbl}` WHERE `{name_col}`=%s LIMIT 1", (host,))
        else:
            rows = query(f"SELECT `{col_actual}` AS v FROM `{tbl}` LIMIT 1")
        v = '' if not rows else ('' if rows[0].get('v') is None else str(rows[0]['v']))
        patt = re.compile(r'\{\{\s*'+re.escape(db)+r'\s*:\s*'+re.escape(tbl)+r'\s*:\s*'+re.escape(col)+r'\s*\}\}')
        out = patt.sub(v, out)

    # 3) Resolve remaining 2-part tokens globally
    for tbl, col in set(RE_TOK_2.findall(out)):
        if tbl.lower() == 'expertpw':
            continue
        cols = describe_columns(query, tbl)
        name_col = pick_name_column(cols)
        col_actual = has_col(cols, col) or col
        if name_col:
            rows = query(f"SELECT `{col_actual}` AS v FROM `{tbl}` WHERE `{name_col}`=%s LIMIT 1", (host,))
        else:
            rows = query(f"SELECT `{col_actual}` AS v FROM `{tbl}` LIMIT 1")
        v = '' if not rows else ('' if rows[0].get('v') is None else str(rows[0]['v']))
        patt = re.compile(r'\{\{\s*'+re.escape(tbl)+r'\s*:\s*'+re.escape(col)+r'\s*\}\}')
        out = patt.sub(v, out)

    return out

def main():
    ap = argparse.ArgumentParser(description="Render template from MySQL for a given host.")
    ap.add_argument('--mysql-host', default=os.getenv('MYSQL_HOST', '127.0.0.1'))
    ap.add_argument('--mysql-port', type=int, default=int(os.getenv('MYSQL_PORT', '3306')))
    ap.add_argument('--mysql-db', default=os.getenv('MYSQL_DB', 'netvars'))
    ap.add_argument('--mysql-user', default=os.getenv('MYSQL_USER', 'ansible'))
    ap.add_argument('--mysql-password', default=os.getenv('MYSQL_PASSWORD', 'ChangeMe'))
    ap.add_argument('--db-name', default=os.getenv('DB_NAME', 'netvars'),
                    help="Logical DB name expected in {{ db:table:column }} tokens.")
    ap.add_argument('--host', required=True, help="Inventory host name (filters rows on Name/name).")
    ap.add_argument('--template-name', default=None,
                    help="Override template. If omitted, use hosts.template for this host.")
    ap.add_argument('--write-to', default='', help="Path to write rendered text")
    ap.add_argument('--stdout', action='store_true', help="Also print rendered text to stdout")
    ap.add_argument('--preview', type=int, default=0, help="Print first N characters as preview")
    ap.add_argument('--fail-on-unresolved', action='store_true',
                    help="Exit 3 if any {{...}} tokens remain unresolved")
    args = ap.parse_args()

    conn, query = _connect_mysql(args.mysql_host, args.mysql_port,
                                 args.mysql_db, args.mysql_user, args.mysql_password)

    # pick template
    tpl_name = args.template_name or get_template_name_from_host_q(query, args.host)
    template_raw = fetch_template_text_q(query, tpl_name)
    template_norm = (template_raw.lstrip('\ufeff').replace('\r\n','\n').replace('\r','\n'))

    # FIRST pass: resolve {{expertpw:...}} early
    template_norm = resolve_expertpw_shortcuts(query, template_norm)

    # Render normally
    rendered = render_template(query, args.db_name, args.host, template_norm)

    # SECOND pass: catch any {{expertpw:...}} that might appear post-render (edge cases)
    rendered = resolve_expertpw_shortcuts(query, rendered)

    # Unresolved token check
    unresolved = sorted(set(re.findall(r'\{\{[^}]+\}\}', rendered)))
    rc = 3 if (args.fail_on_unresolved and unresolved) else 0
    if rc:
        print("ERROR: Unresolved tokens remain:", file=sys.stderr)
        for u in unresolved:
            print("  -", u, file=sys.stderr)

    # Output
    if args.write_to:
        os.makedirs(os.path.dirname(args.write_to) or ".", exist_ok=True)
        with open(args.write_to, "w", encoding="utf-8") as f:
            f.write(rendered)
    if args.preview > 0:
        p = rendered[:args.preview] + ('...' if len(rendered) > args.preview else '')
        print(p)
    if args.stdout:
        print(rendered)

    try:
        conn.close()
    except Exception:
        pass
    sys.exit(rc)

if __name__ == "__main__":
    main()
