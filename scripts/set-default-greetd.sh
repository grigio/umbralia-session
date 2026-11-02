#!/usr/bin/env bash
# Make umbralia-session the entry gtkgreet preselects, or with --list only add
# it to the dropdown while leaving the default alone. This is an explicit,
# opt-in action: the package itself never edits /etc/greetd.
#
# How the default is picked (gtkgreet src/config.c, config_update_command_selector):
#   - the command passed with -c is appended to the session combo *first*,
#   - every line of /etc/greetd/environments is appended after it,
#   - the combo is then set to index 0 (src/window.c).
# So -c is the default and the environments file only fills the dropdown.
# Without -c, gtkgreet uses the first line of environments as index 0, so this
# script prepends the session there.
#
# greetd reads its config once, at startup (greetd/src/main.rs), so the change
# lands at the next greetd start: a reboot, or `systemctl restart greetd` while
# you are logged out.
#
# The package installs this as /usr/bin/umbralia-session-default. The
# GREETD_CONFIG/GREETD_ENVIRONMENTS overrides exist for testing.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then SUDO=(); else SUDO=(sudo); fi

cmd=${UMBRALIA_SESSION:-/usr/bin/umbralia-session}
conf=${GREETD_CONFIG:-/etc/greetd/config.toml}
envs=${GREETD_ENVIRONMENTS:-/etc/greetd/environments}
stamp=$(date +%Y%m%d-%H%M%S)
tmp=""

usage() {
    cat <<'EOF'
usage: umbralia-session-default [--list]

  (no option)  make Umbralia the gtkgreet default and add it to the dropdown
  --list       only add Umbralia to /etc/greetd/environments; leave the
               default (-c, or the first environments line) unchanged
EOF
}

case ${1:-} in
    '') ;;
    --list) list_only=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 1
fi
list_only=${list_only:-0}

cleanup_tmp() {
    [[ -n $tmp ]] && rm -f -- "$tmp"
}
trap cleanup_tmp EXIT

new_tmp() {
    [[ -n $tmp ]] && rm -f -- "$tmp"
    tmp=$(mktemp)
}

# Keep the last 3 backups of a file instead of letting them accumulate.
prune_backups() {
    local path=$1 dir base
    dir=$(dirname -- "$path")
    base=$(basename -- "$path")
    "${SUDO[@]}" find "$dir" -maxdepth 1 -name "$base.bak.*" \
        -printf '%T@ %p\n' 2>/dev/null |
        sort -rn | tail -n +4 | cut -d' ' -f2- |
        xargs -r "${SUDO[@]}" rm -f --
}

backup_envs() {
    if [[ -f $envs ]]; then
        "${SUDO[@]}" cp -a -- "$envs" "$envs.bak.$stamp"
    fi
}

# Append at the end if missing. Returns 1 when it was already there.
ensure_in_envs() {
    if grep -qxF -- "$cmd" "$envs" 2>/dev/null; then
        return 1
    fi
    new_tmp
    if [[ -f $envs ]]; then
        cat -- "$envs" >"$tmp"
        if [[ -s $tmp ]] && [[ -n $(tail -c1 "$tmp") ]]; then
            printf '\n' >>"$tmp"
        fi
    fi
    printf '%s\n' "$cmd" >>"$tmp"
    "${SUDO[@]}" install -Dm644 -o root -g root "$tmp" "$envs"
    return 0
}

# Validate TOML syntax using taplo
validate_toml() {
    local file=$1
    if ! "${SUDO[@]}" taplo lint "$file" >/dev/null 2>&1; then
        echo "error: $file is not valid TOML after modification" >&2
        "${SUDO[@]}" taplo lint "$file" >&2
        return 1
    fi
}

# Get the current command value from greetd config using taplo
get_current_command() {
    "${SUDO[@]}" taplo get -f "$conf" default_session.command 2>/dev/null || true
}

[[ -x $cmd ]] || {
    echo "$cmd is missing, install the session first (./scripts/install.sh" >&2
    echo "or the umbralia-session package)" >&2
    exit 1
}

if (( list_only )); then
    backup_envs
    if ensure_in_envs; then
        action="added $cmd to $envs (default unchanged)"
    else
        action="already listed in $envs (default unchanged)"
    fi
    prune_backups "$envs"

    echo "$action"
    echo "dropdown entry   -> $(grep -cxF -- "$cmd" "$envs" 2>/dev/null || true) line(s) in $envs"
    echo
    echo "The default (-c or the first environments line) was not changed."
    echo "Effective at the next greetd start."
    exit 0
fi

[[ -f $conf ]] || { echo "$conf not found (greetd is not configured here?)" >&2; exit 1; }

# Check if greetd config uses gtkgreet
if ! grep -qE '^[[:space:]]*command[[:space:]]*=.*gtkgreet' "$conf"; then
    if grep -qE '^[[:space:]]*command[[:space:]]*=.*noctalia-greeter' "$conf"; then
        cat >&2 <<'EOF'
This greetd config uses Noctalia Greeter, which selects the session itself.
Pick "Umbralia" once in the greeter, or set:

  [session]
  default = "Umbralia"

in /var/lib/noctalia-greeter/greeter.toml.

To only add Umbralia to /etc/greetd/environments, run this again with --list.
EOF
    else
        echo "$conf does not run gtkgreet; set the session default in your greeter." >&2
        echo "(Use --list to only edit /etc/greetd/environments.)" >&2
    fi
    exit 1
fi

"${SUDO[@]}" cp -a -- "$conf" "$conf.bak.$stamp"
backup_envs

# Check if config has -c flag in command (gtkgreet with explicit default)
current_cmd=$(get_current_command)
if [[ $current_cmd == *"-c"* ]]; then
    # Rewrite the -c argument in the command using taplo + jq
    # Extract the command, replace the -c value, write back
    new_tmp
    # Use jq to do the string replacement on the command field
    # Write jq filter to a temp file to avoid quoting issues
    jq_filter=$(mktemp)
    cat >"$jq_filter" <<'JQEOF'
.default_session.command |=
    (sub("-c\\s+\"[^\"]*\""; "-c \($cmd)") |
     sub("-c\\s+'[^']*'"; "-c \($cmd)") |
     sub("-c\\s+[^\s\"]+"; "-c \($cmd)") |
     sub("-c=\"[^\"]*\""; "-c \($cmd)") |
     sub("-c='[^']*'"; "-c \($cmd)") |
     sub("-c=[^\s\"]+"; "-c \($cmd)"))
JQEOF
    "${SUDO[@]}" taplo get -f "$conf" -o json 2>/dev/null | \
        jq --arg cmd "$cmd" --from-file "$jq_filter" >"$tmp" || {
        rm -f "$jq_filter"
        echo "error: failed to parse/modify $conf" >&2
        exit 1
    }
    rm -f "$jq_filter"
    "${SUDO[@]}" install -Dm644 -o root -g root "$tmp" "$conf"

    if ! validate_toml "$conf"; then
        echo "Restoring backup..." >&2
        "${SUDO[@]}" mv -f "$conf.bak.$stamp" "$conf"
        exit 1
    fi

    # Verify the change took effect
    new_cmd=$(get_current_command)
    if [[ $new_cmd != *"$cmd"* ]]; then
        echo "could not rewrite the -c argument in $conf; edit it by hand." >&2
        "${SUDO[@]}" mv -f "$conf.bak.$stamp" "$conf"
        exit 1
    fi
    action="rewrote -c in $conf"
else
    # gtkgreet without -c uses the first line of environments as the default.
    new_tmp
    {
        printf '%s\n' "$cmd"
        if [[ -f $envs ]]; then
            grep -vxF -- "$cmd" "$envs" || true
        fi
    } >"$tmp"
    "${SUDO[@]}" install -Dm644 -o root -g root "$tmp" "$envs"
    action="prepended $cmd to $envs (gtkgreet has no -c)"
fi

# Make sure the session is in the dropdown list too. The no -c branch above
# already did this; the -c branch needs it.
ensure_in_envs || true

prune_backups "$conf"
prune_backups "$envs"

echo "$action"
# Show the command line from config
"${SUDO[@]}" taplo get -f "$conf" default_session.command 2>/dev/null | sed 's/^/  /'
echo "dropdown entry   -> $(grep -cxF -- "$cmd" "$envs" 2>/dev/null || true) line(s) in $envs"
echo
echo "Effective at the next greetd start: reboot, or, once logged out,"
echo "  sudo systemctl restart greetd     # now it would end the running session"