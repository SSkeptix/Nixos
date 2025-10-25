#!/bin/sh
set -e

REPOSITORY="${1:-git@github.com:sskeptix/NixConfig2.git}"
DOTFILES_FOLDER_RELATIVE_PATH="${2:-.dotfiles}"

echo "Checking sudo privileges..."
if ! command -v sudo >/dev/null 2>&1; then
    echo "Installing temporary sudo..."
    nix-shell -p sudo --run 'echo "✓ sudo available in nix-shell"'
fi

if ! sudo -v 2>/dev/null; then
    echo "Error: Current user does not have sudo privileges."
    echo "Run this as a user with sudo rights (not as root)."
    exit 1
fi
echo "✓ sudo privileges confirmed"

if [ -n "$SUDO_USER" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(eval echo ~$SUDO_USER)
else
    ACTUAL_USER=$(whoami)
    ACTUAL_HOME="$HOME"
fi

DOTFILES_FOLDER_PATH="${ACTUAL_HOME}/${DOTFILES_FOLDER_RELATIVE_PATH}"
echo ""
echo "User: ${ACTUAL_USER}"
echo "Home: ${ACTUAL_HOME}"
echo "Repository: ${REPOSITORY}"
echo "Dotfiles path: ${DOTFILES_FOLDER_PATH}"

echo ""
echo "Checking network..."
if ! ping -c1 github.com >/dev/null 2>&1; then
    echo "❌ Network unavailable. Please connect to the Internet and retry."
    exit 1
fi
echo "✓ Network OK"

echo ""
echo "Entering nix-shell with git, qrencode, nix, and sudo..."
NIX_CONFIG="experimental-features = nix-command flakes" \
nix-shell -p git qrencode nix sudo openssh --run '
    set -e
    export PATH="/run/wrappers/bin:$PATH"

    ACTUAL_USER="'"${ACTUAL_USER}"'"
    ACTUAL_HOME="'"${ACTUAL_HOME}"'"
    DOTFILES_FOLDER_PATH="'"${DOTFILES_FOLDER_PATH}"'"
    REPOSITORY="'"${REPOSITORY}"'"

    SSH_DIR="${ACTUAL_HOME}/.ssh"
    SSH_KEY_PATH="${SSH_DIR}/id_ed25519"
    echo ""
    echo "✅ Setting up .ssh directory and keys..."

    if [ ! -d "$SSH_DIR" ]; then
        echo "Creating $SSH_DIR..."
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        chown "$ACTUAL_USER" "$SSH_DIR"
    else
        echo "$SSH_DIR already exists. Fixing permissions..."
        chmod 700 "$SSH_DIR"
        chown "$ACTUAL_USER" "$SSH_DIR"
    fi

    if [ ! -f "$SSH_KEY_PATH" ]; then
        echo "Generating SSH key..."
        sudo -u "$ACTUAL_USER" ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "nixos-setup"
    else
        echo "SSH key already exists at $SSH_KEY_PATH"
    fi

    # Set proper permissions on key files
    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "${SSH_KEY_PATH}.pub"
    chown "$ACTUAL_USER" "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"

    # Ensure known_hosts exists and is writable
    KNOWN_HOSTS="${SSH_DIR}/known_hosts"
    touch "$KNOWN_HOSTS"
    chmod 644 "$KNOWN_HOSTS"
    chown "$ACTUAL_USER" "$KNOWN_HOSTS"

    # Add repository host to known_hosts safely
    REPO_HOST=$(echo "${REPOSITORY}" | sed "s/.*@\([^:]*\).*/\1/")
    if grep -q "${REPO_HOST}" "$KNOWN_HOSTS" 2>/dev/null; then
        echo "✓ $REPO_HOST already in known_hosts"
    else
        echo "Adding $REPO_HOST to known_hosts..."
        sudo -u "$ACTUAL_USER" ssh-keyscan -t ed25519 "$REPO_HOST" >> "$KNOWN_HOSTS"
        chmod 644 "$KNOWN_HOSTS"
        chown "$ACTUAL_USER" "$KNOWN_HOSTS"
        echo "✓ Host key added"
    fi

    echo ""
    echo "Public SSH key as QR code:"
    cat "${SSH_KEY_PATH}.pub" | qrencode -t ANSIUTF8
    echo ""
    echo "Public key text:"
    cat "${SSH_KEY_PATH}.pub"
    echo ""
    echo "👉 Please add this SSH key to your ${REPO_HOST} account:"
    echo "Press ENTER to continue..."
    read dummy < /dev/tty

    echo ""
    echo "Cloning repository..."
    if [ -d "${DOTFILES_FOLDER_PATH}" ]; then
        echo "Directory ${DOTFILES_FOLDER_PATH} already exists. Skipping clone."
    else
        if [ -n "$SUDO_USER" ]; then
            sudo -u "${ACTUAL_USER}" git clone "${REPOSITORY}" "${DOTFILES_FOLDER_PATH}"
        else
            git clone "${REPOSITORY}" "${DOTFILES_FOLDER_PATH}"
        fi
        echo "✓ Repository cloned"
    fi

    echo ""
    echo "Configuring git safe directory..."
    sudo git config --system --add safe.directory "${DOTFILES_FOLDER_PATH}"

    cd "${DOTFILES_FOLDER_PATH}"

    read -p "Enter host [default: nixos]: " HOST < /dev/tty
    HOST=${HOST:-nixos}
    if [ ! -d "./hosts/$HOST" ]; then
        echo "❌ Host \"$HOST\" does not exist in your nixos configuration. Exiting."
        exit 1
    fi

    echo ""
    read -p "Do you want to generate a new hardware-configuration.nix? [yes/Y default] or use from repo [no/N]: " generate_hw < /dev/tty
    generate_hw=${generate_hw:-yes}
    if echo "$generate_hw" | grep -iqE "^(y|yes)$"; then
        echo ""
        echo "Checking /etc/nixos/configuration.nix..."
        if [ ! -f /etc/nixos/configuration.nix ]; then
            echo "⚠️  /etc/nixos/configuration.nix not found."
            echo "Generating default configuration..."
            sudo nixos-generate-config
            echo "✓ Default configuration generated."
        else
            echo "✓ /etc/nixos/configuration.nix exists."
        fi

        HW_FILE="/etc/nixos/hardware-configuration.nix"
        if [ -f "$HW_FILE" ]; then
            echo ""
            # Construct default target path
            default_target="./hosts/$HOST/hardware-configuration.nix"
            mkdir -p "$(dirname "$default_target")"

            read -p "Hardware configuration file exists. Enter target location to move it [default: $default_target]: " target_path < /dev/tty
            target_path=${target_path:-$default_target}

            echo "Moving hardware-configuration.nix to $target_path..."
            sudo cp -f "$HW_FILE" "$target_path"
            sudo chown "$ACTUAL_USER" "$target_path"
            sudo chmod 644 "$target_path"
            git add -f "$target_path"
            echo "✓ Hardware configuration moved and permissions set."
        else
            echo "⚠️  /etc/nixos/hardware-configuration.nix does not exist. Proceeding without moving."
        fi
    else
        echo "Using hardware-configuration.nix from repository. Skipping generation."
    fi

    echo ""
    echo "Running nixos-rebuild switch --flake ."
    if [ ! -f flake.nix ]; then
        echo "❌ Error: flake.nix not found in repository."
        exit 1
    fi
    sudo nixos-rebuild switch --flake .#${HOST}
    echo ""
    echo "✅ Setup complete! Reboot your system."
'
