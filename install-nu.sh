#!/usr/bin/env bash
#
# install-nushell.sh — install Nushell and add it to /etc/shells
# Supported distributions: Ubuntu (snapd), Debian (apt),
# Arch Linux (pacman), openSUSE (zypper), Fedora/RHEL (dnf).
#
set -euo pipefail

# Colored output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Detect the distribution
# ---------------------------------------------------------------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="${ID,,}"        # convert to lowercase
    DISTRO_LIKE="${ID_LIKE:-}" # may be empty
else
    error "Failed to detect the distribution: /etc/os-release is missing"
fi

info "Detected distribution: ${PRETTY_NAME:-$DISTRO_ID}"

# ---------------------------------------------------------------------------
# 2. Install functions for each family
# ---------------------------------------------------------------------------

install_ubuntu_snap() {
    info "Installing Nushell via snapd (Ubuntu)…"
    if ! command -v snap &>/dev/null; then
        error "snapd is not installed. Install snapd and run again."
    fi
    sudo snap install nushell --classic
}

install_debian_apt() {
    info "Installing Nushell via the official apt repository (Debian)…"
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl gnupg

    # Add the GPG key and the Fury repository
    curl -fsSL https://apt.fury.io/nushell/gpg.key \
        | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/fury-nushell.gpg

    echo "deb https://apt.fury.io/nushell/ /" \
        | sudo tee /etc/apt/sources.list.d/fury.list >/dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq nushell
}

install_arch_pacman() {
    info "Installing Nushell via pacman (Arch Linux)…"
    sudo pacman -Sy --noconfirm nushell
}

install_opensuse_zypper() {
    info "Installing Nushell via zypper (openSUSE)…"
    # The nushell package is available in the main openSUSE repositories.
    sudo zypper --non-interactive install nushell
}

install_fedora_dnf() {
    info "Installing Nushell via dnf (Fedora/RHEL)…"

    # Add the Fury repository for yum/dnf
    sudo tee /etc/yum.repos.d/fury-nushell.repo >/dev/null <<'EOF'
[fury-nushell]
name=Fury Nushell Repo
baseurl=https://yum.fury.io/nushell/
enabled=1
gpgcheck=1
gpgkey=https://yum.fury.io/nushell/gpg.key
EOF

    sudo dnf install -y nushell
}

# ---------------------------------------------------------------------------
# 3. Select and run the installer
# ---------------------------------------------------------------------------
case "$DISTRO_ID" in
    ubuntu)
        install_ubuntu_snap
        ;;
    debian)
        # snapd is not always preinstalled on Debian, so use the apt repository
        install_debian_apt
        ;;
    arch|manjaro|endeavouros)
        install_arch_pacman
        ;;
    opensuse*|suse|sles)
        install_opensuse_zypper
        ;;
    fedora|rhel|centos|rocky|almalinux)
        install_fedora_dnf
        ;;
    *)
        # For derivative distributions (ID_LIKE)
        if [[ "$DISTRO_LIKE" == *"debian"* ]]; then
            install_debian_apt
        elif [[ "$DISTRO_LIKE" == *"arch"* ]]; then
            install_arch_pacman
        elif [[ "$DISTRO_LIKE" == *"suse"* ]]; then
            install_opensuse_zypper
        elif [[ "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_LIKE" == *"rhel"* ]]; then
            install_fedora_dnf
        else
            error "Unsupported distribution: $DISTRO_ID (ID_LIKE=$DISTRO_LIKE). Install Nushell manually."
        fi
        ;;
esac

# ---------------------------------------------------------------------------
# 4. Verify that nu is installed
# ---------------------------------------------------------------------------
if ! command -v nu &>/dev/null; then
    error "The 'nu' executable was not found in PATH after installation. Check the installation manually."
fi

NU_PATH="$(command -v nu)"
info "Nushell installed: $NU_PATH"
nu --version

# ---------------------------------------------------------------------------
# 5. Add to /etc/shells (if not already there)
# ---------------------------------------------------------------------------
SHELLS_FILE="/etc/shells"

if [[ ! -f "$SHELLS_FILE" ]]; then
    warn "$SHELLS_FILE does not exist. Creating an empty file."
    sudo touch "$SHELLS_FILE"
fi

# Check whether an exact line match already exists
if grep -Fxq "$NU_PATH" "$SHELLS_FILE"; then
    info "$NU_PATH is already present in $SHELLS_FILE — skipping."
else
    info "Adding $NU_PATH to $SHELLS_FILE…"
    echo "$NU_PATH" | sudo tee -a "$SHELLS_FILE" >/dev/null
    info "Done. You can now change the shell with: chsh -s $NU_PATH"
fi

info "Nushell installation and setup completed successfully."
