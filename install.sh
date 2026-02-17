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
    "git/gitconfig:$HOME/.gitconfig"
    "git/gitignore_global:$HOME/.config/git/ignore"
    "editor/vimrc:$HOME/.vimrc"
    "claude/settings.json:$HOME/.claude/settings.json"
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

# ---- Install launchd plist ----
PLIST_NAME="com.fabioferreira.backup.plist"
PLIST_SRC="$DOTFILES/$PLIST_NAME"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

if [ -f "$PLIST_SRC" ]; then
    echo ""
    echo "==> Installing launchd agent..."
    mkdir -p "$HOME/Library/LaunchAgents"

    # Unload existing if loaded
    launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true

    cp "$PLIST_SRC" "$PLIST_DST"
    launchctl load "$PLIST_DST"
    echo "  Loaded: $PLIST_NAME"
fi

echo ""
echo "==> Done! You may want to restart your shell or run: source ~/.zshrc"
