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
    if pgrep -x "packagekitd" >/dev/null; then
        log "Stopping PackageKit daemon..."
        sudo systemctl stop packagekit || log_warning "Could not stop packagekit via systemctl"
        sleep 2
        if pgrep -x "packagekitd" >/dev/null; then
            log "Force killing PackageKit processes..."
            sudo pkill -9 -f packagekitd || true
        fi
    fi

    if systemctl is-enabled --quiet packagekit; then
        log "Temporarily disabling PackageKit..."
        sudo systemctl disable packagekit || log_warning "Could not disable packagekit"
    fi

    log "Removing apt lock files..."
    sudo rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock

    log "Removing PackageKit..."
    sudo apt-get -y remove --purge packagekit || log_warning "Failed to remove PackageKit"
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

    log "Setting night-light to be always on..."
    gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-automatic false
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-from 0
    gsettings set org.gnome.settings-daemon.plugins.color night-light-schedule-to 24
    gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature 5000

    log "Disabling IPv6 and applying network/SSH optimizations..."
    echo "exec gnome-session" >~/.xsession
    chmod +x ~/.xsession
    gsettings set org.gnome.desktop.interface enable-animations false || log_warning "Failed to disable animations"

    if ! grep -q 'net.ipv6.conf.all.disable_ipv6 = 1' /etc/sysctl.conf; then
        sudo tee -a /etc/sysctl.conf >/dev/null <<EOF

# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        sudo sysctl -p
        log "IPv6 has been disabled via sysctl."
    else
        log "IPv6 disable settings already present in /etc/sysctl.conf"
    fi

    sudo sed -i.bkp1 's/#UseDNS no/UseDNS no/g' /etc/ssh/sshd_config || log_warning "Failed to disable DNS resolve on ssh"
	
    sudo sed -i.bkp2 's/#AddressFamily any/AddressFamily inet/g' /etc/ssh/sshd_config || log_warning "Failed to set ssh to inet"
	
    log "Applying performance optimizations with tuned..."
    if ! is_installed tuned; then
        log "Installing tuned..."
        sudo apt-get install -y tuned tuned-utils
    fi
    sudo systemctl enable tuned --now
    sudo tuned-adm profile throughput-performance

    log "Setting kernel parameters for performance..."
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
        echo 'vm.vfs_cache_pressure=50' | sudo tee -a /etc/sysctl.conf
    fi
}

install_essential_tools() {
    log "Installing essential tools..."
    sudo apt-get install -y curl wget gpg git build-essential dkms software-properties-common apt-transport-https ca-certificates gnupg lsb-release vim nano htop neofetch tree apt-file locate mlocate jq 
}

install_extra_fonts() {
    log "Installing Additional Fonts..."
    sudo apt-get install -y fonts-ipafont-gothic fonts-ipafont-mincho fonts-wqy-microhei fonts-wqy-zenhei fonts-indic || log_warning "Font installation is failed"
    sudo updatedb
}

install_multimedia_tools() {
    log "Installing multimedia tools..."
    sudo apt-get install -y ffmpeg obs-studio shotcut handbrake vlc
}

install_system_tools() {
    log "Installing system tools..."
    sudo apt-get install -y filezilla gnome-disk-utility gparted tilix flameshot ncdu ranger fzf glances iotop tmux remmina remmina-plugin-rdp p7zip-full unzip gnome-tweaks dconf-editor postgresql-client redis-tools

    if ! is_installed rustdesk; then
        log "Installing RustDesk..."
        RUSTDESK_VERSION=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -Po '"tag_name": "\K[^"\n]*')
        wget "https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-${RUSTDESK_VERSION}-x86_64.deb" -O /tmp/rustdesk.deb
        sudo apt-get install -y /tmp/rustdesk.deb
        rm /tmp/rustdesk.deb
    else
        log "RustDesk is already installed."
    fi
    
    if lspci | grep -i nvidia >/dev/null 2>&1; then
        log "NVIDIA GPU detected."

        if ! command -v nvidia-smi >/dev/null 2>&1; then
            log "Installing Nvidia drivers..."
            sudo apt-get install -y "nvidia-driver-${NVIDIA_DRIVER}" "nvidia-dkms-${NVIDIA_DRIVER}"
        else
            log "Nvidia drivers appear to be installed."
        fi

        if command -v nvidia-smi >/dev/null 2>&1 && ! command -v nvcc >/dev/null 2>&1; then
            log "Installing Nvidia CUDA Toolkit..."
            sudo apt-get install -y nvidia-cuda-toolkit
        elif command -v nvcc >/dev/null 2>&1; then
            log "Nvidia CUDA Toolkit is present."
        fi
    else
        log "No NVIDIA GPU detected. Skipping Nvidia driver and CUDA installation."
    fi

}

install_dev_tools() {
    log "Installing programming languages & libraries..."

    if ! command -v rustc &>/dev/null; then
        log "Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    else
        log "Rust is already installed."
    fi

    if ! command -v go &>/dev/null; then
        log "Installing Go..."
        sudo apt-get install -y golang-go
    else
        log "Go is already installed."
    fi
  
    if ! command -v nvm &>/dev/null; then
        log "NVM is not installed. Installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    else
        log "NVM is already installed."
    fi

    if ! nvm ls "$NODE_VERSION" | grep -q "v$NODE_VERSION"; then
        log "Installing Node.js v$NODE_VERSION via NVM..."
        nvm install "$NODE_VERSION"
        nvm use "$NODE_VERSION"
        nvm alias default "$NODE_VERSION"
    else
        log "Node.js v$NODE_VERSION is already installed."
    fi

    if ! command -v conda &>/dev/null; then
        log "Conda not found. Installing Miniconda..."
        INSTALL_DIR="$HOME/miniconda3"
        INSTALLER="Miniconda3-latest-Linux-x86_64.sh"
        INSTALL_PATH="/tmp/miniconda.sh"
        DOWNLOAD_URL="https://repo.anaconda.com/miniconda/$INSTALLER"
        if [ -d "$INSTALL_DIR" ]; then
            log_warning "Miniconda directory already exists. Skipping installation."
        else
            log "Downloading Miniconda..."
            wget -q "$DOWNLOAD_URL" -O "$INSTALL_PATH"
            log "Installing Miniconda..."
            bash "$INSTALL_PATH" -b -p "$INSTALL_DIR"
            log "Initializing Conda..."
            "$INSTALL_DIR/bin/conda" init bash
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
