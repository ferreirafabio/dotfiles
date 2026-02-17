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

`backup.sh` creates a password-protected zip of sensitive files (SSH keys, credentials) and stores it in `~/Dropbox/7_Backups/`. It runs weekly via launchd (Sundays at noon).

### One-Time Keychain Setup

The backup password is stored in macOS Keychain. Set it up once:

```bash
security add-generic-password -a "fabioferreira" -s "dotfiles-backup" -w
# Enter your password when prompted
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

```bash
cd /tmp
unzip ~/Dropbox/7_Backups/secrets_backup_LATEST.zip
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
backup.sh  — encrypted backup script
install.sh — deploy dotfiles to home (with diff preview)
save.sh    — copy home configs into repo
```

## Notes

- `backup.sh` uses macOS `zip -P` (ZipCrypto). Adequate for personal Dropbox backup. Upgrade to `7z` (AES-256) if stronger encryption is needed.
- The Keychain lookup requires a login session — backup will fail silently if the user is logged out.
- `claude/settings.json` has the ntfy.sh topic URL redacted. After `install.sh`, update it manually or re-run `save.sh` to overwrite.
