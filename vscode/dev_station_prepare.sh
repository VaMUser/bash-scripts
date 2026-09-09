#!/usr/bin/env bash

# Prepare a Debian VM for VS Code Remote-SSH, Ansible development, git and tmux.
# Run as root:
#   bash dev_station_prepare_enhanced.sh

set -Eeuo pipefail

# ===== CONFIG =====
USERNAME="${USERNAME:-user}"
USER_HOME="/home/$USERNAME"
SSH_DROPIN="/etc/ssh/sshd_config.d/99-dev-station.conf"

export DEBIAN_FRONTEND=noninteractive

log() {
    echo
    echo "==== $* ===="
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: run this script as root" >&2
        exit 1
    fi
}

append_once() {
    local file="$1"
    local line="$2"
    touch "$file"
    grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

require_root

log "[1] Installing base packages"
apt update
apt install -y \
    sudo \
    openssh-server \
    ca-certificates \
    curl \
    locales \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    git \
    tmux \
    mc \
    nano \
    htop \
    ripgrep \
    fd-find \
    rsync \
    unzip \
    less \
    build-essential

log "[2] Configuring locale"
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen || true
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

log "[3] Creating or updating user: $USERNAME"
if id "$USERNAME" >/dev/null 2>&1; then
    echo "User $USERNAME already exists"
else
    adduser --disabled-password --gecos "" "$USERNAME"
fi
usermod -aG sudo "$USERNAME"

log "[4] Copying SSH authorized_keys from root, if present"
mkdir -p "$USER_HOME/.ssh"
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/authorized_keys"
else
    echo "WARNING: /root/.ssh/authorized_keys not found; add your public key to $USER_HOME/.ssh/authorized_keys manually"
fi
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
[ -f "$USER_HOME/.ssh/authorized_keys" ] && chmod 600 "$USER_HOME/.ssh/authorized_keys"

log "[5] Configuring sshd keepalive settings"
mkdir -p /etc/ssh/sshd_config.d
cat > "$SSH_DROPIN" <<'SSHD_EOF'
# Keep stale mobile-network SSH sessions from hanging forever.
ClientAliveInterval 60
ClientAliveCountMax 3

# Safer defaults for key-based access. Uncomment only after verifying key login works.
# PasswordAuthentication no
# PermitRootLogin prohibit-password
SSHD_EOF
sshd -t
systemctl enable --now ssh || systemctl enable --now sshd || true
systemctl reload ssh || systemctl reload sshd || true

log "[6] Configuring pipx PATH"
cat > /etc/profile.d/pipx-local-bin.sh <<'PROFILE_EOF'
# Make pipx-installed tools visible in login shells and VS Code Remote-SSH terminals.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
PROFILE_EOF
chmod 644 /etc/profile.d/pipx-local-bin.sh

append_once "$USER_HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'
append_once "$USER_HOME/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc" "$USER_HOME/.profile"

log "[7] Installing ansible-core and ansible-lint with pipx"
sudo -H -u "$USERNAME" bash -lc '
set -Eeuo pipefail
export PATH="$HOME/.local/bin:$PATH"
python3 -m pipx ensurepath || true
pipx install ansible-core || pipx upgrade ansible-core
pipx install --include-deps ansible-lint || pipx upgrade ansible-lint
# Extra Ansible package can be useful for collections and compatibility; keep it inside ansible-lint env.
pipx inject ansible-lint ansible yamllint || true
'

log "[8] Writing tmux config"
cat > "$USER_HOME/.tmux.conf" <<'TMUX_EOF'
set -g mouse on
set -g history-limit 50000
setw -g mode-keys vi
set -g status-interval 5
set -g renumber-windows on
set -g escape-time 10
TMUX_EOF
chown "$USERNAME:$USERNAME" "$USER_HOME/.tmux.conf"

log "[9] Adding useful shell aliases"
cat > "$USER_HOME/.bash_aliases" <<'ALIASES_EOF'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias tmw='tmux attach -t work || tmux new -s work'
ALIASES_EOF
chown "$USERNAME:$USERNAME" "$USER_HOME/.bash_aliases"
append_once "$USER_HOME/.bashrc" 'if [ -f ~/.bash_aliases ]; then . ~/.bash_aliases; fi'
chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"

log "[10] Creating VS Code workspace settings template"
mkdir -p "$USER_HOME/.config/vscode-remote-templates"
cat > "$USER_HOME/.config/vscode-remote-templates/settings.json" <<'VSCODE_EOF'
{
  "ansible.python.interpreterPath": "/usr/bin/python3",
  "ansible.validation.lint.enabled": true,
  "ansible.validation.lint.path": "/home/user/.local/bin/ansible-lint",
  "terminal.integrated.profiles.linux": {
    "tmux work": {
      "path": "/bin/bash",
      "args": ["-lc", "tmux attach -t work || tmux new -s work"]
    }
  },
  "terminal.integrated.defaultProfile.linux": "tmux work"
}
VSCODE_EOF
sed -i "s#/home/user/#$USER_HOME/#g" "$USER_HOME/.config/vscode-remote-templates/settings.json"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config"

log "[11] Final checks"
sudo -H -u "$USERNAME" bash -lc '
export PATH="$HOME/.local/bin:$PATH"
command -v git
command -v tmux
command -v ansible || true
command -v ansible-lint || true
ansible --version || true
ansible-lint --version || true
'

echo
echo "Done. Reconnect as: $USERNAME"
echo "Recommended local SSH target: ssh $USERNAME@<VM_IP>"
echo "Inside shell: tmw"
