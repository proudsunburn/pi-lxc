#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stephen Chin (steveonjava)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://pi.dev/
#
# Self-contained installer — uses build.func's build_container() for everything,
# then does its own install since pi-install.sh isn't in the community repo.

APP="piagent"
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
    npm install -g --prefix /home/pi/.local --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent
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

# build_container does storage detection, template download, container creation,
# start + network wait, base packages. It will fail on the install script step
# (pi-install.sh not in community repo) but container will be created and running.
build_container || true

# If container wasn't created by build_container, bail out
if ! pct status "$CTID" &>/dev/null; then
  msg_error "Container was not created. Aborting."
  exit 1
fi

# ---- Install Pi + little-coder inside the container ----

msg_info "Installing Node.js..."
pct exec "$CTID" -- bash -c '
curl -fsSL https://deb.nodesource.com/setup_26.x | sudo -E bash -
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
# No passwords set — access via Proxmox pct exec or console
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
  npm install -g --prefix /home/pi/.local --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent
' >>"$BUILD_LOG" 2>&1 || {
  msg_error "Failed to install Pi."
  exit 1
}
pct exec "$CTID" -- chown -R pi:pi /home/pi
pct exec "$CTID" -- chmod 750 /home/pi
pct exec "$CTID" -- chmod 700 /home/pi/.local || true
msg_ok "Installed Pi"
pct exec "$CTID" -- apt-get install -y git >>"$BUILD_LOG" 2>&1 || {
  msg_error "Failed to install git."
  exit 1
}

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
chmod 700 /home/pi/.local || true
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
