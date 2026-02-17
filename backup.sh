#!/usr/bin/env bash
# backup.sh — Encrypted backup of sensitive files to Dropbox
set -euo pipefail

BACKUP_DIR="$HOME/Dropbox/7_Backups"
LOG_FILE="$BACKUP_DIR/backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ZIP_NAME="secrets_backup_${TIMESTAMP}.zip"
ZIP_PATH="$BACKUP_DIR/$ZIP_NAME"
STAGING_DIR=$(mktemp -d)
KEEP_COUNT=4

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

log "Starting backup..."

# Retrieve zip password from macOS Keychain
PASSWORD=$(security find-generic-password -a "fabioferreira" -s "dotfiles-backup" -w 2>/dev/null) || {
    log "ERROR: Could not retrieve password from Keychain."
    log "Run: security add-generic-password -a fabioferreira -s dotfiles-backup -w"
    exit 1
}

if [ -z "$PASSWORD" ]; then
    log "ERROR: Keychain password is empty."
    log "Delete and re-add: security delete-generic-password -a fabioferreira -s dotfiles-backup"
    log "Then: security add-generic-password -a fabioferreira -s dotfiles-backup -w"
    exit 1
fi

# Files and directories to back up
declare -a BACKUP_ITEMS=(
    "$HOME/.ssh"
    "$HOME/.netrc"
    "$HOME/.pypirc"
    "$HOME/.claude.json"
    "$HOME/.config/github-copilot/hosts.json"
    "$HOME/.config/dbxcli/auth.json"
)

# Stage files
for item in "${BACKUP_ITEMS[@]}"; do
    if [ -e "$item" ]; then
        # Preserve directory structure relative to $HOME
        rel_path="${item#$HOME/}"
        dest="$STAGING_DIR/$rel_path"
        mkdir -p "$(dirname "$dest")"
        if [ -d "$item" ]; then
            mkdir -p "$dest"
            # Copy everything except sockets
            find "$item" -not -type s -print0 | while IFS= read -r -d '' src_file; do
                rel="${src_file#$item}"
                if [ -d "$src_file" ]; then
                    mkdir -p "$dest$rel"
                else
                    cp -p "$src_file" "$dest$rel"
                fi
            done
        else
            cp -a "$item" "$dest"
        fi
        log "  Staged: $rel_path"
    else
        log "  Skipped (not found): $item"
    fi
done

# Create password-protected zip
mkdir -p "$BACKUP_DIR"
cd "$STAGING_DIR"
zip -r -P "$PASSWORD" "$ZIP_PATH" . >/dev/null 2>&1
log "Created: $ZIP_NAME ($(du -h "$ZIP_PATH" | cut -f1))"

# Rotate old backups — keep only the most recent $KEEP_COUNT
old_backups=($(ls -1t "$BACKUP_DIR"/secrets_backup_*.zip 2>/dev/null))
if [ ${#old_backups[@]} -gt $KEEP_COUNT ]; then
    for ((i=KEEP_COUNT; i<${#old_backups[@]}; i++)); do
        rm -f "${old_backups[$i]}"
        log "  Rotated out: $(basename "${old_backups[$i]}")"
    done
fi

log "Backup complete. ${#old_backups[@]} backup(s) in $BACKUP_DIR (keeping last $KEEP_COUNT)."
