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

# Escape most punctuation characters, except quotes, forward slash, and space
escape() {
  printf '%s' "$@" | sed -e 's/\([][!#$%&()*;<=>?\_`{|}]\)/\\\1/g;'
}

# Define needed environment variables
setup_env() {
  # use sudo if we are not already root
  SUDO=sudo
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=
  fi

  # Use binary install directory if defined or create default
  if [ -n "$INSTALL_NODE_EXPORTER_BIN_DIR" ]; then
    BIN_DIR=${INSTALL_NODE_EXPORTER_BIN_DIR}
  else
    # Use /usr/local/bin if root can write to it, otherwise use /opt/bin if it exists
    BIN_DIR=/usr/local/bin
    if ! $SUDO sh -c "touch $BIN_DIR/node_exporter-ro-test && rm -rf $BIN_DIR/node_exporter-ro-test"; then
      if [ -d /opt/bin ]; then
        BIN_DIR=/opt/bin
      fi
    fi
  fi
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
    *) fatal "Architecture $ARCH not supported" ;;
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
    *) fatal "OS $OS not supported" ;;
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
    *) fatal "OS $OS not supported" ;;
  esac

  # Not supported
  fatal "Architecture $ARCH on OS $OS not supported";
}

# Verify command is installed
verify_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "$1 not found"
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
  verify_init_system
  verify_arch
  verify_os
  verify_arch_os
  verify_cmd "tar"
  verify_downloader_cmd "curl" "wget"
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
    _github_api_url=https://api.github.com/repos/prometheus/node_exporter/releases/latest
    case $DOWNLOADER in
      curl)
        VERSION_NODE_EXPORTER=$(curl -L -f -s -S $_github_api_url) || fatal "Download '$_github_api_url' failed"
      ;;
      wget)
        VERSION_NODE_EXPORTER=$(wget -q -O - $_github_api_url 2>&1) || fatal "Download '$_github_api_url' failed"
      ;;
      *)
        fatal "Invalid downloader '$DOWNLOADER'"
      ;;
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
  HASH_URL=$GITHUB_URL/download/$VERSION_NODE_EXPORTER/sha256sums.txt
  info "Downloading hash '$HASH_URL'"
  download "$TMP_HASH" "$HASH_URL"
  HASH_EXPECTED=$(grep " $RELEASE_ARCHIVE" "$TMP_HASH")
  HASH_EXPECTED=${HASH_EXPECTED%%[[:blank:]]*}
}

# Download archive
download_archive() {
  ARCHIVE_URL=$GITHUB_URL/download/$VERSION_NODE_EXPORTER/$RELEASE_ARCHIVE
  info "Downloading archive '$ARCHIVE_URL'"
  download "$TMP_ARCHIVE" "$ARCHIVE_URL"
}

# Verify downloaded archive hash
verify_archive() {
  info "Verifying archive download"
  HASH_ARCHIVE=$(sha256sum "$TMP_ARCHIVE")
  HASH_ARCHIVE=${HASH_ARCHIVE%%[[:blank:]]*}
  if [ "$HASH_EXPECTED" != "$HASH_ARCHIVE" ]; then
    fatal "Download sha256 does not match '$HASH_EXPECTED', got '$HASH_ARCHIVE'"
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
    HASH_INSTALLED=$(sha256sum $BIN_DIR/node_exporter)
    HASH_INSTALLED=${HASH_INSTALLED%%[[:blank:]]*}
    if [ "$HASH_BIN_EXPECTED" = "$HASH_INSTALLED" ]; then
      return 0
    fi
  fi
  return 1
}

# Setup permissions and move binary to system directory
setup_binary() {
  chmod 755 "$TMP_BIN"
  info "Installing Node exporter to $BIN_DIR/node_exporter"
  $SUDO chown root:root "$TMP_BIN"
  $SUDO mv -f "$TMP_BIN" "$BIN_DIR/k3s"
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


# ================
# MAIN
# ================
# Re-evaluate args to include env command
eval set -- "$(escape "${INSTALL_NODE_EXPORTER_EXEC}") $(quote "$@")"
# Run
{
  verify_system
  setup_env "$@"
  download_and_verify
}
