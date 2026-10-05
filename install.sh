#!/usr/bin/env bash
# Wayplank installer — detects your distro, installs the dock + bridge,
# migrates Plank config, and starts the service. Logs to
# /tmp/wayplank-install.log; console stays quiet unless something fails.
#
#   curl -fsSL https://raw.githubusercontent.com/Neeraj-Parekh/wayplank/main/install.sh | bash
#
set -u
LOG=/tmp/wayplank-install.log
: > "$LOG"
exec 3>&1 1>>"$LOG" 2>&1

say()  { echo "[wayplank] $*" >&3; echo "[wayplank] $*" >>"$LOG"; }
die()  { echo "[wayplank] ERROR: $*" >&3; echo "[wayplank] ERROR: $*" >>"$LOG"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
if [ "$(id -u)" -eq 0 ]; then SUDO="";
elif have sudo; then SUDO="sudo";
else die "need root (run as root or install sudo)"; fi

[ -f /etc/os-release ] || die "cannot detect distro (no /etc/os-release)"
# shellcheck disable=SC1091
. /etc/os-release
ID=${ID:-unknown}; VERSION_ID=${VERSION_ID:-}; LIKE=${ID_LIKE:-}
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
say "platform: $ID $VERSION_ID ($ARCH), log: $LOG"

is_debian_family() { case " $ID $LIKE " in *" debian "*|*" ubuntu "*) return 0;; *) return 1;; esac; }
is_fedora_family() { case " $ID $LIKE " in *" fedora "*|*" rhel "*|*" centos "*) return 0;; *) return 1;; esac; }
is_arch_family()   { case " $ID $LIKE " in *" arch "*) return 0;; *) return 1;; esac; }

latest_deb_url() {
  # Prefer an asset built for this exact distro release, else any amd64 .deb.
  python3 - "$ID$VERSION_ID" <<'PY' 2>/dev/null
import json, sys, urllib.request
want = sys.argv[1]
try:
    rel = json.load(urllib.request.urlopen(
        "https://api.github.com/Neeraj-Parekh/wayplank/releases/latest",
        timeout=30))
except Exception as e:
    print(f"ERR {e}", file=sys.stderr); sys.exit(1)
assets = [(a["name"], a["browser_download_url"])
          for a in rel.get("assets", []) if a["name"].endswith(".deb")]
if not assets:
    sys.exit(2)
for name, url in assets:
    if want in name and "amd64" in name:
        print(url); break
else:
    for name, url in assets:
        if "amd64" in name:
            print(url); break
PY
}

install_dock_deb() {
  local url deb
  url=$(latest_deb_url) || die "no .deb in latest GitHub release (log has details)"
  say "downloading $(basename "$url")"
  deb=/tmp/$(basename "$url")
  curl -fsSL -o "$deb" "$url" >>"$LOG" 2>&1 || die "download failed"
  say "installing dock (needs sudo)"
  $SUDO apt-get install -y "$deb" >>"$LOG" 2>&1 || die "apt install failed — see $LOG"
}

install_dock_source_debian() {
  say "building from source (needs sudo for build deps)"
  $SUDO apt-get update >>"$LOG" 2>&1
  $SUDO apt-get install -y git valac libgtk-3-dev libwnck-3-dev libbamf3-dev \
    libgee-0.8-dev libgnome-menu-3-dev libxfixes-dev libxi-dev \
    libdbusmenu-glib-dev libdbusmenu-gtk3-dev autoconf automake libtool \
    gettext autopoint gtk-doc-tools \
    libxml2-utils >>"$LOG" 2>&1 || die "build deps failed"
  local src=/tmp/wayplank-src
  rm -rf "$src"; git clone --depth 1 https://github.com/Neeraj-Parekh/wayplank "$src" >>"$LOG" 2>&1 || die "clone failed"
  (cd "$src" && NOCONFIGURE=1 ./autogen.sh >>"$LOG" 2>&1 && ./configure --prefix=/usr >>"$LOG" 2>&1 \
    && make -j"$(nproc)" >>"$LOG" 2>&1 && $SUDO make install >>"$LOG" 2>&1) || die "build failed — see $LOG"
}

install_dock_source_fedora() {
  say "building from source (needs sudo for build deps)"
  $SUDO dnf install -y git vala gtk3-devel libwnck3-devel bamf-devel \
    gee-devel gnome-menus-devel libXfixes-devel libXi-devel \
    libdbusmenu-glib-devel libdbusmenu-gtk3-devel autoconf automake \
    libtool gettext gtk-doc \
    libxml2-utils >>"$LOG" 2>&1 || die "build deps failed (bamf may be missing on this release)"
  local src=/tmp/wayplank-src
  rm -rf "$src"; git clone --depth 1 https://github.com/Neeraj-Parekh/wayplank "$src" >>"$LOG" 2>&1 || die "clone failed"
  (cd "$src" && NOCONFIGURE=1 ./autogen.sh >>"$LOG" 2>&1 && ./configure --prefix=/usr >>"$LOG" 2>&1 \
    && make -j"$(nproc)" >>"$LOG" 2>&1 && $SUDO make install >>"$LOG" 2>&1) || die "build failed — see $LOG"
}

install_dock_source_arch() {
  say "building from source (needs sudo for build deps)"
  $SUDO pacman -S --needed --noconfirm git base-devel vala gtk3 libwnck3 bamf gee gnome-menus dbusmenu-gtk3 libxml2 >>"$LOG" 2>&1 || die "build deps failed"
  local src=/tmp/wayplank-src
  rm -rf "$src"; git clone --depth 1 https://github.com/Neeraj-Parekh/wayplank "$src" >>"$LOG" 2>&1 || die "clone failed"
  (cd "$src" && NOCONFIGURE=1 ./autogen.sh >>"$LOG" 2>&1 && ./configure --prefix=/usr >>"$LOG" 2>&1 \
    && make -j"$(nproc)" >>"$LOG" 2>&1 && $SUDO make install >>"$LOG" 2>&1) || die "build failed — see $LOG"
}

install_bridge() {
  local dest=~/.local/share/gnome-shell/extensions/wayplank-bridge@local
  say "installing bridge extension"
  rm -rf "$dest"
  mkdir -p "$dest"
  curl -fsSL https://codeload.github.com/Neeraj-Parekh/wayplank-bridge/tar.gz/refs/heads/main \
    | tar -xz -C "$dest" --strip-components=1 >>"$LOG" 2>&1 || die "bridge download failed"
  node --check "$dest/extension.js" >/dev/null 2>&1 || have node || true
  if have gnome-extensions; then
    gnome-extensions enable wayplank-bridge@local >>"$LOG" 2>&1 || true
  fi
}

migrate_config() {
  if [ ! -d ~/.config/wayplank/dock1 ] && [ -d ~/.config/plank/dock1 ]; then
    say "migrating Plank config"
    mkdir -p ~/.config/wayplank
    cp -r ~/.config/plank/dock1 ~/.config/wayplank/ >>"$LOG" 2>&1
    cp -rn ~/.local/share/plank/themes ~/.local/share/wayplank/ 2>/dev/null >>"$LOG" 2>&1 || true
    dconf dump /net/launchpad/plank/docks/dock1/ 2>/dev/null \
      | dconf load /net/launchpad/wayplank/docks/dock1/ 2>/dev/null || true
  fi
}

start_service() {
  say "starting service"
  systemctl --user daemon-reload >>"$LOG" 2>&1
  systemctl --user enable --now wayplank.service >>"$LOG" 2>&1 || die "could not start service — see $LOG"
  sleep 6
  systemctl --user is-active wayplank.service >>"$LOG" 2>&1 || die "service won't stay up — see $LOG"
}

verify() {
  command -v wayplank >/dev/null 2>&1 || die "wayplank binary not on PATH"
  pgrep -af "/usr/bin/wayplank|/bin/wayplank" | grep -v pgrep >/dev/null \
    || die "wayplank not running"
  say "dock is running"
  if gdbus call --session --dest org.freedesktop.DBus \
      --object-path /org/freedesktop/DBus \
      --method org.freedesktop.DBus.NameHasOwner org.wayplank.Bridge 2>/dev/null | grep -q true; then
    say "bridge active: running apps will show with indicators"
  else
    say "bridge not loaded yet — log out/in once, then running dots appear (pins work now)"
  fi
}

main() {
  if is_debian_family; then
    if [ "$ID" = "ubuntu" ]; then
      case "$VERSION_ID" in 24.04|25.*|26.*) install_dock_deb;; *) install_dock_source_debian;; esac
    else
      install_dock_deb || install_dock_source_debian
    fi
  elif is_fedora_family; then install_dock_source_fedora
  elif is_arch_family;   then install_dock_source_arch
  else die "unsupported distro ($ID) — build from source per README"; fi
  install_bridge
  migrate_config
  start_service
  verify
  say "done — push to the top screen edge to reveal the dock"
}
main
