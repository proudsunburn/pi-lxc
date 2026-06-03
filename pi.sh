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
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
LITTLE_CODER_REPO="https://github.com/itayinbarr/little-coder.git"
LITTLE_CODER_DIR="/home/pi/little-coder"

# ---- Colors ----
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'
BOLD=$'\033[1m'
TAB=$'    '

# Box drawing chars
ULC=$'\u250c'  # upper left corner
URC=$'\u2510'  # upper right corner
LLC=$'\u2514'  # lower left corner
LRC=$'\u2518'  # lower right corner
HL=$'\u2500'    # horizontal line
VL=$'\u2502'    # vertical line
HMC=$'\u252c'   # horizontal middle
VHC=$'\u2534'   # vertical horizontal cross

msg_info()  { printf "%b\u2192%b %s\n" "$CYAN" "$NC" "$1"; }
msg_ok()    { printf "%b\u2713%b %s\n" "$GREEN" "$NC" "$1"; }
msg_warn()  { printf "%b\u26a0%b %s\n" "$YELLOW" "$NC" "$1"; }
msg_error() { printf "%b\u2717%b %s\n" "$RED" "$NC" "$1"; }

print_banner() {
  local line="${ULC}$(printf "${HL}%.0s" {1..62})${URC}"
  local mid="${VHC}${HL}$(printf "${HL}%.0s" {1..62})${HMC}"
  local bot="${LLC}$(printf "${HL}%.0s" {1..62})${LRC}"
  printf "%b%s%b\n" "$CYAN" "$BOLD" "$NC"
  printf "%s\n" "$line"
  printf "%s %b%s%s %s\n" "$VL" "$NC" " \u2694 Pi + little-coder Installer" "$NC" "$VL"
  printf "%s\n" "$mid"
  printf "%s %bCoding agent with 20 extensions + 30 skills.%b %s\n" "$VL" "$NC" "$NC" "$VL"
  printf "%s\n" "$bot"
}

print_success() {
  local line="${ULC}$(printf "${HL}%.0s" {1..62})${URC}"
  local bot="${LLC}$(printf "${HL}%.0s" {1..62})${LRC}"
  printf "%b%s%b\n" "$GREEN" "$BOLD" "$NC"
  printf "%s\n" "$line"
  printf "%s %b\u2713 Installation Complete!%b %s\n" "$VL" "$NC" "$NC" "$VL"
  printf "%s\n" "$bot"
}

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
print_banner

# ---- Download template if missing ----
msg_info "Checking LXC template..."
TEMPLATE_NAME="debian-13-standard_13.0-1_amd64.tar.zst"
if ! pveam list local 2>/dev/null | grep -q "$TEMPLATE_NAME"; then
  msg_info "Downloading Debian 13 template..."
  # Try exact name first, fall back to searching available templates
  if ! pveam download local "$TEMPLATE_NAME" 2>/dev/null; then
    # Search for the actual template name
    ACTUAL_TEMPLATE=$(pveam available | grep -i "debian-13-standard" | head -1 | awk '{print $NF}' || true)
    if [ -n "$ACTUAL_TEMPLATE" ]; then
      msg_info "Found template: $ACTUAL_TEMPLATE"
      pveam download local "$ACTUAL_TEMPLATE" || {
        msg_error "Failed to download template."
        exit 1
      }
      TEMPLATE_NAME="$ACTUAL_TEMPLATE"
    else
      msg_error "Could not find Debian 13 template. Available templates:"
      pveam available | grep -i debian | head -10
      exit 1
    fi
  fi
fi
msg_ok "Template ready ($TEMPLATE_NAME)"

# ---- Create container ----
msg_info "Creating LXC container ${CTID}..."
# Find the actual template file path
TEMPLATE_FILE=$(pveam list local | grep "$TEMPLATE_NAME" | sed 's/^local://' || true)
if [ -z "$TEMPLATE_FILE" ]; then
  TEMPLATE_FILE="${TEMPLATE_NAME}"
fi
pct create "$CTID" \
  "/var/lib/vz/template/iso/${TEMPLATE_FILE}" \
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
  echo "  Run pi-setup to configure your API key and start using Pi."
  echo "  Use su - pi (with the dash) to switch to the pi user."
fi
HINT
'
msg_ok "Login hints configured"

# ---- Done ----
echo
print_success
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
