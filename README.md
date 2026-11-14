# Wayplank

A simple dock for Wayland — a Plank fork with native Wayland app tracking.

Plank is X11-only (libwnck/BAMF) and refuses to start outside X11. Wayplank
keeps Plank's renderer, themes, and behavior, but replaces window tracking
with a small GNOME Shell extension that publishes running apps over D-Bus
(`org.wayplank.Bridge`). No XWayland shims, no blind spots for native apps.

Requires the companion extension: **wayplank-bridge**
(`Neeraj-Parekh/wayplank-bridge`), which provides the app feed. Without it,
Wayplank runs with pinned launchers only.

## Install (Ubuntu 26.04)

```bash
sudo apt install ./wayplank_1.0.0_amd64.deb
```

Easiest (auto-detects your distro, installs the bridge, migrates config):

```bash
curl -fsSL https://raw.githubusercontent.com/Neeraj-Parekh/wayplank/main/install.sh | bash
```

Or build from source:

```bash
sudo apt install valac libgtk-3-dev libwnck-3-dev libbamf3-dev \
  libgee-0.8-dev libgnome-menu-3-dev libxfixes-dev libxi-dev \
  libdbusmenu-glib-dev libdbusmenu-gtk3-dev autoconf automake \
  libtool gettext autopoint gtk-doc-tools libxml2-utils
./autogen.sh && ./configure --prefix=/usr && make -j$(nproc)
```

## Run

```bash
wayplank
```

Position: top/bottom/left/right via Preferences (Ctrl+Right-click the dock)
or `dconf` under `/net/launchpad/wayplank/`. Coming from Plank? Copy your dock over:

```bash
cp -r ~/.config/plank/dock1 ~/.config/wayplank/
dconf dump /net/launchpad/plank/docks/dock1/ | dconf load /net/launchpad/wayplank/docks/dock1/
```

Hide behaviors: none / intelligent / auto / dodge-maximized. On Wayland,
intelligent hide uses maximized/fullscreen state from the bridge, and a
pointer poll reveals the dock at screen edges (pointer barriers are X11-only).

## Nyx docklet

The **Nyx** docklet puts [Nyx Continuity](https://github.com/Neeraj-Parekh/nyx-continuity)
in the dock: your phone with its battery and connection in the tooltip, a
dot while it is connected and a glow while the cursor is on the phone (the
crossover), files dropped on it sent to the phone, a click for the Nyx Hub,
and Nyx's actions in its menu (App Space, Recent Apps, Tab Mode, mirroring,
second display, clipboard, phone music, camera, dock settings).

It reads `$XDG_RUNTIME_DIR/nyx-status.ini`, which Nyx rewrites when any of
that changes, and runs actions with the command that file names - no polling
and nothing to put on PATH. Add it from Preferences > Docklets, or set Nyx's
*Show the dock in* to **Wayplank** (Hub > Settings > Dock): Nyx then adds the
docklet itself and hides its own dock window while Wayplank runs (it keeps
running the crossover, transfers and App Space, and shows its window again
if Wayplank goes away).

## Origin & license

Fork of [Plank](https://github.com/ricotz/plank) (Rico Tzschichholz and
contributors). GPL-3.0-or-later, same as upstream — see COPYING. A `git log`
against upstream is preserved in history.
