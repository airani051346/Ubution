#!/usr/bin/env python3
import argparse, json, re, shlex, sys, time, pexpect, os
from datetime import datetime

def parse_template(text):
    lines = [ln.strip() for ln in text.splitlines() if ln.strip() and not ln.strip().startswith('#')]
    blocks, current = [], {'type':'clish','items':[]}

    def flush():
        nonlocal current
        if current['items']:
            blocks.append(current)
        current = {'type':'clish','items':[]}

    for l in lines:
        if l.startswith('::Sleep '):
            flush()
            m = re.match(r'^::Sleep\s+(\d+)$', l)
            secs = int(m.group(1)) if m else 1
            blocks.append({'type':'sleep','seconds':secs})
        elif re.match(r'^::ExpertMode\b', l):
            flush()
            cmd_enter  = re.search(r"command=([^\s]+)", l)
            prompt_pre = re.search(r"prompt='([^']+)'", l)
            prompt_ex  = re.search(r"expert-prompt='([^']+)'", l)
            pw_q = re.search(r"prompt='[^']*'\s+'([^']+)'(?!')\s+expert-prompt", l)
            pw_b = re.search(r"prompt='[^']*'\s+([^\s]+)\s+expert-prompt", l)
            current = {
                'type':'expert',
                'cmd_enter': (cmd_enter.group(1) if cmd_enter else 'expert'),
                'prompt_pre': (prompt_pre.group(1) if prompt_pre else 'password:'),
                'prompt_expert': (prompt_ex.group(1) if prompt_ex else '#'),
                'password': (pw_q.group(1) if pw_q else (pw_b.group(1) if pw_b else '')),
                'items': []
            }
        elif re.match(r'^::ExpertModeEnd\b', l):
            cmd_exit   = re.search(r"command=([^\s]+)", l)
            prompt_out = re.search(r"prompt='([^']+)'", l)
            if current.get('type') == 'expert':
                current['cmd_exit']   = (cmd_exit.group(1) if cmd_exit else 'exit')
                current['prompt_exit']= (prompt_out.group(1) if prompt_out else '>')
                blocks.append(current)
            current = {'type':'clish','items':[]}
        elif l.startswith('::'):
            continue
        else:
            current['items'].append(l)
    if current['items']:
        blocks.append(current)
    return blocks

DEFAULT_TOLERATED = [
    'already configured',
    'object already exists',
    'a contradicting route already exists',
    'internetconnection.ipaddr property or method does not exist',
    'failed to find the requested interface',
]

class TeeLogger:
    def __init__(self, path=None):
        self.path = path
        self.fh = open(path, 'a', encoding='utf-8') if path else None
    def write(self, s='', end='\n'):
        msg = f'{s}{end}' if end else s
        sys.stdout.write(msg)
        sys.stdout.flush()
        if self.fh:
            self.fh.write(msg)
            self.fh.flush()
    def close(self):
        if self.fh:
            self.fh.close()
            self.fh = None

def connect_ssh(host, user, password=None, keyfile=None, port=22, login_timeout=30):
    ssh_cmd = [
        'ssh','-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=/dev/null',
        '-p', str(port)
    ]
    if keyfile: ssh_cmd += ['-i', keyfile]
    ssh_cmd += [f'{user}@{host}']
    child = pexpect.spawn(' '.join(shlex.quote(x) for x in ssh_cmd), encoding='utf-8', timeout=login_timeout)
    while True:
        i = child.expect([
            r'Are you sure you want to continue connecting \(yes/no\)\?',
            r'[Pp]assword:',
            r'>\s*$',
            r'#\s*$',
            pexpect.EOF, pexpect.TIMEOUT
        ])
        if i == 0: child.sendline('yes')
        elif i == 1:
            if not password: raise RuntimeError('Password required but not provided.')
            child.sendline(password)
        elif i in (2,3): break
        elif i == 4: raise RuntimeError('SSH closed unexpectedly during login')
        elif i == 5: raise RuntimeError('SSH login timed out')
    return child

def expect_prompt(child, pattern=r'>\s*$|#\s*$', timeout=90):
    return child.expect([pattern, pexpect.EOF, pexpect.TIMEOUT], timeout=timeout)

def run_clish(child, line, gaia_mode='spark', timeout=120):
    cmd = line if gaia_mode != 'full' else f'clish -s -c {shlex.quote(line)}'
    child.sendline(cmd)
    i = expect_prompt(child, timeout=timeout)
    out = child.before or ''
    return (i == 0), out

def run_expert_block(child, block, log, fallback_password=None, timeout=180):
    enter_cmd   = block.get('cmd_enter','expert')
    prompt_pre  = block.get('prompt_pre','password:')
    ex_prompt   = block.get('prompt_expert','#')
    password    = block.get('password') or fallback_password or ''
    exit_cmd    = block.get('cmd_exit','exit')
    prompt_exit = block.get('prompt_exit','>')

    log.write(f'-- ENTER EXPERT ({enter_cmd})')
    child.sendline(enter_cmd)
    i = child.expect([re.escape(prompt_pre), re.escape(ex_prompt), pexpect.EOF, pexpect.TIMEOUT], timeout=timeout)
    if i == 0:
        if not password: raise RuntimeError('Expert password required but missing')
        child.sendline(password)
        if child.expect([re.escape(ex_prompt), pexpect.EOF, pexpect.TIMEOUT], timeout=timeout) != 0:
            raise RuntimeError('Did not reach expert prompt after password')
    elif i == 1:
        pass
    else:
        raise RuntimeError('Failed entering expert mode')

    for cmd in block.get('items', []):
        log.write(f'EXPERT# {cmd}')
        child.sendline(cmd)
        if child.expect([re.escape(ex_prompt), pexpect.EOF, pexpect.TIMEOUT], timeout=timeout) != 0:
            raise RuntimeError(f'Expert command timed out/failed: {cmd}')
        out = (child.before or '').strip()
        if out: log.write(out)

    child.sendline(exit_cmd)
    j = child.expect([re.escape(prompt_exit), r'>\s*$', pexpect.EOF, pexpect.TIMEOUT], timeout=timeout)
    if j not in (0,1): raise RuntimeError('Did not reach clish prompt after exit')
    log.write('-- EXIT EXPERT')

def apply_blocks(host, user, template_path, log_path=None, password=None, keyfile=None,
                 gaia_mode='spark', expert_password=None, tolerated=None, dry_run=False, port=22):
    tolerated = [t.lower() for t in (tolerated or DEFAULT_TOLERATED)]
    with open(template_path, 'r', encoding='utf-8') as f:
        text = f.read()
    blocks = parse_template(text)

    log = TeeLogger(log_path)
    try:
        log.write(f'Parsed {len(blocks)} blocks')
        log.write(f'Host: {host}, User: {user}, Gaia: {gaia_mode}')
        log.write(f'Template: {template_path}')
        log.write(f'Start: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')

        if dry_run:
            log.write(json.dumps(blocks, indent=2))
            return 0

        child = connect_ssh(host, user, password=password, keyfile=keyfile, port=port)
        try:
            for b in blocks:
                if b['type'] == 'sleep':
                    secs = int(b.get('seconds',1))
                    log.write(f'-- SLEEP {secs}s'); time.sleep(secs); continue
                if b['type'] == 'clish':
                    for line in b['items']:
                        log.write(f'CLISH> {line}')
                        ok, out = run_clish(child, line, gaia_mode=gaia_mode)
                        out = (out or '').strip()
                        if out: log.write(out)
                        if not ok:
                            low = out.lower()
                            if not any(t in low for t in tolerated):
                                raise RuntimeError(f'clish failed or timed out: {line}')
                            log.write('  (tolerated)')
                    continue
                if b['type'] == 'expert':
                    run_expert_block(child, b, log, fallback_password=expert_password or password)
                    continue
            log.write('All blocks applied.')
            log.write(f'End: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')
            return 0
        finally:
            try: child.sendline('exit'); child.close()
            except Exception: pass
    finally:
        log.close()

def build_log_path(log_dir, log_path, template_path):
    if log_path:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        return log_path
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
        ts = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
        base = os.path.basename(template_path)  # e.g. vpn-gw-1.cfg
        # Force extension to .cfg as requested:
        name_noext = os.path.splitext(base)[0]
        return os.path.join(log_dir, f'{ts}_{name_noext}.cfg')
    return None

def main():
    ap = argparse.ArgumentParser(description='Apply Check Point template over SSH with ExpertMode support.')
    ap.add_argument('--host', required=True)
    ap.add_argument('--user', default='admin')
    ap.add_argument('--password')
    ap.add_argument('--keyfile')
    ap.add_argument('--port', type=int, default=22)
    ap.add_argument('--template', required=True)
    ap.add_argument('--gaia-mode', choices=['spark','full'], default='spark')
    ap.add_argument('--expert-password')
    ap.add_argument('--dry-run', action='store_true')
    # Logging
    ap.add_argument('--log-dir', help='Directory to write a timestamped <ts>_<template-basename>.cfg log')
    ap.add_argument('--log-path', help='Exact path to write the log (overrides --log-dir)')
    args = ap.parse_args()

    if not args.password and not args.keyfile:
        print('Either --password or --keyfile is required for SSH auth.', file=sys.stderr); return 2

    log_path = build_log_path(args.log_dir, args.log_path, args.template)

    try:
        return apply_blocks(
            host=args.host, user=args.user, template_path=args.template,
            log_path=log_path,
            password=args.password, keyfile=args.keyfile, gaia_mode=args.gaia_mode,
            expert_password=args.expert_password, dry_run=args.dry_run, port=args.port
        )
    except Exception as e:
        print(f'ERROR: {e}', file=sys.stderr); return 1

if __name__ == '__main__':
    sys.exit(main())

