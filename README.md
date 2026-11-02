# Umbralia

A minimal **umbriel + Noctalia** Wayland session for Arch Linux. It is the
umbriel port of [Cosmalia](https://github.com/grigio/cosmalia-session): the
compositor is [umbriel](https://umbriel.github.io/), the shell is
[Noctalia](https://github.com/noctalia-dev/noctalia), and the session starts
everything through systemd user units instead of a umbriel autostart file.

![Umbralia: umbriel + Noctalia](umbralia-session.png)

The package installs:

- `/usr/bin/umbralia-session` — the session launcher;
- `/usr/share/wayland-sessions/umbralia.desktop` — the XDG session entry;
- `/usr/lib/systemd/user/umbralia-session.target` and the
  `umbralia-noctalia.service` unit;
- `/usr/share/xdg-desktop-portal/umbralia-portals.conf` — explicit portal
  backend selection (umbriel for all portal interfaces, gnome-keyring for secrets);
- `/usr/bin/umbralia-session-default` — the optional gtkgreet helper.

The package **does not** edit `/etc/greetd`, **does not** install
`~/.config/umbriel/autostart`, and **does not** make itself the default session.
It can be installed alongside `cosmalia-session`.

## Requirements

Install the package (or use the source install below). The hard dependencies
are `umbriel`, `noctalia`, `xdg-desktop-portal-umbriel`, `polkit`, `gnome-keyring`
and `wireplumber`.

Useful optional packages:

| Package | Why |
| --- | --- |
| `kanshi` | dynamic display profiles |
| `brightnessctl` | brightness keys |
| `playerctl` | media keys |
| `polkit-gnome` | fallback polkit agent if Noctalia's is disabled |
| `xorg-xwayland` | X11 apps |
| `gvfs` | trash, recent files and volume monitoring in file choosers |

## Install

### Package

```sh
git clone https://github.com/grigio/umbralia-session
cd umbralia-session
makepkg -fi
```

Or install a release package:

```sh
sudo pacman -U umbralia-session-*.pkg.tar.zst
```

The package does not touch `/etc/greetd` or `~/.config/umbriel`.

### From a checkout without pacman

```sh
./scripts/install.sh             # session files only
./scripts/install.sh --default   # ... and make it the gtkgreet default
```

`scripts/install.sh` refuses to run if the package is already installed (so
pacman's file list stays correct).

## Start the session

Log out and pick **Umbralia** in your greeter. Greeters that read
`/usr/share/wayland-sessions` (GDM, SDDM, Noctalia Greeter) list it
automatically.

`gtkgreet` only lists `/etc/greetd/environments` plus its `-c` argument. Add
Umbralia to the dropdown without changing the default:

```sh
sudo umbralia-session-default --list
```

Make it the gtkgreet default (`-c`, or the first line of `environments` when
`gtkgreet` has no `-c`):

```sh
sudo umbralia-session-default
```

With Noctalia Greeter, pick **Umbralia** once, or set:

```toml
[session]
default = "Umbralia"
```

in `/var/lib/noctalia-greeter/greeter.toml`.

greetd reads its configuration once at startup; the change lands at the next
greetd start (a reboot, or `systemctl restart greetd` while logged out).

## How startup works

There is no `~/.config/umbriel/autostart` in this package. The launcher owns the
startup order:

1. Set `XDG_SESSION_TYPE=wayland`, `XDG_SESSION_DESKTOP=umbralia`,
   `DESKTOP_SESSION=umbralia` and `XDG_CURRENT_DESKTOP=umbralia:wlroots`.
2. Stop a stale `graphical-session.target` and the COSMIC portal from a
   previous session.
3. Start `/usr/bin/umbriel` and find the `wayland-N` socket it listens on.
4. Export `WAYLAND_DISPLAY` and `UMBRIEL_PID` to the systemd user manager and
   the D-Bus activation environment.
5. Restart `xdg-desktop-portal.service` and `xdg-desktop-portal-umbriel.service`
   so they see the new socket.
6. Start `umbralia-session.target`, which pulls in
   `umbralia-noctalia.service`.
7. On exit, stop the target, the umbriel portal and the graphical session.

`UMBRIEL_PID` matters: Noctalia uses it for compositor detection and logout, and
`umbriel --reconfigure` needs it. Noctalia is a systemd service, not a child of
umbriel, so the launcher publishes the variable explicitly.

## Migrating an existing umbriel setup

The package does not edit your personal umbriel configuration. If you already
have one, clean up these files and any personal units so the session's
units are the only owners of the services.

### `~/.config/umbriel/environment`

Remove `XDG_CURRENT_DESKTOP` (the launcher exports
`umbralia:wlroots`), or set it to the same value:

```sh
XDG_CURRENT_DESKTOP=umbralia:wlroots
```

umbriel reads this file itself and overrides the launcher's environment. A stale
`XDG_CURRENT_DESKTOP=umbriel:wlroots` makes umbriel's children and the systemd
user manager disagree, which can make `xdg-desktop-portal` pick the wrong
backend. The launcher logs a warning when it sees the mismatch.

### `~/.config/umbriel/autostart`

Remove lines that start any of these; `umbralia-session.target` starts them:

- `noctalia` / `noctalia --daemon`
- `xdg-desktop-portal`, `xdg-desktop-portal-wlr`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-umbriel`
- `umbriel-session.target`

Keep personal app launches if you want them. If you prefer to keep the file
mostly intact, guard only the managed lines:

```sh
if [ -z "${UMBRALIA_SESSION:-}" ]; then
  noctalia --daemon &
  ...
fi
```

The launcher sets `UMBRALIA_SESSION=1` for exactly this purpose. Do **not**
start Noctalia from the autostart under Umbralia: the systemd unit is what
gets `UMBRIEL_PID`, restart-on-crash and `PartOf=umbralia-session.target`.

### Old personal systemd units

Autostart is not the only place an old setup can start the same services. If
you moved Noctalia to personal units, disable those too: they are not namespaced.

```sh
systemctl --user daemon-reload
```

The package does not remove personal units.

## umbriel configuration

umbriel reads `~/.config/umbriel/config.toml` (TOML format; `rc.xml` is
legacy). The package installs a Umbralia-tuned default at
`/usr/share/umbralia-session/umbralia-config.toml`. On first login, the
launcher copies it to `~/.config/umbriel/config.toml` **only if that file
does not already exist**, so your existing config is never overwritten.

To customize, edit `~/.config/umbriel/config.toml` and reload:

```sh
umbriel --reconfigure
```

The default includes keybinds for Mod+Return (kitty), Mod (launcher),
media/volume/brightness keys via Noctalia, and window rules for Noctalia
panels. See the installed config for the full reference.

Keybinds are up to your configuration. Common bindings include:

| Key | Action |
| --- | --- |
| `W-Return` | terminal |
| `W-Space` | Noctalia launcher |
| `W-S-w` | Noctalia session panel |
| `W-Escape`, `XF86PowerOff` | lock and suspend |
| `W-w` | close window |
| `C-W-Left` / `C-W-Right` | previous / next desktop |
| `W-1` … `W-4` | go to desktop |
| `W-A-r` | reconfigure umbriel |
| `XF86Audio*` | volume / mute / play-pause |
| `XF86MonBrightness*` | brightness (needs brightnessctl) |

Right-clicking the desktop opens the root menu from `menu.xml`.

## Portals

`XDG_CURRENT_DESKTOP=umbralia:wlroots` makes xdg-desktop-portal read
`/usr/share/xdg-desktop-portal/umbralia-portals.conf`. It selects:

- `umbriel` for all portal interfaces (`Screenshot`, `ScreenCast`, `FileChooser`,
  `Settings`, `Access`, `Print`, `Notification`, `AppChooser`, etc.);
- `gnome-keyring` for `Secret`;
- `Inhibit=none`, matching umbriel's own portal configuration (the gtk
  inhibitor expects a GNOME session manager).

The explicit list avoids `default=wlr;*` falling through to the COSMIC portal
for `FileChooser`/`Settings` on systems where `xdg-desktop-portal-cosmic` is
installed. It also avoids routing `Settings`/`Clipboard` to the GNOME portal,
which needs Mutter.

The launcher restarts the portal after the compositor socket exists.
If you have a personal `~/.config/xdg-desktop-portal/portals.conf` or a
`~/.config/xdg-desktop-portal/umbriel-portals.conf` that routes interfaces to
`cosmic` or `gnome`, remove it or make it match the selection above.

## Coexistence with Cosmalia

`cosmalia-session` and `umbralia-session` can be installed together. The
launcher, session entry, units, portal config and helper are all namespaced
with `umbralia-`. The package does not add a `conflicts`/`replaces` entry and
does not remove Cosmalia from `/etc/greetd/environments`.

`umbralia-session-default --list` only appends the Umbralia entry; it leaves
the Cosmalia entry and the current default alone. `umbralia-session-default`
changes the gtkgreet default but still does not remove other sessions.

## Troubleshooting

### umbriel does not start / black screen

```sh
cat "$XDG_RUNTIME_DIR/umbralia-session.log"
journalctl --user -b
```

Check that `/usr/bin/umbriel` and `/usr/bin/noctalia` exist and are executable.
The launcher is the session leader: do not run it from a terminal inside an
existing graphical session, because it stops `graphical-session.target` as
part of startup. For a nested test, use a separate user manager or VM and set
`UMBRALIA_NESTED=1` to keep `DISPLAY`/`WAYLAND_DISPLAY`; without it the
launcher clears them so umbriel takes the DRM/KMS backend.

### Noctalia is not running

```sh
systemctl --user status umbralia-noctalia.service
journalctl --user -u umbralia-noctalia.service -b
```

The target pulls the service in; do not enable `umbralia-noctalia.service`
separately. If you removed the package's units, `systemctl --user
daemon-reload` and log in again.

### Logout or reconfigure does nothing

```sh
systemctl --user show-environment | grep -E 'UMBRIEL_PID|WAYLAND_DISPLAY'
```

`UMBRIEL_PID` must point at the running umbriel. If it is missing, Noctalia was
probably started from `~/.config/umbriel/autostart` instead of the systemd unit.
Remove that line. `W-A-r` runs `umbriel --reconfigure` from a umbriel child, so it
has the variable.

### Screenshots or screen sharing fail

```sh
systemctl --user status xdg-desktop-portal.service xdg-desktop-portal-umbriel.service
journalctl --user -u xdg-desktop-portal -u xdg-desktop-portal-umbriel -b
busctl --user introspect org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop
```

Check `XDG_CURRENT_DESKTOP` is `umbralia:wlroots`, and that
`/usr/share/xdg-desktop-portal/umbralia-portals.conf` exists. Remove personal
portal overrides that select `cosmic` or `gnome`.

## Uninstall

```sh
sudo pacman -R umbralia-session
```

The package does not change `/etc/greetd`; if Umbralia is the greeter
default, point the greeter at another session first. Your personal
`~/.config/umbriel` files are left in place.

## License

MIT.# Test
