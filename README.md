# 🚀 Fast SSH Tunnel Installer [XSH Tunnel]

A simple and reliable Bash script to quickly set up a secure SSH tunnel between your servers. Designed for end-users, this script automates SSH key setup, multi-port forwarding, and systemd service creation.

---

## Features

- Persistent SSH tunnel with auto-restart on failure
- Multi-port forwarding
- Easy installation and uninstallation
- No technical knowledge required

---

## Requirements

- Linux server (Debian/Ubuntu recommended)
- Root privileges
- Internet connection for initial setup
- `ssh`, `ssh-keygen`, `ssh-copy-id`, `autossh`, `systemctl` installed (script will install missing dependencies automatically)

---

## Installation

1. For Download and install the script use this link :

```bash
bash <(curl -Ls https://raw.githubusercontent.com/c0rtex-dev/xsh-tunnel/main/xsh-tunnel.sh)
```

## Follow the prompts to provide:

- Foreign IP and SSH port
- Foreign SSH user
- Local listen IP (usually `0.0.0.0`)
- Target host (usually `localhost`)
- Inbound and outbound ports (multi-port supported)

> **_NOTE:_**  You can use different ports for input and output.

The script will:

- Generate SSH keys
- Copy the key to the remote server
- Create a systemd service to keep the tunnel alive
- Apply system tweaks for low port access

## Usage

### Check the tunnel status:

```bash
systemctl status iran-to-foreign-xsh-tunnel
```

### Restart the tunnel manually:

```bash
systemctl restart iran-to-foreign-xsh-tunnel
```

### Stop the tunnel:

```bash
systemctl stop iran-to-foreign-xsh-tunnel
```

## Uninstallation

### To remove everything installed by the script:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/c0rtex-dev/xsh-tunnel/main/xsh-tunnel.sh) uninstall
```

## Support

### For questions, issues, or suggestions, please open an issue in this repository.