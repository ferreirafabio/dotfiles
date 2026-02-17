#!/usr/bin/env bash
# backup.sh — Encrypted backup of sensitive files, uploaded to Dropbox via API
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$DOTFILES_DIR/.env"
DROPBOX_DEST="/7_Backups"
LOCAL_LOG_DIR="$HOME/Dropbox/7_Backups"
LOG_FILE="$LOCAL_LOG_DIR/backup.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ZIP_NAME="secrets_backup_${TIMESTAMP}.zip"
STAGING_DIR=$(mktemp -d)
ZIP_PATH="$STAGING_DIR/$ZIP_NAME"
KEEP_COUNT=6  # 6 weeks of weekly backups

mkdir -p "$LOCAL_LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

log "Starting backup..."

# Load Dropbox API credentials from .env
if [ ! -f "$ENV_FILE" ]; then
    log "ERROR: $ENV_FILE not found."
    exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

for var in DROPBOX_APP_KEY DROPBOX_APP_SECRET DROPBOX_REFRESH_TOKEN; do
    if [ -z "${!var:-}" ]; then
        log "ERROR: $var is not set in $ENV_FILE"
        exit 1
    fi
done

# Retrieve zip password from macOS Keychain
PASSWORD=$(security find-generic-password -a "fabioferreira" -s "dotfiles-backup" -w 2>/dev/null) || {
    log "ERROR: Could not retrieve password from Keychain."
    log "Run: security add-generic-password -a fabioferreira -s dotfiles-backup -w"
    exit 1
}

if [ -z "$PASSWORD" ]; then
    log "ERROR: Keychain password is empty."
    exit 1
fi

# Get a fresh Dropbox access token
log "Obtaining Dropbox access token..."
TOKEN_RESPONSE=$(curl -s -X POST https://api.dropboxapi.com/oauth2/token \
    -d "grant_type=refresh_token" \
    -d "refresh_token=$DROPBOX_REFRESH_TOKEN" \
    -d "client_id=$DROPBOX_APP_KEY" \
    -d "client_secret=$DROPBOX_APP_SECRET")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    log "ERROR: Failed to get Dropbox access token."
    log "Response: $TOKEN_RESPONSE"
    exit 1
fi
log "  Access token obtained."

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
        rel_path="${item#$HOME/}"
        dest="$STAGING_DIR/$rel_path"
        mkdir -p "$(dirname "$dest")"
        if [ -d "$item" ]; then
            mkdir -p "$dest"
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
cd "$STAGING_DIR"
zip -r -P "$PASSWORD" "$ZIP_PATH" . -x "$ZIP_NAME" >/dev/null 2>&1
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
log "Created: $ZIP_NAME ($ZIP_SIZE)"

# Upload to Dropbox via API
log "Uploading to Dropbox: $DROPBOX_DEST/$ZIP_NAME ..."
UPLOAD_RESPONSE=$(curl -s -X POST https://content.dropboxapi.com/2/files/upload \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Dropbox-API-Arg: {\"path\": \"$DROPBOX_DEST/$ZIP_NAME\", \"mode\": \"add\", \"autorename\": true, \"mute\": false}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$ZIP_PATH")

UPLOAD_ID=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

if [ -z "$UPLOAD_ID" ]; then
    log "ERROR: Upload failed."
    log "Response: $UPLOAD_RESPONSE"
    exit 1
fi
log "  Uploaded successfully (id: $UPLOAD_ID)"

# Rotate old backups on Dropbox — keep only the most recent $KEEP_COUNT
log "Checking for old backups to rotate..."
LIST_RESPONSE=$(curl -s -X POST https://api.dropboxapi.com/2/files/list_folder \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"path\": \"$DROPBOX_DEST\", \"limit\": 100}")

# Extract secrets_backup_*.zip entries sorted by name (descending = newest first)
OLD_BACKUPS=$(echo "$LIST_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
entries = [e['path_display'] for e in data.get('entries', [])
           if e.get('.tag') == 'file' and 'secrets_backup_' in e.get('name', '') and e['name'].endswith('.zip')]
entries.sort(reverse=True)
for e in entries:
    print(e)
" 2>/dev/null)

COUNT=0
while IFS= read -r path; do
    [ -z "$path" ] && continue
    COUNT=$((COUNT + 1))
    if [ $COUNT -gt $KEEP_COUNT ]; then
        curl -s -X POST https://api.dropboxapi.com/2/files/delete_v2 \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"path\": \"$path\"}" >/dev/null
        log "  Rotated out: $path"
    fi
done <<< "$OLD_BACKUPS"

log "Backup complete. Kept last $KEEP_COUNT in Dropbox:$DROPBOX_DEST"
