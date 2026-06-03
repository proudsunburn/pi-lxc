#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stephen Chin (steveonjava)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://pi.dev/
#
# Self-contained Proxmox LXC installer for Pi + little-coder coding agent.
# Creates an unprivileged Debian 13 container with Node.js 22 + Pi + little-coder extensions.
#
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/pi.sh)"
#
# Or with options:
#   var_cpu=4 var_ram=8192 var_disk=20 bash -c "..."

set -euo pipefail

# ---- Configuration ----
APP="Pi + little-coder"
BRG="${BRG:-vmbr0}"
CTID="${CTID:-$(pvesh get /cluster/nextid)}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE="debian-13-standard_13.0-*.tar.zst"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
LITTLE_CODER_REPO="https://github.com/itayinbarr/little-coder.git"
LITTLE_CODER_DIR="/home/pi/little-coder"

# ---- Colors ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
TAB='    '

msg_info()  { echo -e "${CYAN}\u2192${NC} $1"; }
msg_ok()    { echo -e "${GREEN}\u2713${NC} $1"; }
msg_warn()  { echo -e "${YELLOW}\u26a0${NC} $1"; }
msg_error() { echo -e "${RED}\u2717${NC} $1"; }

# ---- Safety checks ----
pve_check() {
  if ! command -v pvesh &>/dev/null || ! command -v pct &>/dev/null; then
    msg_error "This script must be run on a Proxmox VE host."
    exit 1
  fi
}

root_check() {
  if [[ "$EUID" -ne 0 ]]; then
    msg_error "This script must be run as root."
    exit 1
  fi
}

# ---- Update function (called when user selects "Update" from community-scripts menu) ----
function update_script() {
  if [[ ! -x /home/pi/.local/bin/pi ]]; then
    msg_error "No Pi Installation Found!"
    exit 1
  fi

  msg_warn "WARNING: This script will update Pi from a third-party source (https://pi.dev/)."
  echo
  read -r -p "${TAB}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi

  msg_info "Updating Pi"
  pct exec "$CTID" -- bash -c '
    set -a; source /etc/default/pi; set +a
    npm install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent
  '
  chown -R pi:pi /home/pi
  msg_ok "Updated Pi"
  msg_info "Pulling latest little-coder extensions..."
  pct exec "$CTID" -- bash -c "cd ${LITTLE_CODER_DIR} && git pull || true"
  chown -R pi:pi /home/pi
  msg_ok "Updated little-coder"
  msg_ok "Updated successfully!"
  exit
}

# ---- Main ----
pve_check
root_check

echo -e "${CYAN}${BOLD}"
echo "\u250c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510"
echo "|             \u2694 Pi + little-coder Installer                    |"
echo "\u251c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2524"
echo "|  Coding agent with 20 extensions + 30 skills.               |"
echo "\u2514\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518"
echo -e "${NC}"

# ---- Download template if missing ----
msg_info "Checking LXC template..."
if ! pveam list local | grep -q "$TEMPLATE"; then
  msg_info "Downloading Debian 13 template..."
  pveam download local "$TEMPLATE" || {
    msg_error "Failed to download template."
    exit 1
  }
fi
msg_ok "Template ready"

# ---- Create container ----
msg_info "Creating LXC container ${CTID}..."
pct create "$CTID" \
  /var/lib/vz/template/iso/$(pveam list local | grep -oP '(?<=local:).*$') \
  --storage "$STORAGE" \
  --cores "$var_cpu" \
  --memory "$var_ram" \
  --swap 0 \
  --rootfs "${STORAGE}:${var_disk}" \
  --hostname pi \
  --unprivileged "$var_unprivileged" \
  --net0 "name=eth0,bridge=${BRG},ip=dhcp" \
  --features fuse=1,nesting=1 \
  --description "Pi + little-coder coding agent - https://pi.dev/" || {
    msg_error "Failed to create container."
    exit 1
  }
msg_ok "Container created"

# ---- Start container and wait for network ----
msg_info "Starting container..."
pct start "$CTID" || {
  msg_error "Failed to start container."
  exit 1
}

msg_info "Waiting for network connectivity..."
ip_in_lxc=""
for i in $(seq 1 60); do
  ip_in_lxc=$(pct exec "$CTID" -- ip -4 addr show dev eth0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 || true)
  [ -n "$ip_in_lxc" ] && break
  sleep 2
done

if [ -z "$ip_in_lxc" ]; then
  msg_error "Container network not available after 60s."
  pct status "$CTID"
  exit 1
fi
msg_ok "Container online at ${ip_in_lxc}"

# ---- Install base packages ----
msg_info "Installing base packages..."
pct exec "$CTID" -- bash -c "apt-get update && apt-get install -y sudo curl git" || {
  msg_error "Failed to install base packages."
  exit 1
}
msg_ok "Base packages installed"

# ---- Install Node.js 22 ----
msg_info "Installing Node.js 22..."
pct exec "$CTID" -- bash -c '
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
apt-get install -y nodejs
' || {
  msg_error "Failed to install Node.js."
  exit 1
}
msg_ok "Node.js $(pct exec "$CTID" -- node --version) installed"

# ---- Create pi user ----
msg_info "Creating Pi user..."
pct exec "$CTID" -- bash -c '
useradd -m -s /bin/bash pi
loginctl enable-linger pi 2>/dev/null || true
echo "export XDG_RUNTIME_DIR=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"" >>/home/pi/.profile
'
msg_ok "Pi user created"

# ---- Configure service environment ----
msg_info "Configuring service environment..."
pct exec "$CTID" -- bash -c '
cat <<EOF >/etc/default/pi
HOME=/home/pi
PATH=/home/pi/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NODE_OPTIONS=
EOF
'
msg_ok "Service environment configured"

# ---- Install Pi ----
msg_warn "WARNING: This will install Pi from a third-party source (https://pi.dev/)."
echo
read -r -p "${TAB}Do you want to continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  msg_error "Aborted by user. Container created but Pi was not installed."
  msg_info "You can install it later by running: pct exec ${CTID} -- pi-setup"
  exit 10
fi

msg_info "Installing Pi..."
pct exec "$CTID" -- bash -c '
set -a; source /etc/default/pi; set +a
export npm_config_yes=true
npm install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent
chown -R pi:pi /home/pi
chmod 750 /home/pi
chmod 700 /home/pi/.local
'
msg_ok "Pi installed ($(pct exec "$CTID" -- pi --version 2>/dev/null || echo "unknown"))"

# ---- Clone little-coder (Approach A: use pi directly inside the repo) ----
msg_info "Cloning little-coder repository..."
pct exec "$CTID" -- bash -c "
git clone ${LITTLE_CODER_REPO} ${LITTLE_CODER_DIR}
chown -R pi:pi ${LITTLE_CODER_DIR}
chmod 750 ${LITTLE_CODER_DIR}
"
msg_ok "little-coder cloned to ${LITTLE_CODER_DIR}"

# ---- Create setup helper (runs pi from inside little-coder dir) ----
msg_info "Creating setup helper..."
pct exec "$CTID" -- bash -c '
cat <<SETUP >/usr/bin/pi-setup
#!/usr/bin/env bash
set -a; source /etc/default/pi; set +a
cd /home/pi/little-coder
/home/pi/.local/bin/pi init
chown -R pi:pi /home/pi
chmod 750 /home/pi
chmod 700 /home/pi/.local
echo "Pi setup complete. File permissions restored."
SETUP
chmod +x /usr/bin/pi-setup
'
msg_ok "Setup helper created at /usr/bin/pi-setup"

# ---- Configure login hints ----
msg_info "Configuring login hints..."
pct exec "$CTID" -- bash -c '
cat <<HINT >/etc/profile.d/pi-hint.sh
if [[ "$(id -u)" -eq 0 ]]; then
  echo "  Run \x27pi-setup\x27 to configure your API key and start using Pi."
  echo "  Use \x27su - pi\x27 (with the dash) to switch to the pi user."
fi
HINT
'
msg_ok "Login hints configured"

# ---- Done ----
echo
echo -e "${GREEN}${BOLD}"
echo "\u250c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510"
echo "|              \u2713 Installation Complete!                       |"
echo "\u2514\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518"
echo -e "${NC}"
echo
echo -e "${CYAN}${BOLD}Files:${NC}"
echo -e "   ${YELLOW}Pi:${NC}        /home/pi/.local/lib/node_modules/@earendil-works/pi-coding-agent/"
echo -e "   ${YELLOW}Extensions:${NC} ${LITTLE_CODER_DIR}/.pi/extensions/"
echo -e "   ${YELLOW}Skills:${NC}    ${LITTLE_CODER_DIR}/skills/"
echo -e "   ${YELLOW}Config:${NC}    ${LITTLE_CODER_DIR}/.pi/settings.json"
echo
echo -e "${CYAN}${BOLD}Commands:${NC}"
echo -e "   ${GREEN}pct exec ${CTID} -- pi-setup${NC}    Configure API key"
echo -e "   ${GREEN}pct exec ${CTID} -- su - pi -c 'cd little-coder && pi'${NC}  Start Pi with extensions"
echo
echo -e "${YELLOW}Container: CTID ${CTID}, IP ${ip_in_lxc}${NC}"
