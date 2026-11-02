# Maintainer: grigio <grigio.org>
#
# Package for Umbralia: a minimal umbriel + Noctalia Wayland desktop. It
# installs the launcher, the XDG session entry, the systemd user units, the
# portal configuration and the optional greeter helper from
# files/ in this repo. Nothing is downloaded — the repo is the source tree, so
# $startdir is used in package() and there is no source array.
#
# The package does NOT edit /etc/greetd and does NOT make Umbralia the default
# session; `sudo umbralia-session-default` does that explicitly.
#
#   makepkg -f       # -> umbralia-session-<pkgver>-<pkgrel>-any.pkg.tar.zst
#   makepkg -fi      # ... and install it
#
# pkgver comes from the nearest v* tag and pkgrel from the number of commits
# that touched packaging files (not docs), so a local build matches the
# CI-built package. Both can be overridden, as .github/workflows/arch-package.yml does:
#
#   SESSION_VERSION=1.0.0 SESSION_PKGREL=1 makepkg -f

pkgname=umbralia-session
pkgver=${SESSION_VERSION:-$(git -C "${startdir:-$PWD}" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}
pkgver=${pkgver:-1.0.0}
# pkgrel: count commits touching packaging files only (exclude docs)
_packaging_files="PKGBUILD umbralia-session.install files scripts/set-default-greetd.sh scripts/install.sh"
_pkgrel=$(git -C "${startdir:-$PWD}" rev-list --count HEAD -- $_packaging_files 2>/dev/null || true)
pkgrel=${SESSION_PKGREL:-${_pkgrel:-1}}
(( pkgrel >= 1 )) || pkgrel=1

pkgdesc='Umbralia: minimal umbriel desktop with Noctalia'
arch=(any)
url='https://github.com/grigio/umbralia-session'
license=(MIT)
# umbriel is the compositor. xdg-desktop-portal-umbriel provides all portal
# backends for umbriel (screencast, screenshot, file chooser, etc.). polkit
# ships polkit-agent-helper-1 (Noctalia's built-in polkit agent); gnome-keyring
# provides the Secret portal; wireplumber is the PipeWire session manager and
# ships wpctl for the volume keys.
depends=(
  umbriel
  noctalia
  xdg-desktop-portal-umbriel
  polkit
  gnome-keyring
  wireplumber
)
optdepends=(
  'kanshi: dynamic display profiles'
  'brightnessctl: brightness keys'
  'playerctl: media keys'
  'polkit-gnome: fallback polkit agent when the Noctalia agent is disabled'
  'xorg-xwayland: run X11 applications'
  'gvfs: trash, recent files and volume monitoring in file choosers'
)
install=umbralia-session.install
source=()
sha256sums=()

check() {
  # Run shellcheck on all shell scripts
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$startdir/files/usr/bin/umbralia-session"
    shellcheck "$startdir/scripts/set-default-greetd.sh"
    shellcheck "$startdir/scripts/install.sh"
  else
    echo "shellcheck not found, skipping shell lint" >&2
  fi

  # Validate desktop file
  if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$startdir/files/usr/share/wayland-sessions/umbralia.desktop"
  else
    echo "desktop-file-validate not found, skipping desktop validation" >&2
  fi

  # Validate portal config (basic syntax)
  if command -v taplo >/dev/null 2>&1; then
    taplo lint "$startdir/files/usr/share/xdg-desktop-portal/umbralia-portals.conf" 2>/dev/null || true
  fi
}

package() {
  # The repo layout mirrors /, and git preserves the executable bit on the
  # scripts. Copying the tree as-is means a file added under files/ cannot be
  # forgotten here.
  cp -a "$startdir/files/." "$pkgdir/"

  # A local `python -m py_compile` (or the CI lint job) must not leak
  # __pycache__ into the package.
  find "$pkgdir" -type d -name __pycache__ -prune -exec rm -rf -- {} +

  # The package installs the helper under a name that makes sense once it is
  # on $PATH for an admin.
  install -Dm755 "$startdir/scripts/set-default-greetd.sh" \
    "$pkgdir/usr/bin/umbralia-session-default"

  install -Dm644 "$startdir/README.md" "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -Dm644 "$startdir/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}