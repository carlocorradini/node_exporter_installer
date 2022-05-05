#!/usr/bin/env sh
# MIT License
#
# Copyright (c) 2022-2022 Carlo Corradini
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Fail on error
set -o errexit
# Disable wildcard character expansion
set -o noglob

# ================
# CONFIGURATION
# ================
# GitHub release URL
GITHUB_URL=https://github.com/prometheus/node_exporter/releases
# GitHub API URL
GITHUB_API_URL=https://api.github.com/repos/prometheus/node_exporter/releases/latest

# ================
# LOGGER
# ================
# Fatal log message
fatal() {
  printf '[FATAL] %s\n' "$@" >&2
  exit 1
}

# Info log message
info() {
  printf '[INFO ] %s\n' "$@"
}

# ================
# FUNCTIONS
# ================
# Add quotes to command arguments
quote() {
  for arg in "$@"; do
    printf '%s\n' "$arg" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"
  done
}

# Add indentation and trailing slash to quoted args
quote_indent() {
  printf ' \\\n'
  for _arg in "$@"; do
    printf '\t%s \\\n' "$(quote "$_arg")"
  done
}

# Escape most punctuation characters, except quotes, forward slash, and space
escape() {
  printf '%s' "$@" | sed -e 's/\([][!#$%&()*;<=>?\_`{|}]\)/\\\1/g;'
}

# Escape double quotes
escape_dq() {
  printf '%s' "$@" | sed -e 's/"/\\"/g'
}

# Define needed environment variables
setup_env() {
  # Command args
  case "$1" in
    (-*|"")
      _cmd_node_exporter=
    ;;
    # Command provided
    (*)
      _cmd_node_exporter=$1
      shift
    ;;
  esac

  CMD_NODE_EXPORTER_EXEC="$_cmd_node_exporter$(quote_indent "$@")"

  # use sudo if not already root
  SUDO=sudo
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  fi

  # Use binary install directory if defined or create default
  if [ -n "$INSTALL_NODE_EXPORTER_BIN_DIR" ]; then
    BIN_DIR=$INSTALL_NODE_EXPORTER_BIN_DIR
  else
    # Use /usr/local/bin if root can write to it, otherwise use /opt/bin if it exists
    BIN_DIR=/usr/local/bin
    if ! $SUDO sh -c "touch $BIN_DIR/node_exporter-ro-test && rm -rf $BIN_DIR/node_exporter-ro-test"; then
      if [ -d /opt/bin ]; then
        BIN_DIR=/opt/bin
      fi
    fi
  fi

  # Use systemd directory if defined or create default
  if [ -n "$INSTALL_NODE_EXPORTER_SYSTEMD_DIR" ]; then
    SYSTEMD_DIR="$INSTALL_NODE_EXPORTER_SYSTEMD_DIR"
  else
    SYSTEMD_DIR=/etc/systemd/system
  fi

  # Set related files from system name
  SERVICE_NODE_EXPORTER=node_exporter.service
  UNINSTALL_NODE_EXPORTER_SH=${UNINSTALL_NODE_EXPORTER_SH:-$BIN_DIR/node_exporter.uninstall.sh}
  KILLALL_NODE_EXPORTER_SH=${KILLALL_NODE_EXPORTER_SH:-$BIN_DIR/node_exporter.killall.sh}

  # Use service or environment location depending on systemd/openrc
  case $INIT_SYSTEM in
    openrc)
      $SUDO mkdir -p /etc/node_exporter
      FILE_NODE_EXPORTER_SERVICE=/etc/init.d/node_exporter
    ;;
    systemd)
      FILE_NODE_EXPORTER_SERVICE=$SYSTEMD_DIR/$SERVICE_NODE_EXPORTER
    ;;
    *) fatal "Unknown init system '$INIT_SYSTEM'" ;;
  esac

  # Get hash of config & exec for currently installed Node exporter
  PRE_INSTALL_HASHES=$(get_installed_hashes)
}

# Verify init system
verify_init_system() {
  # OpenRC
  if [ -x /sbin/openrc-run ]; then
    INIT_SYSTEM=openrc
    return
  fi
  # systemd
  if [ -x /bin/systemctl ] || type systemctl > /dev/null 2>&1; then
    INIT_SYSTEM=systemd
    return
  fi

  # Not supported
  fatal 'No supported init system found (OpenRC or systemd)'
}

# Verify architecture
verify_arch() {
  ARCH=$(uname -m)
  case $ARCH in
    amd64|x86_64) ARCH=amd64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    armv5*) ARCH=armv5 ;;
    armv6*) ARCH=armv6 ;;
    armv7*) ARCH=armv7 ;;
    mips) ARCH=mips ;;
    mipsle) ARCH=mipsle ;;
    mips64) ARCH=mips64 ;;
    mips64le) ARCH=mips64le ;;
    ppc64) ARCH=ppc64 ;;
    ppc64le) ARCH=ppc64le ;;
    s390x) ARCH=s390x ;;
    i386) ARCH=386 ;;
    # Not supported
    *) fatal "Architecture '$ARCH' not supported" ;;
  esac
}
# Verify Operating System
verify_os() {
  OS=$(uname -s)
  case $OS in
    Linux) OS=linux ;;
    Darwin) OS=darwin ;;
    NetBSD) OS=netbsd ;;
    OpenBSD) OS=openbsd ;;
    # Not supported
    *) fatal "OS '$OS' not supported" ;;
  esac
}

# Verify architecture and os are supported
verify_arch_os() {
  case $OS in
    linux)
      case $ARCH in
        amd64|arm64|armv5|armv6|armv7|mips|mipsle|mips64|mips64le|ppc64|ppc64le|s390x|386) return ;;
      esac
    ;;
    darwin)
      case $ARCH in
        amd64|arm64) return ;;
      esac
    ;;
    netbsd)
      case $ARCH in
        386|amd64) return ;;
      esac
    ;;
    openbsd)
      case $ARCH in
        amd64) return ;;
      esac
    ;;
    # Not supported
    *) fatal "OS '$OS' not supported" ;;
  esac

  # Not supported
  fatal "Architecture '$ARCH' on OS '$OS' not supported";
}

# Verify command is installed
verify_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "Command '$1' not found"
}

# Verify downloader command is installed
verify_downloader_cmd() {
  # Cycle downloader commands
  for cmd in ${1:+"$@"}; do
    # Check if exists
    if command -v "$cmd" >/dev/null 2>&1; then
      # Found
      DOWNLOADER=$cmd
      return
    fi
  done

  # Not found
  fatal "Unable to find any downloader command in list '$*'"
}

# Verify system
verify_system() {
  # Init system
  verify_init_system
  # Arch and OS
  verify_arch
  verify_os
  verify_arch_os
  # Commands
  verify_cmd chmod
  verify_cmd chown
  verify_cmd grep
  verify_cmd mktemp
  verify_cmd rm
  verify_cmd sed
  verify_cmd sha256sum
  verify_cmd tar
  verify_cmd tee
  # Downloader
  verify_downloader_cmd curl wget
}

# Create temporary directory and cleanup
setup_tmp() {
  TMP_DIR=$(mktemp -d -t node_exporter.XXXXXXXX)
  TMP_HASH=$TMP_DIR/node_exporter.hash
  TMP_ARCHIVE=$TMP_DIR/node_exporter.archive
  TMP_BIN=$TMP_DIR/node_exporter.bin

  cleanup() {
    _exit_code=$?
    set +o errexit
    trap - EXIT
    rm -rf "$TMP_DIR"
    exit $_exit_code
  }
  trap cleanup INT EXIT
}

# Use provided version or obtain from latest release
get_release_version() {
  if [ -n "$INSTALL_NODE_EXPORTER_VERSION" ]; then
    VERSION_NODE_EXPORTER=$INSTALL_NODE_EXPORTER_VERSION
  else
    info "Finding latest release"
    case $DOWNLOADER in
      curl) VERSION_NODE_EXPORTER=$(curl -L -f -s -S $GITHUB_API_URL) || fatal "Download '$GITHUB_API_URL' failed" ;;
      wget) VERSION_NODE_EXPORTER=$(wget -q -O - $GITHUB_API_URL 2>&1) || fatal "Download '$GITHUB_API_URL' failed" ;;
      *) fatal "Invalid downloader '$DOWNLOADER'" ;;
    esac
    VERSION_NODE_EXPORTER=$(echo "$VERSION_NODE_EXPORTER" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  fi

  info "Using $VERSION_NODE_EXPORTER as release"
}

# Download a file
download() {
  [ $# -eq 2 ] || fatal "Download requires exactly 2 arguments but '$#' found"

  # Download
  case $DOWNLOADER in
    curl)
      curl --fail --silent --location --output "$1" "$2" || fatal "Download '$2' failed"
    ;;
    wget)
      wget --quiet --output-document="$1" "$2" || fatal "Download '$2' failed"
    ;;
    *)
      fatal "Unknown downloader '$DOWNLOADER'"
    ;;
  esac
}

# Download hash
download_hash() {
  _hash_url=$GITHUB_URL/download/$VERSION_NODE_EXPORTER/sha256sums.txt

  info "Downloading hash '$_hash_url'"
  download "$TMP_HASH" "$_hash_url"
  HASH_ARCHIVE_EXPECTED=$(grep " $RELEASE_ARCHIVE" "$TMP_HASH")
  HASH_ARCHIVE_EXPECTED=${HASH_ARCHIVE_EXPECTED%%[[:blank:]]*}
}

# Download archive
download_archive() {
  _archive_url=$GITHUB_URL/download/$VERSION_NODE_EXPORTER/$RELEASE_ARCHIVE

  info "Downloading archive '$_archive_url'"
  download "$TMP_ARCHIVE" "$_archive_url"
  HASH_ARCHIVE=$(sha256sum "$TMP_ARCHIVE")
  HASH_ARCHIVE=${HASH_ARCHIVE%%[[:blank:]]*}
}

# Verify downloaded archive hash
verify_archive() {
  info "Verifying archive download '$TMP_ARCHIVE'"
  if [ "$HASH_ARCHIVE_EXPECTED" != "$HASH_ARCHIVE" ]; then
    fatal "Download sha256 does not match '$HASH_ARCHIVE_EXPECTED', got '$HASH_ARCHIVE'"
  fi
}

# Extract archive
extract_archive() {
  info "Extracting archive '$TMP_ARCHIVE'"
  tar xzf "$TMP_ARCHIVE" -C "$TMP_DIR" --strip-components 1 "$RELEASE_NAME/node_exporter"
  mv "$TMP_DIR/node_exporter" "$TMP_BIN"

  info "Extracted binary '$TMP_BIN'"
  HASH_BIN_EXPECTED=$(sha256sum "$TMP_BIN")
  HASH_BIN_EXPECTED=${HASH_BIN_EXPECTED%%[[:blank:]]*}
}

# Check hash against installed version
installed_hash_matches() {
  if [ -x $BIN_DIR/node_exporter ]; then
    _hash_bin_installed=$(sha256sum $BIN_DIR/node_exporter)
    _hash_bin_installed=${_hash_bin_installed%%[[:blank:]]*}
    if [ "$HASH_BIN_EXPECTED" = "$_hash_bin_installed" ]; then
      return 0
    fi
  fi
  return 1
}

# Setup permissions and move binary to system directory
setup_binary() {
  chmod 755 "$TMP_BIN"
  info "Installing Node exporter to '$BIN_DIR/node_exporter'"
  $SUDO chown root:root "$TMP_BIN"
  $SUDO mv -f "$TMP_BIN" "$BIN_DIR/node_exporter"
}

# Download and verify
download_and_verify() {
  setup_tmp
  get_release_version

  RELEASE_NAME=node_exporter-$(echo "$VERSION_NODE_EXPORTER" | sed 's/^v//').$OS-$ARCH
  RELEASE_ARCHIVE=$RELEASE_NAME.tar.gz

  download_hash
  download_archive
  verify_archive
  extract_archive

  if installed_hash_matches; then
    info 'Skipping binary download, installed Node exporter matches hash'
    return
  fi

  setup_binary
}

# Create killall script
create_killall() {
  info "Creating killall script '$KILLALL_NODE_EXPORTER_SH'"
  $SUDO tee "$KILLALL_NODE_EXPORTER_SH" >/dev/null << \EOF
#!/usr/bin/env sh
[ $(id -u) -eq 0 ] || exec sudo $0 $@

set -x

for service in /etc/systemd/system/node_exporter.service; do
  [ -s $service ] && systemctl stop $(basename $service)
done

for service in /etc/init.d/node_exporter.service; do
  [ -x $service ] && $service stop
done

do_unmount_and_remove() {
  set +x
  while read -r _ path _; do
    case "$path" in $1*) echo "$path" ;; esac
  done < /proc/self/mounts | sort -r | xargs -r -t -n 1 sh -c 'umount "$0" && rm -rf "$0"'
  set -x
}
do_unmount_and_remove '/run/node_exporter'
EOF
  $SUDO chmod 755 "$KILLALL_NODE_EXPORTER_SH"
  $SUDO chown root:root "$KILLALL_NODE_EXPORTER_SH"
}

# Create uninstall script
create_uninstall() {
  info "Creating uninstall script '$UNINSTALL_NODE_EXPORTER_SH'"
  $SUDO tee "$UNINSTALL_NODE_EXPORTER_SH" >/dev/null << EOF
#!/usr/bin/env sh
set -x
[ \$(id -u) -eq 0 ] || exec sudo \$0 \$@

$KILLALL_NODE_EXPORTER_SH

if command -v systemctl; then
  systemctl disable node_exporter
  systemctl reset-failed node_exporter
  systemctl daemon-reload
fi
if command -v rc-update; then
  rc-update delete node_exporter default
fi

rm -f $FILE_NODE_EXPORTER_SERVICE

remove_uninstall() {
  rm -f $UNINSTALL_NODE_EXPORTER_SH
}
trap remove_uninstall EXIT

rm -rf /etc/node_exporter
rm -rf /run/node_exporter
rm -f $BIN_DIR/k3s
rm -f $KILLALL_NODE_EXPORTER_SH
EOF
  $SUDO chmod 755 "$UNINSTALL_NODE_EXPORTER_SH"
  $SUDO chown root:root "$UNINSTALL_NODE_EXPORTER_SH"
}

# Disable current service if loaded
systemd_disable() {
  $SUDO systemctl disable node_exporter >/dev/null 2>&1 || true
  $SUDO rm -f /etc/systemd/system/$SERVICE_NODE_EXPORTER || true
}

# Write openrc service file
create_openrc_service_file() {
  LOG_FILE=/var/log/node_exporter.log

  info "openrc: Creating service file '$FILE_NODE_EXPORTER_SERVICE'"
  $SUDO tee "$FILE_NODE_EXPORTER_SERVICE" >/dev/null << EOF
#!/sbin/openrc-run

description="Node exporter"

depend() {
  need net
  need localmount
  use dns
  after firewall
}

supervisor=supervise-daemon
name=node_exporter
command="$BIN_DIR/node_exporter"
command_args="$(escape_dq "$CMD_NODE_EXPORTER_EXEC")
    >>$LOG_FILE 2>&1"

output_log=$LOG_FILE
error_log=$LOG_FILE

pidfile="/var/run/node_exporter.pid"
respawn_delay=5
respawn_max=0

set -o allexport
if [ -f /etc/environment ]; then source /etc/environment; fi
set +o allexport
EOF
  $SUDO chmod 0755 $FILE_NODE_EXPORTER_SERVICE

  $SUDO tee /etc/logrotate.d/node_exporter >/dev/null << EOF
$LOG_FILE {
	missingok
	notifempty
	copytruncate
}
EOF
}

# Write systemd service file
create_systemd_service_file() {
  info "systemd: Creating service file '$FILE_NODE_EXPORTER_SERVICE'"
  $SUDO tee "$FILE_NODE_EXPORTER_SERVICE" >/dev/null << EOF
[Unit]
Description=Node exporter
Documentation=https://github.com/prometheus/node_exporter
After=local-fs.target network-online.target network.target
Wants=local-fs.target network-online.target network.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
KillMode=process
Delegate=yes
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/iptables -I INPUT 1 -p tcp --dport 9100 -s 127.0.0.1 -j ACCEPT
ExecStartPre=-/sbin/iptables -I INPUT 3 -p tcp --dport 9100 -j DROP
ExecStart=$BIN_DIR/node_exporter \\
    $CMD_NODE_EXPORTER_EXEC
EOF
}

# Write service file
create_service_file() {
  case $INIT_SYSTEM in
    openrc) create_openrc_service_file ;;
    systemd) create_systemd_service_file ;;
    *) fatal "Unknown init system '$INIT_SYSTEM'" ;;
  esac
}

# Get hashes of the current Node exporter bin and service files
get_installed_hashes() {
  $SUDO sha256sum $BIN_DIR/node_exporter $FILE_NODE_EXPORTER_SERVICE 2>&1 || true
}

# Enable systemd service
systemd_enable() {
  info "systemd: Enabling node_exporter unit"
  $SUDO systemctl enable $FILE_NODE_EXPORTER_SERVICE >/dev/null
  $SUDO systemctl daemon-reload >/dev/null
}
# Start systemd service
systemd_start() {
  info "systemd: Starting node_exporter"
  $SUDO systemctl restart node_exporter
}

# Enable openrc service
openrc_enable() {
    info "openrc: Enabling node_exporter service for default runlevel"
    $SUDO rc-update add node_exporter default >/dev/null
}
# Start openrc service
openrc_start() {
  info "openrc: Starting node_exporter"
  $SUDO $FILE_NODE_EXPORTER_SERVICE restart
}

# Startup service
service_enable_and_start() {
  [ "$INSTALL_NODE_EXPORTER_SKIP_ENABLE" = true ] && return
  case $INIT_SYSTEM in
    openrc) openrc_enable ;;
    systemd) systemd_enable ;;
    *) fatal "Unknown init system '$INIT_SYSTEM'" ;;
  esac

  [ "$INSTALL_NODE_EXPORTER_SKIP_START" = true ] && return
  POST_INSTALL_HASHES=$(get_installed_hashes)
  if [ "$PRE_INSTALL_HASHES" = "$POST_INSTALL_HASHES" ] && [ "$INSTALL_NODE_EXPORTER_FORCE_RESTART" != true ]; then
    info 'No change detected so skipping service start'
    return
  fi
  case $INIT_SYSTEM in
    openrc) openrc_start ;;
    systemd) systemd_start ;;
    *) fatal "Unknown init system '$INIT_SYSTEM'" ;;
  esac

  return 0
}

# ================
# MAIN
# ================
# Re-evaluate args to include env command
eval set -- "$(escape "$INSTALL_NODE_EXPORTER_EXEC") $(quote "$@")"
# Run
{
  verify_system
  setup_env "$@"
  download_and_verify
  create_killall
  create_uninstall
  systemd_disable
  service_enable_and_start
}
