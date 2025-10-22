#!/bin/sh
set -e

REPOSITORY="${1:-git@github.com:sskeptix/NixConfig2.git}"
DOTFILES_FOLDER_RELATIVE_PATH="${2:-.dotfiles}"

echo "Checking sudo privileges..."
if ! sudo -v; then
    echo "Error: Current user does not have sudo privileges"
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
REPOSITORY="git@github.com:sskeptix/NixConfig2.git"
DOTFILES_FOLDER_PATH="${ACTUAL_HOME}/${DOTFILES_FOLDER_RELATIVE_PATH}"
echo "User: ${ACTUAL_USER}"
echo "Home: ${ACTUAL_HOME}"
echo "Repository: ${REPOSITORY}"
echo "Dotfiles path: ${DOTFILES_FOLDER_PATH}"

echo ""
echo "Entering nix-shell with git and qrencode..."
nix-shell -p git qrencode --run '
    set -e

    ACTUAL_USER="'"${ACTUAL_USER}"'"
    ACTUAL_HOME="'"${ACTUAL_HOME}"'"
    DOTFILES_FOLDER_PATH="'"${DOTFILES_FOLDER_PATH}"'"
    REPOSITORY="'"${REPOSITORY}"'"

    SSH_KEY_PATH="${ACTUAL_HOME}/.ssh/id_ed25519"
    if [ ! -d "${ACTUAL_HOME}/.ssh" ]; then
        mkdir -p "${ACTUAL_HOME}/.ssh"
        chmod 700 "${ACTUAL_HOME}/.ssh"
        if [ -n "$SUDO_USER" ]; then
            chown "${ACTUAL_USER}:${ACTUAL_USER}" "${ACTUAL_HOME}/.ssh"
        fi
    fi

    if [ -f "${SSH_KEY_PATH}" ]; then
        echo ""
        echo "SSH key already exists at ${SSH_KEY_PATH}"
        echo "Using existing key..."
    else
        echo ""
        echo "Generating new SSH key..."
        ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -N "" -C "nixos-setup"
        if [ -n "$SUDO_USER" ]; then
            chown "${ACTUAL_USER}:${ACTUAL_USER}" "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
        fi
        chmod 600 "${SSH_KEY_PATH}"
        chmod 644 "${SSH_KEY_PATH}.pub"
        echo "✓ SSH key generated"
    fi

    echo ""
    echo "Public SSH key as QR code:"
    echo ""
    cat "${SSH_KEY_PATH}.pub" | qrencode -t ANSIUTF8
    echo ""
    echo "Public key text:"
    cat "${SSH_KEY_PATH}.pub"
    echo ""
    echo "Please add this SSH key to your GitHub account."
    echo "Press ENTER to continue..."
    read dummy < /dev/tty

    REPO_HOST=$(echo "${REPOSITORY}" | sed "s/.*@\([^:]*\).*/\1/")
    if grep -q "${REPO_HOST}" "${ACTUAL_HOME}/.ssh/known_hosts" 2>/dev/null; then
        echo "✓ ${REPO_HOST} already in known hosts"
    else
        echo "Adding ${REPO_HOST} to known hosts..."
        ssh-keyscan -t ed25519 "${REPO_HOST}" >> "${ACTUAL_HOME}/.ssh/known_hosts"
        chmod 644 "${ACTUAL_HOME}/.ssh/known_hosts"
        if [ -n "$SUDO_USER" ]; then
            chown "${ACTUAL_USER}:${ACTUAL_USER}" "${ACTUAL_HOME}/.ssh/known_hosts"
        fi
        echo "✓ ${REPO_HOST} host key added"
    fi

    echo ""
    echo "Cloning repository..."
    if [ -d "${DOTFILES_FOLDER_PATH}" ]; then
        echo "Directory ${DOTFILES_FOLDER_PATH} already exists. Skipping clone."
    else
        # Run git clone as the actual user
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

    echo ""
    echo "Running nixos-rebuild..."
    cd "${DOTFILES_FOLDER_PATH}"
    sudo nixos-rebuild switch --flake .
    echo ""
    echo "✓ Setup complete!"
'
