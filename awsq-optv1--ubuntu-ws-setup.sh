#!/bin/bash
# Ubuntu 22.04 LTS Installation Script
# Optimized for Development workloads
# Powered by Kyilmaz
# 

# --- Configuration ---
NODE_VERSION="18"
NVIDIA_DRIVER="535"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Logging ---
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# --- Helper Functions ---
is_installed() {
    dpkg -l "$1" &>/dev/null
}

# --- Script Setup ---
# Exit on error, treat unset variables as an error, and propagate exit status through pipes
set -euo pipefail
trap 'log_error "Script failed at line $LINENO with command: $BASH_COMMAND"' ERR

# --- Installation Functions ---

handle_packagekit_conflict() {
    log "Handling PackageKit conflicts..."
    
    # Stop and disable PackageKit
    if pgrep -x "packagekitd" >/dev/null; then
        sudo systemctl stop packagekit 2>/dev/null || true
        sleep 1
        sudo pkill -9 -f packagekitd 2>/dev/null || true
    fi
    
    systemctl is-enabled --quiet packagekit 2>/dev/null && sudo systemctl disable packagekit 2>/dev/null || true
    
    # Clean up locks and remove PackageKit
    sudo rm -f /var/lib/dpkg/lock* /var/cache/apt/archives/lock 2>/dev/null || true
    sudo apt-get -y remove --purge packagekit 2>/dev/null || true
}

system_update_and_optimize() {
    log "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get autoremove -y

    if is_installed snapd; then
        log "Removing snapd..."
        sudo apt-get remove --purge snapd -y
        sudo apt-mark hold snapd
        rm -rf ~/snap
        sudo rm -rf /var/snap
        sudo rm -rf /var/lib/snapd
    fi

    log "Configuring power management to prevent sleep..."
    sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'

    log "Configuring GNOME settings..."
    {
        gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
        gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic false
        gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 0
        gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 24
        gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 5000
        gsettings set org.gnome.desktop.interface enable-animations false
        gsettings set org.gnome.desktop.media-handling automount-open false
        gsettings set org.gnome.desktop.media-handling automount false
    } 2>/dev/null || log_warning "Some GNOME settings failed"
    
    echo "exec gnome-session" >~/.xsession && chmod +x ~/.xsession
    sudo systemctl disable udisks2 2>/dev/null && sudo systemctl mask udisks2 2>/dev/null || true

    # Configure sysctl settings
    if ! grep -q 'net.ipv6.conf.all.disable_ipv6' /etc/sysctl.conf; then
        sudo tee -a /etc/sysctl.conf >/dev/null <<'EOF'

# Performance and IPv6 settings
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
        sudo sysctl -p >/dev/null
    fi
    
    # SSH optimizations
    sudo sed -i.bak -e 's/#UseDNS no/UseDNS no/' -e 's/#AddressFamily any/AddressFamily inet/' /etc/ssh/sshd_config 2>/dev/null || true
	
    # Install and configure tuned for performance
    if ! is_installed tuned; then
        sudo apt-get install -y tuned tuned-utils
        sudo systemctl enable tuned --now
        sudo tuned-adm profile throughput-performance
    fi
}

install_essential_tools() {
    log "Installing essential tools..."
    sudo apt-get install -y \
        curl wget gpg git duf archivemount build-essential dkms \
        software-properties-common apt-transport-https ca-certificates \
        gnupg lsb-release vim nano htop neofetch tree apt-file \
        locate mlocate jq
}

install_extra_fonts() {
    log "Installing additional fonts..."
    sudo apt-get install -y \
        fonts-ipafont-gothic fonts-ipafont-mincho \
        fonts-wqy-microhei fonts-wqy-zenhei fonts-indic
    sudo updatedb 2>/dev/null || true
}

install_multimedia_tools() {
    log "Installing multimedia tools..."
    sudo apt-get install -y ffmpeg obs-studio shotcut handbrake vlc
}

install_system_tools() {
    log "Installing system tools..."
    sudo apt-get install -y \
        filezilla partclone fsarchiver xfsprogs reiserfsprogs reiser4progs \
        jfsutils ntfsprogs btrfs-progs gnome-disk-utility gparted tilix \
        flameshot ncdu ranger fzf glances iotop tmux remmina remmina-plugin-rdp \
        p7zip-full unzip gnome-tweaks dconf-editor postgresql-client redis-tools

    # Install RustDesk
    if ! is_installed rustdesk; then
        log "Installing RustDesk..."
        local version=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | jq -r .tag_name)
        wget -q "https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-${version}-x86_64.deb" -O /tmp/rustdesk.deb
        sudo apt-get install -y /tmp/rustdesk.deb && rm /tmp/rustdesk.deb
    fi
    
    # NVIDIA setup
    if lspci | grep -qi nvidia; then
        log "NVIDIA GPU detected"
        ! command -v nvidia-smi >/dev/null && sudo apt-get install -y "nvidia-driver-${NVIDIA_DRIVER}" "nvidia-dkms-${NVIDIA_DRIVER}"
        command -v nvidia-smi >/dev/null && ! command -v nvcc >/dev/null && sudo apt-get install -y nvidia-cuda-toolkit
    fi
}

install_dev_tools() {
    log "Installing development tools..."
    
    # Install basic dev packages
    ! command -v go >/dev/null && sudo apt-get install -y golang-go
    
    # Install Rust
    if ! command -v rustc >/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    
    # Install NVM and Node.js
    if ! command -v nvm >/dev/null; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
        nvm install "$NODE_VERSION" && nvm alias default "$NODE_VERSION"
    fi
    
    # Install Miniconda
    if ! command -v conda >/dev/null && [ ! -d "$HOME/miniconda3" ]; then
        wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
        bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
        "$HOME/miniconda3/bin/conda" init bash
        rm /tmp/miniconda.sh
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi bash
            rm -f "$INSTALL_PATH"
            log "Miniconda installed successfully."
        fi
        export PATH="$INSTALL_DIR/bin:$PATH"
    else
        log "Conda is already installed."
    fi

    if ! is_installed google-chrome-stable; then
        log "Installing Google Chrome..."
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
        sudo apt-get update
        sudo apt-get install -y google-chrome-stable
    else
        log "Google Chrome is already installed."
    fi
    
    if ! is_installed firefox; then
        log "Installing Firefox ESR..."
        sudo add-apt-repository -y ppa:mozillateam/ppa
        sudo apt-get update
        sudo apt install -y firefox-esr
    else
        log "Firefox is already installed."
    fi	

    if ! is_installed docker-ce; then
        log "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        log "Configuring Docker..."
        sudo mkdir -p /opt/containers/docker
        sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "data-root": "/opt/containers/docker",
  "storage-driver": "overlay2"
}
EOF
        sudo usermod -aG docker "$USER"
        sudo systemctl enable docker --now
    else
        log "Docker is already installed."
    fi

    if ! is_installed rancher-desktop; then
        log "Installing Rancher Desktop..."
        curl -s https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/Release.key | gpg --yes --dearmor | sudo dd status=none of=/usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg
        echo 'deb [signed-by=/usr/share/keyrings/isv-rancher-stable-archive-keyring.gpg] https://download.opensuse.org/repositories/isv:/Rancher:/stable/deb/ ./' | sudo tee /etc/apt/sources.list.d/isv-rancher-stable.list >/dev/null
        sudo apt-get update
        sudo apt-get install -y rancher-desktop
    else
        log "Rancher Desktop is already installed."
    fi

    if ! command -v minikube &>/dev/null; then
        log "Installing Minikube..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
    else
        log "Minikube is already installed."
    fi
}

configure_shell() {
    log "Setting up shell configuration..."
    if ! grep -q "# Custom aliases" ~/.bashrc; then
        log "Backing up and updating .bashrc..."
        cp ~/.bashrc ~/.bashrc.backup.$(date +%Y%m%d)
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
        log "Backing up and updating .profile..."
        cp ~/.profile ~/.profile.backup.$(date +%Y%m%d)
        cat <<'EOF' >>~/.profile

# Function remotedisplay to get ip for ssh
if [ -n "$SSH_CONNECTION" ]; then
  function remotedisplay() {
    remoteip=$(who am i | awk '{print $NF}' | tr -d ')''(' )
  }
  remotedisplay
  if [ -n "$remoteip" ]; then
    DISPLAY=$remoteip:0.0
    export DISPLAY
  fi
fi

parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}
export PS1="\[\033[38;5;141m\]\u\[\033[0m\]@\[\033[38;5;39m\]\h\[\033[0m\]:\[\033[1;37m\]\W\[\033[0;33m\]\$(parse_git_branch)\[\033[0m\]\$ "

export NVM_DIR="$HOME/.nvm"

export PATH="$HOME/.cargo/bin:$HOME/miniconda3/bin:$PATH"
EOF
    fi
}

install_flatpak() {
    log "Installing Flatpak support..."
    sudo apt-get install -y flatpak gnome-software-plugin-flatpak
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

cleanup_and_finalize() {
    log "Cleaning up..."
    sudo apt-get autoremove -y
    sudo apt-get autoclean

    log "Re-enabling PackageKit..."
    sudo apt-get -y install --reinstall packagekit gnome-software
    sudo systemctl unmask packagekit
    sudo systemctl enable packagekit
    sudo systemctl start packagekit
}

show_help() {
    echo -e "${BLUE}Usage: $0 [function_name]...${NC}"
    echo
    echo -e "${YELLOW}Description:${NC}"
    echo "  This script installs and configures a development environment on Ubuntu 22.04."
    echo "  If no arguments are provided, it runs the full installation."
    echo
    echo -e "${YELLOW}Available functions:${NC}"
    compgen -A function | grep -E "^handle_|^system_|^install_|^configure_|^cleanup_" | sed 's/^/  /'
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0                            # Run the full installation"
    echo "  $0 install_dev_tools          # Install only development tools"
    echo "  $0 install_dev_tools configure_shell # Install dev tools and configure the shell"
}

main() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}  Ubuntu 22.04 Setup Script           ${NC}"
    echo -e "${GREEN}  Refactored and Enhanced             ${NC}"
    echo -e "${BLUE}========================================${NC}"

    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this script as root!"
        exit 1
    fi

    if ! sudo -v; then
        log_error "Sudo access required but not granted"
        exit 1
    fi

    if [[ "$#" -eq 0 ]]; then
        # --- Full Installation ---
        handle_packagekit_conflict
        system_update_and_optimize
        install_essential_tools
        install_extra_fonts
        install_multimedia_tools
        install_system_tools
        install_dev_tools
        configure_shell
        install_flatpak
        cleanup_and_finalize
    elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_help
        exit 0
    else
        # --- Selective Execution ---
        for func_name in "$@"; do
            if declare -f "$func_name" > /dev/null; then
                log "Executing: $func_name"
                "$func_name"
            else
                log_error "Invalid function name: '$func_name'"
                show_help
                exit 1
            fi
        done
    fi

    # --- Completion ---
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Operation Complete!                   ${NC}"
    echo -e "${GREEN}  Please reboot your system if necessary  ${NC}"
    echo -e "${YELLOW}  to ensure all changes take effect.    ${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# --- Script Entrypoint ---
main "$@"
