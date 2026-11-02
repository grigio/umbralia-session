#!/usr/bin/env bash
# Install the Umbralia session from a checkout: copies files/ onto /, so the
# repo layout is the install layout. This does NOT make Umbralia the greeter
# default and does NOT edit /etc/greetd.
#
#   ./scripts/install.sh             # session files only
#   ./scripts/install.sh --default   # ... and preselect it in gtkgreet
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "run this as your user, not root: it uses sudo for /usr and must" >&2
    echo "reload the current user's systemd manager." >&2
    exit 1
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src="$root/files"

case ${1:-} in
    ''|--default) ;;
    -h|--help)
        sed -n '2,6p' "$0"
        exit 0
        ;;
    *)
        echo "usage: $0 [--default]" >&2
        exit 1
        ;;
esac

# If the files are already package-managed, copying over them only makes
# pacman's file list lie. Rebuild the package instead.
if pacman -Qq umbralia-session >/dev/null 2>&1; then
    echo "umbralia-session is installed as a package; pacman owns these" >&2
    echo "files. Bump pkgver/pkgrel in PKGBUILD and run 'makepkg -fi' instead." >&2
    exit 1
fi

# The session starts these directly, so a missing one is a broken install,
# not a warning.
missing=0
for bin in /usr/bin/umbriel /usr/bin/noctalia; do
    if [[ ! -x $bin ]]; then
        echo "error: $bin is missing or not executable" >&2
        missing=1
    fi
done
if (( missing )); then
    exit 1
fi

# The package does not install an autostart file. A personal one may still
# start the same daemons twice (Noctalia, portals).
if [[ -f $HOME/.config/umbriel/autostart ]] &&
    grep -v '^[[:space:]]*#' "$HOME/.config/umbriel/autostart" 2>/dev/null |
        grep -Eq 'noctalia|xdg-desktop-portal|umbriel-session\.target'; then
    echo "warning: ~/.config/umbriel/autostart starts services this session already" >&2
    echo "         manages. Remove those lines; umbralia-session.target starts" >&2
    echo "         them. If you keep them, guard just those lines with" >&2
    echo "         UMBRALIA_SESSION." >&2
fi

# Old personal units run in every session and would duplicate the package's
# units.
if systemctl --user is-enabled --quiet noctalia-umbriel-sync.path 2>/dev/null; then
    echo "warning: personal noctalia-umbriel-sync.path is enabled; disable it" >&2
    echo "         systemctl --user disable --now noctalia-umbriel-sync.path" >&2
fi
if systemctl --user is-enabled --quiet umbriel-4finger-gestures.service 2>/dev/null; then
    echo "warning: personal umbriel-4finger-gestures.service is enabled; disable" >&2
    echo "         it: systemctl --user disable --now umbriel-4finger-gestures.service" >&2
fi

# umbriel reads this file itself and overrides the launcher's environment.
if [[ -f $HOME/.config/umbriel/environment ]] &&
    grep -qE '^[[:space:]]*(export[[:space:]]+)?XDG_CURRENT_DESKTOP[[:space:]]*=' \
        "$HOME/.config/umbriel/environment"; then
    echo "warning: ~/.config/umbriel/environment sets XDG_CURRENT_DESKTOP." >&2
    echo "         Remove that line (Umbralia exports umbralia:wlroots), or set" >&2
    echo "         it to umbralia:wlroots." >&2
fi

while IFS= read -r -d '' f; do
    rel=${f#"$src"/}
    perm=644
    case $rel in */bin/*) perm=755 ;; esac
    printf 'install -m%s %s\n' "$perm" "/$rel"
    sudo install -D -o root -g root -m "$perm" "$f" "/$rel"
done < <(find "$src" -type f -print0 | sort -z)

# The package installs the same helper and docs; keep the source install in
# sync so "sudo umbralia-session-default" works after the checkout is gone.
sudo install -D -o root -g root -m 755 "$root/scripts/set-default-greetd.sh" \
    /usr/bin/umbralia-session-default
sudo install -D -o root -g root -m 644 "$root/README.md" \
    /usr/share/doc/umbralia-session/README.md
sudo install -D -o root -g root -m 644 "$root/LICENSE" \
    /usr/share/licenses/umbralia-session/LICENSE

if systemctl --user daemon-reload; then
    echo "reloaded the systemd user manager"
else
    echo "warning: could not reload the systemd user manager" >&2
fi
echo
echo "Umbralia is installed but was NOT made the greeter default."
echo "Greeters that read /usr/share/wayland-sessions list it already; gtkgreet"
echo "users can run: sudo umbralia-session-default --list"
echo "That makes it selectable without changing the default."
echo "To make it the default: sudo umbralia-session-default"

if [[ ${1:-} == --default ]]; then
    sudo /usr/bin/umbralia-session-default
fi