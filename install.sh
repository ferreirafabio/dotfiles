#!/usr/bin/env bash
# install.sh — Install dotfiles from repo to home directory
set -euo pipefail

DOTFILES="$HOME/dotfiles"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Mapping: repo_path -> home_path
declare -a MAPPING=(
    "shell/zshrc:$HOME/.zshrc"
    "shell/p10k.zsh:$HOME/.p10k.zsh"
    "shell/bash_profile:$HOME/.bash_profile"
    "shell/bashrc:$HOME/.bashrc"
    "shell/profile:$HOME/.profile"
    "git/gitconfig:$HOME/.gitconfig"
    "git/gitignore_global:$HOME/.config/git/ignore"
    "editor/vimrc:$HOME/.vimrc"
    "claude/settings.json:$HOME/.claude/settings.json"
    "claude/statusline.sh:$HOME/.claude/statusline.sh"
)

# ---- Diff preview ----
echo "==> Preview of changes:"
has_changes=false
for entry in "${MAPPING[@]}"; do
    repo_path="${entry%%:*}"
    home_path="${entry##*:}"
    src="$DOTFILES/$repo_path"

    [ -f "$src" ] || continue

    if [ -f "$home_path" ]; then
        if ! diff -q "$src" "$home_path" >/dev/null 2>&1; then
            echo ""
            echo "--- $home_path (current)"
            echo "+++ $src (repo)"
            diff -u "$home_path" "$src" || true
            has_changes=true
        fi
    else
        echo ""
        echo "NEW: $home_path (from $repo_path)"
        has_changes=true
    fi
done

if [ "$has_changes" = false ]; then
    echo "  All files are already up to date."
fi

# ---- Confirmation ----
echo ""
read -rp "Proceed with installation? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ---- Install files ----
echo ""
echo "==> Installing dotfiles..."
for entry in "${MAPPING[@]}"; do
    repo_path="${entry%%:*}"
    home_path="${entry##*:}"
    src="$DOTFILES/$repo_path"

    [ -f "$src" ] || continue

    # Backup existing file
    if [ -f "$home_path" ]; then
        cp "$home_path" "${home_path}.backup_${TIMESTAMP}"
        echo "  Backed up: $home_path -> ${home_path}.backup_${TIMESTAMP}"
    fi

    mkdir -p "$(dirname "$home_path")"
    cp "$src" "$home_path"
    echo "  Installed: $repo_path -> $home_path"
done

# ---- Optional: brew bundle ----
if [ -f "$DOTFILES/Brewfile" ]; then
    echo ""
    read -rp "Run 'brew bundle' from Brewfile? [y/N] " brew_confirm
    if [[ "$brew_confirm" =~ ^[Yy]$ ]]; then
        brew bundle --file="$DOTFILES/Brewfile"
    fi
fi

# ---- Install launchd plist (template: __HOME__ is substituted at install time) ----
PLIST_NAME="com.dotfiles.backup.plist"
PLIST_SRC="$DOTFILES/$PLIST_NAME"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

if [ -f "$PLIST_SRC" ]; then
    echo ""
    echo "==> Installing launchd agent..."
    mkdir -p "$HOME/Library/LaunchAgents"

    # Unload existing if loaded (under either old or new name, for upgrades from previous installs)
    launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
    launchctl bootout "gui/$(id -u)/com.fabioferreira.backup.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.fabioferreira.backup.plist"

    # Substitute __HOME__ placeholder with the actual home directory of the current user.
    sed "s|__HOME__|$HOME|g" "$PLIST_SRC" > "$PLIST_DST"
    launchctl load "$PLIST_DST"
    echo "  Loaded: $PLIST_NAME (paths bound to $HOME)"
fi

# ---- Create .profile.local stub if absent (gitignored, holds machine-local secrets) ----
if [ ! -f "$HOME/.profile.local" ]; then
    echo ""
    echo "==> Creating ~/.profile.local stub (for E2B_API_KEY and other per-machine secrets)..."
    cat > "$HOME/.profile.local" <<'EOF'
# Machine-local secrets and overrides. NOT in git, NOT in iCloud backup.
# Sourced by ~/.profile.
#
# export E2B_API_KEY=...
EOF
    chmod 600 "$HOME/.profile.local"
    echo "  Created (chmod 600). Edit it to add your secrets."
fi

echo ""
echo "==> Done! You may want to restart your shell or run: source ~/.zshrc"
