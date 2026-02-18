#!/usr/bin/env bash
# Claude Code statusLine — mirrors Powerlevel10k (p10k) prompt style
# Left side: dir | git branch | conda env
# Right side: user@host | model | context bar | 5h usage | 7d usage

input=$(cat)

# --- Data from Claude ---
cwd=$(echo "$input"      | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input"    | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# --- Helper: render a compact progress bar ---
make_bar() {
    local pct=$1 width=$2 fill_color=$3
    [ "$pct" -lt 0 ]   2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local bar="" i
    for (( i=0; i<filled; i++ )); do bar="${bar}▓"; done
    for (( i=0; i<empty;  i++ )); do bar="${bar}░"; done
    printf "${fill_color}${bar}\033[0m"
}

# --- Helper: pick color by percentage + base color ---
# Usage: pct_color <percent> <base_color_code>
# Escalates: base → yellow (50%) → red (80%)
pct_color() {
    local pct=$1 base=$2
    if [ "$pct" -ge 80 ] 2>/dev/null; then   printf "\033[0;31m"  # red
    elif [ "$pct" -ge 50 ] 2>/dev/null; then  printf "\033[0;33m"  # yellow
    else                                       printf "\033[0;${base}m"
    fi
}

# --- Directory (shorten home to ~) ---
short_dir="${cwd/#$HOME/\~}"

# --- Git branch ---
git_branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree --no-optional-locks 2>/dev/null | grep -q true; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    [ -n "$branch" ] && git_branch=" \033[0;33m($branch)\033[0m"
fi

# --- Conda environment ---
conda_env=""
if [ -n "$CONDA_DEFAULT_ENV" ] && [ "$CONDA_DEFAULT_ENV" != "base" ]; then
    conda_env=" \033[0;36m[$CONDA_DEFAULT_ENV]\033[0m"
fi

# --- Bar 1: Context window usage ---
ctx_bar=""
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
    pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo "$used_pct")
    bar_color=$(pct_color "$pct_int" "35")  # magenta
    bar=$(make_bar "$pct_int" 8 "$bar_color")
    ctx_bar=" ctx[${bar}]${pct_int}%%"
fi

# --- Bars 2 & 3: API usage limits (5h session + 7d weekly) ---
# Cached to avoid hitting the API on every statusline refresh
CACHE_FILE="/tmp/claude-usage-cache-$(id -u).json"
CACHE_TTL=120  # seconds

usage_5h="" usage_7d=""
need_refresh=true

if [ -f "$CACHE_FILE" ]; then
    if [[ "$(uname)" == "Darwin" ]]; then
        cache_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    else
        cache_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    fi
    cache_age=$(( $(date +%s) - cache_mtime ))
    if [ "$cache_age" -lt "$CACHE_TTL" ]; then
        need_refresh=false
    fi
fi

if $need_refresh; then
    token=""
    # macOS: credentials stored in Keychain
    if [[ "$(uname)" == "Darwin" ]]; then
        creds_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$creds_json" ]; then
            token=$(echo "$creds_json" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        fi
    fi
    # Linux: credentials in flat file
    if [ -z "$token" ]; then
        creds_file="$HOME/.claude/.credentials.json"
        if [ -f "$creds_file" ]; then
            token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null)
        fi
    fi
    if [ -n "$token" ]; then
        resp=$(curl -s --max-time 3 \
            -H "Authorization: Bearer $token" \
            -H "anthropic-beta: oauth-2025-04-20" \
            "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
        if echo "$resp" | jq -e '.five_hour' &>/dev/null; then
            echo "$resp" > "$CACHE_FILE"
        fi
    fi
fi

if [ -f "$CACHE_FILE" ]; then
    usage_5h=$(jq -r '.five_hour.utilization // empty' "$CACHE_FILE" 2>/dev/null)
    usage_7d=$(jq -r '.seven_day.utilization // empty' "$CACHE_FILE" 2>/dev/null)
fi

five_h_bar=""
if [ -n "$usage_5h" ] && [ "$usage_5h" != "null" ]; then
    pct_5h=$(printf "%.0f" "$usage_5h" 2>/dev/null || echo "$usage_5h")
    bar_color=$(pct_color "$pct_5h" "36")  # cyan
    bar=$(make_bar "$pct_5h" 8 "$bar_color")
    five_h_bar=" 5h[${bar}]${pct_5h}%%"
fi

seven_d_bar=""
if [ -n "$usage_7d" ] && [ "$usage_7d" != "null" ]; then
    pct_7d=$(printf "%.0f" "$usage_7d" 2>/dev/null || echo "$usage_7d")
    bar_color=$(pct_color "$pct_7d" "34")  # blue
    bar=$(make_bar "$pct_7d" 8 "$bar_color")
    seven_d_bar=" 7d[${bar}]${pct_7d}%%"
fi

# --- Assemble ---
left="\033[1;34m${short_dir}\033[0m${git_branch}${conda_env}"
right="\033[0;32m$(whoami)@$(hostname -s)\033[0m"
[ -n "$model" ] && right="${right} \033[0;37m${model}\033[0m"
right="${right}${ctx_bar}${five_h_bar}${seven_d_bar}"

printf "${left}  ${right}\n"
