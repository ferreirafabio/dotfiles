# dotfiles

Personal dotfiles and automated encrypted backup for macOS.

## Quick Start

```bash
# Clone
git clone https://github.com/ferreirafabio/dotfiles.git ~/dotfiles

# Install dotfiles to home directory (shows diff preview first)
cd ~/dotfiles && ./install.sh
```

## Updating Dotfiles

```bash
# Save current home configs into the repo
cd ~/dotfiles && ./save.sh

# Review, commit, push
git diff
git add -A && git commit -m "Update dotfiles" && git push
```

## Encrypted Backup

`backup.sh` creates a password-protected zip of sensitive files (SSH keys, credentials) and uploads it to Dropbox via the API. It runs weekly via launchd (Sundays at noon). Old backups are rotated automatically (keeps last 6 weeks).

### One-Time Setup

#### 1. Zip password (macOS Keychain)

```bash
security add-generic-password -a "$USER" -s "dotfiles-backup" -w
# Enter your password when prompted
```

#### 2. Dropbox API credentials

1. Go to https://www.dropbox.com/developers/apps and create an app
   - Choose **Scoped access** and **Full Dropbox**
2. In the app's **Permissions** tab, enable `files.content.write` and `files.content.read`, then click Submit
3. Go back to **Settings** and note the **App key** and **App secret**
4. Get an authorization code — open this URL in your browser:
   ```
   https://www.dropbox.com/oauth2/authorize?client_id=YOUR_APP_KEY&response_type=code&token_access_type=offline
   ```
5. Exchange the code for a refresh token:
   ```bash
   curl -s -X POST https://api.dropboxapi.com/oauth2/token \
     -d code=AUTH_CODE \
     -d grant_type=authorization_code \
     -d client_id=YOUR_APP_KEY \
     -d client_secret=YOUR_APP_SECRET
   ```
6. Create `~/dotfiles/.env` (gitignored) with all three values:
   ```
   DROPBOX_APP_KEY=your_app_key
   DROPBOX_APP_SECRET=your_app_secret
   DROPBOX_REFRESH_TOKEN=your_refresh_token
   ```

### Manual Backup

```bash
~/dotfiles/backup.sh
```

### What Gets Backed Up

- `~/.ssh/` (SSH keys and config)
- `~/.netrc` (machine credentials)
- `~/.pypirc` (PyPI credentials)
- `~/.claude.json` (Claude auth tokens)
- `~/.config/github-copilot/hosts.json`
- `~/.config/dbxcli/auth.json`

### Restoring from Backup

Download the latest `secrets_backup_*.zip` from Dropbox, then:

```bash
cd /tmp
unzip secrets_backup_*.zip
# Copy files back to $HOME, fix SSH permissions:
cp -a .ssh/ ~/.ssh/
chmod 700 ~/.ssh && chmod 600 ~/.ssh/id_*
```

## Repo Structure

```
shell/     — zshrc, p10k.zsh, bash_profile, bashrc
git/       — gitconfig, gitignore_global
editor/    — vimrc
claude/    — settings.json (ntfy.sh topic redacted)
Brewfile   — auto-generated from brew
.env       — Dropbox API credentials (gitignored)
backup.sh  — encrypted backup via Dropbox API
install.sh — deploy dotfiles to home (with diff preview)
save.sh    — copy home configs into repo
```

## Notes

- `backup.sh` uses macOS `zip -P` (ZipCrypto). Adequate for personal Dropbox backup. Upgrade to `7z` (AES-256) if stronger encryption is needed.
- The Keychain lookup requires a login session — backup will fail silently if the user is logged out.
- `claude/settings.json` has the ntfy.sh topic URL redacted. After `install.sh`, update it manually or re-run `save.sh` to overwrite.
