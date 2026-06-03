#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stephen Chin (steveonjava)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://pi.dev/
#
# Self-contained installer — uses build.func for utilities, runs install locally.
# Does NOT require community repo. Just run:
#   bash -c "$(curl -fsSL <url-to-this-script>)"

APP="Pi"
var_tags="${var_tags:-ai;automation;agent}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /home/pi/.local/bin/pi ]]; then
    msg_error "No Pi Installation Found!"
    exit
  fi

  msg_warn "WARNING: This script will run an external installer from a third-party source (https://pi.dev/)."
  msg_warn "The following code is NOT maintained or audited by our repository."
  msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
  msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://pi.dev/install.sh"
  echo
  read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    msg_error "Aborted by user. No changes have been made."
    exit 10
  fi

  msg_info "Updating Pi"
  $STD setsid --wait bash -c '
    set -a; source /etc/default/pi; set +a
    npm install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent
  '
  chown -R pi:pi /home/pi
  msg_ok "Updated Pi"

  msg_info "Pulling latest little-coder extensions..."
  cd /home/pi/little-coder && git pull || true
  chown -R pi:pi /home/pi
  msg_ok "Updated little-coder"

  msg_ok "Updated successfully!"
  exit
}

start

# ---- Build container using build.func utilities ----
# Uses variables() for storage/network detection, then creates container directly.
# Skips the community repo install script step.

# Check/download template
check_template "$var_os" "$var_version"

# Create container
msg_info "Creating LXC container ${CTID}..."
pct create "$CTID" \
  "/var/lib/vz/template/iso/${TEMPLATE_FILE}" \
  --storage "$STORAGE" \
  --cores "$var_cpu" \
  --memory "$var_ram" \
  --swap 0 \
  --rootfs "${STORAGE}:${var_disk}" \
  --hostname pi \
  --unprivileged "$var_unprivileged" \
  --net0 "name=eth0,bridge=${BRG:-vmbr0},ip=${NET:-dhcp}" \
  --features fuse=1,nesting=1 \
  --description "Pi + little-coder coding agent - https://pi.dev/" >>"$BUILD_LOG" 2>&1 || {
    msg_error "Failed to create container."
    exit 1
  }
msg_ok "Container created"

# Start container and wait for network
msg_info "Starting container..."
pct start "$CTID" >>"$BUILD_LOG" 2>&1 || {
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
  exit 1
fi
msg_ok "Container online at ${ip_in_lxc}"

# Install base packages (same as build_container does)
msg_info "Installing base packages..."
pct exec "$CTID" -- bash -c "apt-get update 2>&1 && apt-get install -y sudo curl mc gnupg2 jq 2>&1" >>"$BUILD_LOG" 2>&1 || {
  msg_error "Failed to install base packages."
  exit 1
}
msg_ok "Base packages installed"

# ---- Install Pi + little-coder inside the container ----

msg_info "Installing Node.js 22..."
pct exec "$CTID" -- bash -c '
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
apt-get install -y nodejs
' >>"$BUILD_LOG" 2>&1 || {
  msg_error "Failed to install Node.js."
  exit 1
}
msg_ok "Node.js installed"

msg_info "Creating Pi User"
pct exec "$CTID" -- useradd -m -s /bin/bash pi >>"$BUILD_LOG" 2>&1
pct exec "$CTID" -- loginctl enable-linger pi >>"$BUILD_LOG" 2>&1 || true
pct exec "$CTID" -- bash -c 'echo '"'"'export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"'"'"' >>/home/pi/.profile'
msg_ok "Created Pi User"

msg_info "Configuring Service Environment"
pct exec "$CTID" -- bash -c "cat <<EOF >/etc/default/pi
HOME=/home/pi
PATH=/home/pi/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NODE_OPTIONS=
EOF"
msg_ok "Configured Service Environment"

msg_warn "WARNING: This script will install Pi from a third-party source (https://pi.dev/)."
msg_warn "The following code is NOT maintained or audited by our repository."
msg_warn "If you have any doubts or concerns, please review the installer code before proceeding:"
msg_custom "${TAB3}${GATEWAY}${BGN}${CL}" "\e[1;34m" "→  https://pi.dev/install.sh"
echo
read -r -p "${TAB3}Do you want to continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  msg_error "Aborted by user. No changes have been made."
  exit 10
fi

msg_info "Installing Pi"
pct exec "$CTID" -- bash -c '
  set -a; source /etc/default/pi; set +a
  export npm_config_yes=true
  npm install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent
' >>"$BUILD_LOG" 2>&1 || {
  msg_error "Failed to install Pi."
  exit 1
}
pct exec "$CTID" -- chown -R pi:pi /home/pi
pct exec "$CTID" -- chmod 750 /home/pi
pct exec "$CTID" -- chmod 700 /home/pi/.local
msg_ok "Installed Pi"

msg_info "Cloning little-coder repository..."
pct exec "$CTID" -- bash -c '
git clone https://github.com/itayinbarr/little-coder.git /home/pi/little-coder
chown -R pi:pi /home/pi/little-coder
chmod 750 /home/pi/little-coder
' >>"$BUILD_LOG" 2>&1 || {
  msg_error "Failed to clone little-coder."
  exit 1
}
msg_ok "little-coder cloned to /home/pi/little-coder"

msg_info "Creating Setup Helper"
pct exec "$CTID" -- bash -c "cat <<'SETUP' >/usr/bin/pi-setup
#!/usr/bin/env bash
set -a; source /etc/default/pi; set +a
cd /home/pi/little-coder
/home/pi/.local/bin/pi init
chown -R pi:pi /home/pi
chmod 750 /home/pi
chmod 700 /home/pi/.local
echo \"Pi setup complete. File permissions restored.\"
SETUP
chmod +x /usr/bin/pi-setup"
msg_ok "Created Setup Helper"

msg_info "Configuring Login Hints"
pct exec "$CTID" -- bash -c "cat <<'HINT' >/etc/profile.d/pi-hint.sh
if [[ \"\$(id -u)\" -eq 0 ]]; then
  echo \"  Run pi-setup to configure your API key and start using Pi.\"
  echo \"  Use su - pi (with the dash) to switch to the pi user.\"
fi
HINT"
msg_ok "Configured Login Hints"

description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}Pi + little-coder has been installed!${CL}"
echo -e "${INFO}${YW} Run setup inside the container to configure your API key:${CL}"
echo -e "${TAB}${BGN}pct exec ${CTID} -- pi-setup${CL}"
