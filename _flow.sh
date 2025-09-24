#!/usr/bin/env bash
set -euo pipefail

# ============================
# CONFIG
# ============================
PLAYBOOK_DIR="$HOME/Ubution"        # keep this consistent everywhere
LOG_DIR="$PLAYBOOK_DIR/logs"
MAIL_TO="admin@example.com"
MAIL_FROM="ansible@example.com"

# Require destHost argument
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <destHost> [gaia_mode]"
  exit 1
fi

destHost="$1"

# Optional platform extra var (fixes your 'defined $2' issue)
Platform=""
if [[ -n "${2:-}" ]]; then
  Platform="gaia_mode=$2"
fi

mkdir -p "$LOG_DIR"

# ============================
# MAIL FUNCTION
# ============================
send_mail() {
  local subject="$1"
  local body="$2"
  # don't let a mail failure kill the whole flow
  echo "$body" | mail -s "$subject" -r "$MAIL_FROM" "$MAIL_TO" || true
}

# ============================
# PLAYBOOK RUN FUNCTION
# ============================
run_playbook() {
  local step="$1"
  local playbook="$2"
  local ignore_fail="$3"   # "true" / "false"

  local logfile="$LOG_DIR/${step}_$(basename "$playbook").log"

  echo ">>> Running $step: $playbook on $destHost (ignore_fail=$ignore_fail)"

  if ansible-playbook "$PLAYBOOK_DIR/$playbook" -i "$PLAYBOOK_DIR/Inventory.yml" \
                      -e "inventory_hostname=$destHost $Platform" >"$logfile" 2>&1; then
    echo "SUCCESS: $playbook" | tee -a "$LOG_DIR/summary.log"
    send_mail "SUCCESS: $playbook" "Playbook $playbook ($step) completed. Log: $logfile"
  else
    echo "FAILED:  $playbook" | tee -a "$LOG_DIR/summary.log"
    send_mail "FAILED: $playbook" "Playbook $playbook ($step) failed. See log: $logfile"
    if [[ "$ignore_fail" == "false" ]]; then
      echo "Stopping at $step due to failure."
      exit 1
    fi
  fi
}

# ============================
# PREP: ensure repo present/updated
# ============================
cd "$HOME"
if [[ -d "$PLAYBOOK_DIR/.git" ]]; then
  git -C "$PLAYBOOK_DIR" pull --ff-only
else
  git clone "https://gitlab.fritz.lan/root/ubution.git" "$PLAYBOOK_DIR"
fi
cd "$PLAYBOOK_DIR"

# ============================
# FLOW
# ============================
# NOTE: fixed probable typo 'reboot_fire_and_exit.yml.yml' -> '.yml'
run_playbook "step-1" "pb_render.yml"                false
run_playbook "step-2" "pb_apply.yml"                 false
run_playbook "step-3" "reboot_fire_and_exit.yml"     true
run_playbook "step-4" "wait_until_reachable.yml"     false
# run_playbook "step-5" "pb_create_cluster.yml"      false

echo ">>> Flow completed for host $destHost. Logs: $LOG_DIR"
