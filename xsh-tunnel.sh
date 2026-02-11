#!/usr/bin/env bash
set -euo pipefail

########################################
# COLORS
########################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${BLUE}[*]${NC} $1"; }
success(){ echo -e "${GREEN}[✓]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✗]${NC} $1"; }

####################################
# CONSTANTS
####################################

SERVICE_NAME="iran-to-foreign-xsh-tunnel"
SSH_DIR="/root/.ssh"
KEY_NAME="key-${SERVICE_NAME}"
KEY_PATH="${SSH_DIR}/${KEY_NAME}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SYSCTL_FILE="/etc/sysctl.d/99-ssh-tunnel.conf"

####################################
# UNINSTALL
####################################

uninstall() {
  log  "Uninstalling $SERVICE_NAME ..."

  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true

  rm -f "$SERVICE_FILE"
  rm -f "$KEY_PATH" "$KEY_PATH.pub"
  rm -f "$SYSCTL_FILE"

  systemctl daemon-reexec
  systemctl daemon-reload
  sysctl --system >/dev/null

  success "Uninstall completed"
  exit 0
}

validate_ip() {
  local ip=$1
  [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  # ensure each octet <= 255
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  for o in $o1 $o2 $o3 $o4; do
    ((o >= 0 && o <= 255)) || return 1
  done
}

validate_port() {
  [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

validate_port_list() {
  IFS=',' read -ra PORTS <<< "$1"

  for p in "${PORTS[@]}"; do
    p=$(echo "$p" | xargs)   # trim spaces
    validate_port "$p" || return 1
  done
}

validate_yes_no() {
  [[ $1 =~ ^[YyNn]$ ]]
}

require_non_empty() {
  [[ -n "$1" ]]
}

########################################
# ROOT CHECK
########################################
if [[ $EUID -ne 0 ]]; then
  error "Run as root"
  exit 1
fi


[[ "${1:-}" == "uninstall" ]] && uninstall


####################################
# DEPENDENCIES
####################################

for b in ssh ssh-keygen ssh-copy-id autossh systemctl sysctl; do
  command -v "$b" >/dev/null || {
    echo "[*] Installing missing dependency: $b"
    apt update && apt install -y autossh
    break
  }
done

####################################
# USER INPUT
####################################

echo
echo -e "${GREEN}🚀 Welcome to the Fast SSH Tunnel Installation Script 🚀${NC}"
echo


while true; do
  read -rp "Foreign server IP: " REMOTE_IP
  validate_ip "$REMOTE_IP" && break
  error "Invalid Foreign Server IP. Try again."
done

while true; do
  read -rp "Foreign SSH port: " REMOTE_SSH_PORT
  validate_port "$REMOTE_SSH_PORT" && break
  error "Invalid port (1-65535)"
done 

while true; do
  read -rp "Foreign SSH user: " REMOTE_USER
  require_non_empty "$REMOTE_USER" && break
  error "User cannot be empty"
done

while true; do
  read -rp "Local listen IP (0.0.0.0 recommended): " LOCAL_IP
  validate_ip "$LOCAL_IP" && break
  error "Invalid IP"
done

while true; do
  read -rp "Remote target host (usually localhost): " REMOTE_TARGET_HOST
  require_non_empty "$REMOTE_TARGET_HOST" && break
  error "Cannot be empty"
done

while true; do
  read -rp "Are inbound & outbound ports identical? (y/n): " SAME_PORTS
  [[ $SAME_PORTS =~ ^[YyNn]$ ]] && break
  error "Enter y or n"
done


while true; do
  read -rp "Inbound ports (comma separated): " IN_PORTS
  validate_port_list "$IN_PORTS" && break
  error "Invalid inbound port list"
done


IFS=',' read -ra IN_PORT_ARRAY <<< "$IN_PORTS"

if [[ "$SAME_PORTS" =~ ^[Yy]$ ]]; then
  OUT_PORT_ARRAY=("${IN_PORT_ARRAY[@]}")
else
  while true; do
    read -rp "Outbound ports (comma separated): " OUT_PORTS
    validate_port_list "$OUT_PORTS" || { error "Invalid outbound list"; continue; }
    IFS=',' read -ra OUT_PORT_ARRAY <<< "$OUT_PORTS"
    [[ ${#IN_PORT_ARRAY[@]} -eq ${#OUT_PORT_ARRAY[@]} ]] && break
    error "Inbound/Outbound port count mismatch"
  done
fi

####################################
# SYSCTL
####################################

echo "[*] Applying sysctl (low port bind)..."
mkdir -p /etc/sysctl.d
echo "net.ipv4.ip_unprivileged_port_start=0" > "$SYSCTL_FILE"
sysctl -w net.ipv4.ip_unprivileged_port_start=0
sysctl --system >/dev/null

####################################
# SSH SETUP
####################################

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ ! -f "$KEY_PATH" ]]; then
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "$SERVICE_NAME"
fi

chmod 600 "$KEY_PATH"

ssh-copy-id -i "${KEY_PATH}.pub" -p "$REMOTE_SSH_PORT" \
  "${REMOTE_USER}@${REMOTE_IP}"

####################################
# BUILD PORT FORWARDS
####################################

FORWARD_ARGS=""
for i in "${!IN_PORT_ARRAY[@]}"; do
  FORWARD_ARGS+=" -L ${LOCAL_IP}:${IN_PORT_ARRAY[$i]}:${REMOTE_TARGET_HOST}:${OUT_PORT_ARRAY[$i]}"
done

####################################
# SYSTEMD SERVICE
####################################

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=[XSH Tunnel] SSH Tunnel (Multi‑Port)  
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root

Environment="AUTOSSH_GATETIME=0"

ExecStart=/usr/bin/autossh -M 0 \
  -i ${KEY_PATH} \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -o Port=${REMOTE_SSH_PORT} \
  -N \
  ${FORWARD_ARGS} \
  ${REMOTE_USER}@${REMOTE_IP}

ExecStop=/bin/kill -TERM \$MAINPID

Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=10
KillMode=control-group
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

####################################
# ENABLE & START
####################################

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo
systemctl --no-pager status "$SERVICE_NAME"
echo
success "[✓] Installation complete"
echo "Uninstall with: sudo $0 uninstall"
