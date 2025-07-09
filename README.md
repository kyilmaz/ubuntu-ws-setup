'''# Ubuntu Workspace Setup Script

This script automates the setup of a complete development environment on a fresh Ubuntu 22.04 LTS installation. It is designed to be modular and idempotent, meaning you can run it multiple times without issues, and you can choose to run only specific parts of the installation.

## Features

- **System Optimization**: Disables sleep, removes Snapd, optimizes system parameters, and disables IPv6.
- **Essential Tools**: Installs common command-line tools like `git`, `curl`, `htop`, `neofetch`, etc.
- **Development Languages**: Installs Node.js, Rust, Go, and Miniconda (Python).
- **Containerization**: Installs Docker, Docker Compose, Rancher Desktop, and Minikube.
- **System & GUI Tools**: Installs multimedia applications, system utilities like GParted, and productivity tools like Flameshot and Remmina.
- **Shell Configuration**: Adds useful aliases and a custom prompt to `~/.bashrc` and `~/.profile`.
- **Modular Execution**: Allows running specific setup functions individually.

## Prerequisites

- A fresh installation of Ubuntu 22.04 LTS.
- Sudo (administrator) privileges.

## Usage

First, make the script executable:

```bash
chmod +x ubuntu-ws-setup.sh
```

### Running the Full Installation

To run the entire setup process, simply execute the script without any arguments. This is the recommended method for a new system.

```bash
./ubuntu-ws-setup.sh
```

### Running Specific Parts of the Installation

You can run one or more specific functions by passing their names as arguments to the script. This is useful if you only want to install a specific set of tools or re-run a part of the configuration.

To see a list of all available functions, use the `-h` or `--help` flag:

```bash
./ubuntu-ws-setup.sh --help
```

This will display a help menu with the list of available functions.

#### Examples

- **Install only development tools:**

  ```bash
  ./ubuntu-ws-setup.sh install_dev_tools
  ```

- **Install system tools and configure the shell:**

  ```bash
  ./ubuntu-ws-setup.sh install_system_tools configure_shell
  ```

- **Update the system and install essential tools:**

  ```bash
  ./ubuntu-ws-setup.sh system_update_and_optimize install_essential_tools
  ```

## Notes

- The script should **not** be run as root. It will ask for sudo privileges when needed.
- A reboot is recommended after the script finishes to ensure all changes take effect.
- The script creates backups of your `~/.bashrc` and `~/.profile` files before modifying them.
'''