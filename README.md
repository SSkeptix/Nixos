# Nixos Install
It contains a public script to pull private repo and install nixos from there.

## 🧩 NixOS Dotfiles Setup Script

This script automates NixOS setup using your GitHub dotfiles.

### What it does
- 🔐 Creates an **SSH key** (if missing) and shows it as text + QR code
- 🧰 Clones your **dotfiles repo**
- 🧱 Runs `nixos-rebuild switch --flake .` to apply the config  

### Requirements
- NixOS  
- Internet connection  
- Sudo privileges  

### Usage
```bash
curl -fsSL https://sskeptix.github.io/NixosInstall/install.sh | sh
```
Or for others
```bash
curl -fsSL https://sskeptix.github.io/NixosInstall/install.sh | sh -s "git@github.com:other/repo.git" "/custom/path"

```
