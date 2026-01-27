#!/usr/bin/env bash
set -euo pipefail

# ======================
# Config
# ======================
NEW_USER="tero"
TZ="Europe/Bucharest"
SSH_PORT="1337"

# ======================
# Helpers
# ======================
log() { echo -e "\n[+] $*\n"; }
err() { echo -e "\n[!] $*\n" >&2; }

gen_pass() {
  # 24 chars strong password
  openssl rand -base64 32 | tr -d '\n' | cut -c1-24
}

if [[ "${EUID}" -ne 0 ]]; then
  err "Rulează scriptul ca root: sudo bash $0"
  exit 1
fi

# ======================
# Timezone
# ======================
log "Set timezone: ${TZ}"
timedatectl set-timezone "${TZ}"

# ======================
# Update
# ======================
log "Update & upgrade"
apt update
apt upgrade -y

# ======================
# User create
# ======================
if id "${NEW_USER}" &>/dev/null; then
  log "User ${NEW_USER} există deja → NU îi schimb parola."
  USER_CREATED="no"
else
  log "Create user: ${NEW_USER}"
  PASSWORD="$(gen_pass)"
  adduser --disabled-password --gecos "" "${NEW_USER}"
  echo "${NEW_USER}:${PASSWORD}" | chpasswd
  chage -d 0 "${NEW_USER}" || true
  USER_CREATED="yes"
fi

# ======================
# Sudo rights
# ======================
log "Add ${NEW_USER} to sudo + NOPASSWD"
usermod -aG sudo "${NEW_USER}"
SUDOERS_FILE="/etc/sudoers.d/${NEW_USER}"
echo "${NEW_USER} ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_FILE}"
chmod 440 "${SUDOERS_FILE}"

# ======================
# Remove default ubuntu user (if exists)
# ======================
if id ubuntu &>/dev/null; then
  log "Removing default user 'ubuntu'..."

  # Kill ubuntu processes (otherwise userdel may fail)
  pkill -KILL -u ubuntu 2>/dev/null || true
  sleep 1
  # Remove sudoers file if present
  rm -f /etc/sudoers.d/ubuntu || true
  # Remove user and home
  deluser --remove-home ubuntu || true
  # Remove ubuntu group if left behind
  getent group ubuntu &>/dev/null && delgroup ubuntu || true
  log "User 'ubuntu' removed."
else
  log "User 'ubuntu' not present, skipping."
fi

# ======================
# SSH port (safe drop-in)
# ======================
log "Set SSH port to ${SSH_PORT}"
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-custom-port.conf <<EOF
# Managed by bootstrap script
Port ${SSH_PORT}
EOF

log "Validate SSH config"
sshd -t

log "Restart SSH"
systemctl restart ssh

# ======================
# Info
# ======================
echo "=============================================="
echo " SETUP SUMMARY"
echo "----------------------------------------------"
echo " User: ${NEW_USER}"
echo " SSH Port: ${SSH_PORT}"
if [[ "${USER_CREATED}" == "yes" ]]; then
  echo " Password: ${PASSWORD}"
  echo " (SAVE IT NOW)"
else
  echo " Password: unchanged"
fi
echo "=============================================="
echo ""
echo "TESTEAZĂ ÎNAINTE SĂ ÎNCHIZI SESIUNEA:"
echo "ssh -p ${SSH_PORT} ${NEW_USER}@<IP>"
echo ""

# ======================
# Reboot confirm
# ======================
read -r -p "Vrei reboot acum? (y/N): " REBOOT
case "$REBOOT" in
  y|Y|yes|YES)
    log "Rebooting..."
    reboot
    ;;
  *)
    log "Reboot sărit."
    ;;
esac
