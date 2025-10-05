# Save as: setup-sftp-password.sh
# Run:
#   sudo USERNAME="sftpuser" PASSWORD="ChangeMe123!" SSH_PORT=22 bash setup-sftp-password.sh
# Optional: START_IN_UPLOAD=true (default true) to land users in /upload on login.

#!/usr/bin/env bash
set -euo pipefail

### ======= Config via env vars =======
USERNAME="${USERNAME:-sftpuser}"               # required user name (created if missing)
PASSWORD="${PASSWORD:?Set PASSWORD env var}"   # required password
SSH_PORT="${SSH_PORT:-22}"                     # SSH/SFTP port
START_IN_UPLOAD="${START_IN_UPLOAD:-true}"     # start session in /upload
### ===================================

require_root() {
  [[ "$(id -u)" -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }
}

install_openssh() {
  apt-get update -y
  apt-get install -y openssh-server
  systemctl enable ssh
  systemctl start ssh
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    local status
    status=$(ufw status | awk 'NR==1{print $2}')
    if [[ "$status" == "active" ]]; then
      if [[ "$SSH_PORT" == "22" ]]; then
        ufw allow OpenSSH || true
      else
        ufw allow "${SSH_PORT}/tcp" || true
      fi
    fi
  fi
}

create_user() {
  getent group sftpusers >/dev/null || groupadd --system sftpusers

  if ! id "${USERNAME}" >/dev/null 2>&1; then
    # nologin shell prevents regular SSH shell access
    useradd -M -g sftpusers -s /usr/sbin/nologin -d "/home/${USERNAME}" "${USERNAME}"
  else
    # Ensure user is in the right group and has nologin shell
    usermod -g sftpusers -s /usr/sbin/nologin -d "/home/${USERNAME}" "${USERNAME}" || true
  fi

  echo "${USERNAME}:${PASSWORD}" | chpasswd
}

prepare_chroot() {
  # Chroot at /sftp/<user>. Root of chroot must be owned by root and not writable.
  mkdir -p "/sftp/${USERNAME}/"{upload,home}
  chown root:root "/sftp/${USERNAME}"
  chmod 755 "/sftp/${USERNAME}"

  # Writable directories for user
  chown "${USERNAME}:sftpusers" "/sftp/${USERNAME}/upload"
  chmod 755 "/sftp/${USERNAME}/upload"

  chown "${USERNAME}:sftpusers" "/sftp/${USERNAME}/home"
  chmod 750 "/sftp/${USERNAME}/home"
}

write_sshd_config() {
  mkdir -p /etc/ssh/sshd_config.d

  # Build ForceCommand line
  local force_cmd="ForceCommand internal-sftp"
  if [[ "${START_IN_UPLOAD}" == "true" ]]; then
    force_cmd='ForceCommand internal-sftp -d /upload'
  fi

  # Write our drop-in (no Subsystem line to avoid duplicates)
  cat > /etc/ssh/sshd_config.d/90-sftp-password.conf <<EOF
# Password-only SFTP for members of 'sftpusers' (chrooted to /sftp/%u)

Match Group sftpusers
    ChrootDirectory /sftp/%u
    ${force_cmd}
    PasswordAuthentication yes
    PubkeyAuthentication no
    X11Forwarding no
    AllowTcpForwarding no
EOF

  # Optional: custom port without touching main config
  if [[ "${SSH_PORT}" != "22" ]]; then
    echo "Port ${SSH_PORT}" > /etc/ssh/sshd_config.d/10-port.conf
  fi

  # Safety: if any prior drop-ins accidentally defined 'Subsystem sftp ...', remove them here.
  # (Ubuntu's main /etc/ssh/sshd_config already has it.)
  sed -i '/^[[:space:]]*Subsystem[[:space:]]\+sftp[[:space:]]/d' /etc/ssh/sshd_config.d/*.conf || true

  # Validate + reload
  sshd -t || { echo "ERROR: sshd config test failed."; exit 1; }
  systemctl reload ssh
}

print_summary() {
  cat <<EOF

✅ SFTP (password-only) is ready.

User: ${USERNAME}
Jail (server path): /sftp/${USERNAME}
Writable upload dir: /sftp/${USERNAME}/upload
Starts in /upload on login: ${START_IN_UPLOAD}
SSH/SFTP port: ${SSH_PORT}

Client view of the chroot:
  /            -> server: /sftp/${USERNAME}
  /upload      -> server: /sftp/${USERNAME}/upload
  /home        -> server: /sftp/${USERNAME}/home

Examples:
  # On your client:
  sftp -P ${SSH_PORT} ${USERNAME}@<server-ip>
  sftp> put localfile /upload/
  sftp> get /upload/manual.pdf

Admin tips (server side):
  Place a file for the user to download:
    sudo cp /path/to/manual.pdf /sftp/${USERNAME}/upload/
    sudo chown ${USERNAME}:sftpusers /sftp/${USERNAME}/upload/manual.pdf
    sudo chmod 644 /sftp/${USERNAME}/upload/manual.pdf

To add another SFTP user later:
  sudo USERNAME='newuser' PASSWORD='NewSecret123!' SSH_PORT='${SSH_PORT}' bash setup-sftp-password.sh

To undo (remove the SFTP-only policy):
  sudo rm -f /etc/ssh/sshd_config.d/90-sftp-password.conf
  sudo systemctl reload ssh

EOF
}

main() {
  require_root
  install_openssh
  open_firewall
  create_user
  prepare_chroot
  write_sshd_config
  print_summary
}

main "$@"
