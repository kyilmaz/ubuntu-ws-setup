#!/bin/bash
# Ubuntu 24.04 LTS (Kubuntu) Installation Script
# Optimized for Development workloads + Hermes Agent
# Powered by Kyilmaz

# --- Configuration ---
NODE_VERSION="22"          # Hermes Agent requires Node.js 22+
NVIDIA_DRIVER="535"
PYTHON_VERSION="3.11"      # Hermes Agent requires Python 3.11

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# --- Logging ---
log()         { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# --- Helper Functions ---
is_installed() { dpkg -l "$1" &>/dev/null; }

# --- Script Setup ---
set -euo pipefail
trap 'log_error "Script failed at line $LINENO with command: $BASH_COMMAND"' ERR

# ---------------------------------------------------------------------------

handle_packagekit_conflict() {
    log "Handling PackageKit conflicts..."

    if pgrep -x "packagekitd" >/dev/null; then
        log "Stopping PackageKit daemon..."
        sudo systemctl stop packagekit 2>/dev/null || log_warning "Could not stop packagekit via systemctl"
        sleep 2
        if pgrep -x "packagekitd" >/dev/null; then
            log "Force killing PackageKit processes..."
            sudo pkill -9 -f packagekitd || true
        fi
    fi

    # systemctl disable fails harmlessly on statically-enabled units — just ignore it
    sudo systemctl disable packagekit 2>/dev/null || true

    log "Removing apt lock files..."
    sudo rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock

    log "Removing PackageKit..."
    sudo apt-get -y remove --purge packagekit || log_warning "Failed to remove PackageKit"
}

# ---------------------------------------------------------------------------

system_update_and_optimize() {
    log "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get autoremove -y

    if is_installed snapd; then
        log "Removing snapd..."
        sudo apt-get remove --purge snapd -y
        sudo apt-mark hold snapd
        rm -rf ~/snap || true
        sudo rm -rf /var/snap /var/lib/snapd
    fi

    log "Configuring power management to prevent sleep..."
    sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

    # Kubuntu uses KDE — kwriteconfig6 is the right tool, not gsettings/GNOME
    if command -v kwriteconfig6 &>/dev/null; then
        log "Setting KDE power management (no screen/suspend on AC)..."
        kwriteconfig6 --file powermanagementprofilesrc \
            --group "AC" --group "SuspendSession" --key "idleTime" "0"
        kwriteconfig6 --file powermanagementprofilesrc \
            --group "AC" --group "SuspendSession" --key "suspendType" "0"
        kwriteconfig6 --file powermanagementprofilesrc \
            --group "AC" --group "DPMSControl" --key "idleTime" "0"
        log "Setting KDE Night Color (always on, 5000K)..."
        kwriteconfig6 --file kwinrc \
            --group "NightColor" --key "Active" "true"
        kwriteconfig6 --file kwinrc \
            --group "NightColor" --key "Mode" "Constant"
        kwriteconfig6 --file kwinrc \
            --group "NightColor" --key "NightTemperature" "5000"
        log "Disabling KDE animations..."
        kwriteconfig6 --file kdeglobals \
            --group "KDE" --key "AnimationDurationFactor" "0"
        log "Disabling KDE automount..."
        kwriteconfig6 --file kded5rc \
            --group "Module-device_automounter" --key "autoload" "false" || true
    else
        log_warning "kwriteconfig6 not found — KDE settings skipped."
    fi

    # Keep udisks2 disabled (still relevant on Kubuntu to block automount)
    sudo systemctl disable udisks2 2>/dev/null || true
    sudo systemctl mask udisks2

    log "Disabling IPv6..."
    if ! grep -q 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.conf; then
        sudo tee -a /etc/sysctl.conf >/dev/null <<'EOF'

# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        sudo sysctl -p
        log "IPv6 disabled."
    else
        log "IPv6 already disabled."
    fi

    log "Applying SSH optimisations..."
    sudo sed -i.bkp1 's/#UseDNS no/UseDNS no/g'           /etc/ssh/sshd_config || log_warning "SSH: UseDNS tweak failed"
    sudo sed -i.bkp2 's/#AddressFamily any/AddressFamily inet/g' /etc/ssh/sshd_config || log_warning "SSH: AddressFamily tweak failed"

    log "Applying performance optimisations with tuned..."
    if ! is_installed tuned; then
        sudo apt-get install -y tuned tuned-utils
    fi
    sudo systemctl enable tuned --now
    sudo tuned-adm profile throughput-performance

    log "Setting kernel parameters for performance..."
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo 'vm.swappiness=10'        | sudo tee -a /etc/sysctl.conf
        echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
    fi
}

# ---------------------------------------------------------------------------

install_essential_tools() {
    log "Installing essential tools..."
    # mlocate was replaced by plocate in Ubuntu 22.04+; use plocate instead
    sudo apt-get install -y \
        curl wget gpg git duf archivemount \
        build-essential dkms software-properties-common \
        apt-transport-https ca-certificates gnupg lsb-release \
        vim nano htop neofetch tree apt-file plocate jq ripgrep pipx

    # Python 3.11 — Hermes Agent installer targets 3.11 specifically
    if ! command -v python3.11 &>/dev/null; then
        log "Installing Python 3.11 (required by Hermes Agent)..."
        sudo add-apt-repository -y ppa:deadsnakes/ppa
        sudo apt-get update
        sudo apt-get install -y python3.11 python3.11-venv python3.11-dev
    else
        log "Python 3.11 already present."
    fi

    # uv — Hermes Agent's Python package manager
    if ! command -v uv &>/dev/null; then
        log "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    else
        log "uv already installed."
    fi
}

# ---------------------------------------------------------------------------

install_extra_fonts() {
    log "Installing additional fonts..."
    sudo apt-get install -y \
        fonts-ipafont-gothic fonts-ipafont-mincho \
        fonts-wqy-microhei fonts-wqy-zenhei fonts-indic \
        || log_warning "Some fonts failed to install"
    sudo updatedb 2>/dev/null || true
}

# ---------------------------------------------------------------------------

install_multimedia_tools() {
    log "Installing multimedia tools..."
    sudo apt-get install -y ffmpeg obs-studio shotcut handbrake vlc
}

# ---------------------------------------------------------------------------

install_system_tools() {
    log "Installing system tools..."
    sudo apt-get install -y \
        filezilla partclone fsarchiver \
        xfsprogs reiserfsprogs reiser4progs jfsutils btrfs-progs \
        gnome-disk-utility gparted tilix flameshot \
        ncdu ranger fzf glances iotop tmux \
        remmina remmina-plugin-rdp \
        p7zip-full unzip \
        gnome-tweaks dconf-editor \
        postgresql-client redis-tools

    if ! is_installed rustdesk; then
        log "Installing RustDesk..."
        RUSTDESK_VERSION=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
            | grep -Po '"tag_name": "\K[^"\n]*')
        wget "https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-${RUSTDESK_VERSION}-x86_64.deb" \
            -O /tmp/rustdesk.deb
        sudo apt-get install -y /tmp/rustdesk.deb
        rm /tmp/rustdesk.deb
    else
        log "RustDesk already installed."
    fi

    if lspci | grep -i nvidia >/dev/null 2>&1; then
        log "NVIDIA GPU detected."
        if ! command -v nvidia-smi >/dev/null 2>&1; then
            log "Installing NVIDIA drivers..."
            sudo apt-get install -y "nvidia-driver-${NVIDIA_DRIVER}" "nvidia-dkms-${NVIDIA_DRIVER}"
        else
            log "NVIDIA drivers already present."
        fi
        if command -v nvidia-smi >/dev/null 2>&1 && ! command -v nvcc >/dev/null 2>&1; then
            log "Installing NVIDIA CUDA Toolkit..."
            sudo apt-get install -y nvidia-cuda-toolkit
        elif command -v nvcc >/dev/null 2>&1; then
            log "CUDA Toolkit already present."
        fi
    else
        log "No NVIDIA GPU detected — skipping driver/CUDA install."
    fi
}

# ---------------------------------------------------------------------------

install_dev_tools() {
    log "Installing programming languages & libraries..."

    if ! command -v rustc &>/dev/null; then
        log "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        log "Rust already installed."
    fi

    if ! command -v go &>/dev/null; then
        log "Installing Go..."
        sudo apt-get install -y golang-go
    else
        log "Go already installed."
    fi

    # NVM
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        log "Installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    else
        log "NVM already installed."
    fi
    # Source NVM so we can use it immediately in this session
    \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # Node.js 22 — required by Hermes Agent
    if ! nvm ls "$NODE_VERSION" 2>/dev/null | grep -q "v$NODE_VERSION"; then
        log "Installing Node.js v$NODE_VERSION..."
        nvm install "$NODE_VERSION"
        nvm use "$NODE_VERSION"
        nvm alias default "$NODE_VERSION"
    else
        log "Node.js v$NODE_VERSION already installed."
    fi

    # Miniconda
    if ! command -v conda &>/dev/null; then
        INSTALL_DIR="$HOME/miniconda3"
        if [ -d "$INSTALL_DIR" ]; then
            log_warning "Miniconda directory exists but conda not on PATH — skipping re-install."
        else
            log "Installing Miniconda..."
            INSTALL_PATH="/tmp/miniconda.sh"
            wget -q "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" -O "$INSTALL_PATH"
            bash "$INSTALL_PATH" -b -p "$INSTALL_DIR"
            "$INSTALL_DIR/bin/conda" init bash
            rm -f "$INSTALL_PATH"
            log "Miniconda installed."
        fi
        export PATH="$INSTALL_DIR/bin:$PATH"
    else
        log "Conda already installed."
    fi

    # Google Chrome
    if ! is_installed google-chrome-stable; then
        log "Installing Google Chrome..."
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
            | sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] \
http://dl.google.com/linux/chrome/deb/ stable main" \
            | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
        sudo apt-get update
        sudo apt-get install -y google-chrome-stable
    else
        log "Google Chrome already installed."
    fi

    # Firefox (snapd is removed, so install from PPA)
    if ! is_installed firefox && ! is_installed firefox-esr; then
        log "Installing Firefox ESR..."
        sudo add-apt-repository -y ppa:mozillateam/ppa
        # Prefer the PPA over any stale snap candidate
        echo 'Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001' | sudo tee /etc/apt/preferences.d/mozilla-firefox >/dev/null
        sudo apt-get update
        sudo apt-get install -y firefox-esr
    else
        log "Firefox already installed."
    fi

    # Docker
    if ! is_installed docker-ce; then
        log "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo mkdir -p /opt/containers/docker
        sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "data-root": "/opt/containers/docker",
  "storage-driver": "overlay2"
}
EOF
        sudo usermod -aG docker "$USER"
        sudo systemctl enable docker --now
    else
        log "Docker already installed."
    fi

    # Minikube
    if ! command -v minikube &>/dev/null; then
        log "Installing Minikube..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
    else
        log "Minikube already installed."
    fi
}

# ---------------------------------------------------------------------------

install_hermes_agent() {
    log "Installing Hermes Agent..."

    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if command -v hermes &>/dev/null; then
        log "Hermes Agent already installed — updating..."
        hermes update || log_warning "hermes update failed, try manually later."
        return
    fi

    log "Running Hermes official installer (git/main)..."
    curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash

    export PATH="$HOME/.hermes/hermes-agent/venv/bin:$HOME/.local/bin:$PATH"

    if command -v hermes &>/dev/null; then
        log "Hermes Agent installed successfully."
        log "Next: 'hermes doctor'  — verify setup"
        log "Next: 'hermes gateway setup'  — connect Telegram/Discord/Slack etc."
    else
        log_warning "hermes not found on PATH yet — reload your shell: source ~/.bashrc"
        log_warning "Then run: hermes doctor"
    fi
}

# ---------------------------------------------------------------------------

configure_shell() {
    log "Setting up shell configuration..."

    if ! grep -q "# Custom aliases" ~/.bashrc; then
        log "Updating .bashrc..."
        cp ~/.bashrc ~/.bashrc.backup."$(date +%Y%m%d)"
        cat <<'EOF' >>~/.bashrc

# Custom aliases
alias ll='ls -alF'
alias c='clear'
alias ports='netstat -tulanp'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias py='python3'
alias dc='docker compose'
alias dps='docker ps'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ln='ln -i'
alias df='df -h'
alias du='du -h'
alias less='less -r'
alias whence='type -a'
alias grep='grep --color'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias ls='ls -hF --color=tty'
alias dir='ls --color=auto --format=vertical'
alias vdir='ls --color=auto --format=long'
EOF
    fi

    if ! grep -q "remotedisplay" ~/.profile; then
        log "Updating .profile..."
        cp ~/.profile ~/.profile.backup."$(date +%Y%m%d)"
        cat <<'EOF' >>~/.profile

# Set DISPLAY when connecting over SSH (for X11 forwarding)
if [ -n "$SSH_CONNECTION" ]; then
  function remotedisplay() {
    remoteip=$(who am i | awk '{print $NF}' | tr -d ')(')
  }
  remotedisplay
  if [ -n "${remoteip:-}" ]; then
    DISPLAY=$remoteip:0.0
    export DISPLAY
  fi
fi

parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
export PS1="\[\033[38;5;141m\]\u\[\033[0m\]@\[\033[38;5;39m\]\h\[\033[0m\]:\[\033[1;37m\]\W\[\033[0;33m\]\$(parse_git_branch)\[\033[0m\]\$ "

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

export PATH="$HOME/.cargo/bin:$HOME/miniconda3/bin:$HOME/.local/bin:$HOME/.hermes/hermes-agent/venv/bin:$PATH"
EOF
    fi
}

# ---------------------------------------------------------------------------

install_flatpak() {
    log "Installing Flatpak support..."
    # On Kubuntu use plasma-discover-backend-flatpak, not gnome-software-plugin-flatpak
    sudo apt-get install -y flatpak plasma-discover-backend-flatpak
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

# ---------------------------------------------------------------------------

cleanup_and_finalize() {
    log "Cleaning up..."
    sudo apt-get autoremove -y
    sudo apt-get autoclean

    # Reinstall Kubuntu-appropriate package management tools
    # (do NOT reinstall gnome-software on Kubuntu — use plasma-discover)
    log "Re-enabling PackageKit..."
    sudo apt-get -y install --reinstall packagekit plasma-discover
    sudo systemctl unmask packagekit 2>/dev/null || true
    sudo systemctl enable packagekit 2>/dev/null || true
    sudo systemctl start packagekit  2>/dev/null || true
}

# ---------------------------------------------------------------------------

show_help() {
    echo -e "${BLUE}Usage: $0 [function_name]...${NC}"
    echo
    echo -e "${YELLOW}Description:${NC}"
    echo "  Ubuntu 24.04 (Kubuntu) setup script — dev environment + Hermes Agent."
    echo "  No arguments = full installation."
    echo
    echo -e "${YELLOW}Available functions:${NC}"
    compgen -A function | grep -E "^handle_|^system_|^install_|^configure_|^cleanup_" | sed 's/^/  /'
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0                            # Full install"
    echo "  $0 install_hermes_agent       # Install Hermes only"
    echo "  $0 install_dev_tools configure_shell"
}

# ---------------------------------------------------------------------------

main() {
    clear
    echo -e "${BLUE}============================================${NC}"
    echo -e "${GREEN}  Ubuntu 24.04 (Kubuntu) Setup Script     ${NC}"
    echo -e "${GREEN}  Dev Environment + Hermes Agent          ${NC}"
    echo -e "${BLUE}============================================${NC}"

    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this script as root!"
        exit 1
    fi

    if ! sudo -v; then
        log_error "Sudo access required but not granted."
        exit 1
    fi

    if [[ "$#" -eq 0 ]]; then
        handle_packagekit_conflict
        system_update_and_optimize
        install_essential_tools
        install_extra_fonts
        install_multimedia_tools
        install_system_tools
        install_dev_tools
        install_hermes_agent
        configure_shell
        install_flatpak
        cleanup_and_finalize
    elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    else
        for func_name in "$@"; do
            if declare -f "$func_name" >/dev/null; then
                log "Executing: $func_name"
                "$func_name"
            else
                log_error "Unknown function: '$func_name'"
                show_help
                exit 1
            fi
        done
    fi

    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Done! Reboot if prompted to do so.      ${NC}"
    echo -e "${GREEN}============================================${NC}"
}

main "$@"
