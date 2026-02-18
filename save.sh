#!/usr/bin/env bash
# save.sh — Copy home configs into the dotfiles repo
set -euo pipefail

DOTFILES="$HOME/dotfiles"

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
    "claude/statusline.sh:$HOME/.claude/statusline.sh"
)

echo "==> Saving dotfiles to repo..."

for entry in "${MAPPING[@]}"; do
    repo_path="${entry%%:*}"
    home_path="${entry##*:}"

    if [ -f "$home_path" ]; then
        mkdir -p "$DOTFILES/$(dirname "$repo_path")"
        cp "$home_path" "$DOTFILES/$repo_path"
        echo "  Copied $home_path -> $repo_path"
    else
        echo "  Skipped $home_path (not found)"
    fi
done

# Sanitize claude/settings.json — redact ntfy.sh topic URL
if [ -f "$DOTFILES/claude/settings.json" ]; then
    sed -i '' 's|ntfy\.sh/[a-zA-Z0-9_-]*|ntfy.sh/YOUR_TOPIC_HERE|g' "$DOTFILES/claude/settings.json"
    echo "  Sanitized ntfy.sh topic in claude/settings.json"
fi

# Auto-generate Brewfile
echo "==> Generating Brewfile..."
if command -v brew &>/dev/null; then
    brew bundle dump --force --file="$DOTFILES/Brewfile"
    echo "  Brewfile written"
else
    echo "  brew not found, skipping Brewfile"
fi

echo "==> Done. Review changes with: cd ~/dotfiles && git diff"
