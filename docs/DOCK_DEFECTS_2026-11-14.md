# Wayplank dock — verified defect list (2026-11-14)

Audit of `Neeraj-Parekh/wayplank` at commit `3f782dc`, running on the user's
Ubuntu 26.04 / GNOME 50 Wayland laptop (Wayplank dock = XWayland X11 client,
`GDK_BACKEND=x11`).

Every entry below is backed by a reproduced symptom or a journal/probe line.
Nothing here is a guess.

Probe methods used:

- `gdbus call --session --dest org.wayplank.Dock --object-path /org/wayplank/Status --method org.wayplank.Status.<M>`
  (the dock's own live status endpoint: `Hidden`, `MatcherOk`, `RunningApps`,
  `TrackedApps`, `X11Detected`)
- `DISPLAY=:0 xwininfo -id <dock>` / `xprop` (window geometry, map state, EWMH state)
- `DISPLAY=:0 import -window <dock> out.png` (pixel capture of the dock window)
- `journalctl --user -u plank-wayland` (dock journal)
- `gdbus call ... org.wayplank.Bridge.GetRunningApps` (Shell bridge health)

---

## D1 — SIGABRT crash loop: libwnck `g_assert` kills the whole dock

**Severity: CRITICAL (dock fully dead; took the dock down 46× in ~2.5 min)**

**Symptom.** 2026-11-14 12:27–12:31 the service restarted every 3 s
(`NRestarts=47`), each instance dying during startup. Journal:

```
wayplank[1406391]: Wnck:ERROR:../libwnck/xutils.c:1510:default_icon_at_size: assertion failed: (base)
wayplank[1406391]: Bail out! Wnck:ERROR:../libwnck/xutils.c:1510:default_icon_at_size: assertion failed: (base)
systemd[1625]: plank-wayland.service: Main process exited, code=killed, status=6/ABRT
```

**Evidence / chain.**

1. `lib/Factories/AbstractMain.vala:265-266`
   ```vala
   if (environment_is_session_type (XdgSessionType.X11))
       WindowControl.initialize ();
   ```
2. The service unit sets `XDG_SESSION_TYPE=x11` (`~/.config/systemd/user/plank-wayland.service`)
   even though the session is **Wayland** (`WAYLAND_DISPLAY=wayland-0`, GNOME 50).
   So the X11 branch is taken.
3. `WindowControl.initialize()` (`lib/Services/WindowControl.vala:53-69`) calls
   `Wnck.set_client_type (Wnck.ClientType.PAGER)` + `Wnck.Screen.get_default()`,
   and libwnck's `default_icon_at_size()` loads the icon named `gnome-panel`
   from the GTK icon theme and asserts on it.
4. The user's icon theme is `MacOS-3D` and **no installed theme provides
   `gnome-panel`**:
   ```
   $ ls /usr/share/icons/*/gnome-panel* ~/.icons/*/gnome-panel* ~/.local/share/icons/*/gnome-panel*
   (nothing)
   $ gsettings get org.gnome.desktop.interface icon-theme
   'MacOS-3D'
   ```
   → `g_assert (base)` → `SIGABRT` → the dock dies.

**Why the port still calls Wnck at all.** `WindowControl` is the pre-Wayland
window tracker. Its only remaining live reference is `initialize()`; the
`ShellControl` equivalents (`lib/Services/ShellControl.vala:100-111`) are
stubs returning `null`, i.e. the port already replaced Wnck with the Shell
bridge. The Wnck icon helpers `WindowControl.get_app_icon()` (line 107) and
`get_window_icon()` (line 132) still call `Wnck.Window.get_icon()` — the very
API that aborts — and the `get_icon_is_fallback()` check that was meant to
discard the fallback icon happens *after* the fatal call.

**Planned fix.** Treat the session as what it is: skip the Wnck pager client
entirely on a Wayland session (truthful session detection instead of the
`XDG_SESSION_TYPE` lie), and delete the two Wnck icon helpers so no code path
can reach the aborting API.

---

## D2 — Hidden dock paints an opaque black slab over the screen edge

**Severity: CRITICAL (the main "not working at all" symptom)**

**Symptom.** The dock window stays at the screen edge and paints a solid
black 1920×237 rectangle when the dock is hidden.

**Evidence.**

```
$ xwininfo -id <dock>            → Absolute upper-left Y: 843, Height: 237, Map State: IsViewable
$ import -window <dock> out.png  → PNG 1920x237, 8-bit Grayscale Gray 2c, 193 bytes   # uniform black
$ gdbus ... PlankStatus.Hidden   → (true,)                                            # state says hidden
$ import -window <dock> out.png  → (after edge rest) PNG 1920x237 sRGB 46663B        # real dock content
```

The window itself is fine when revealed (rounded translucent dock + icons),
so the *state machine* works; only the **visual** hide is broken.

**Chain.** The X11 screen advertises the Composite extension
(`xdpyinfo | grep Composite` → `Composite`), so `screen_is_composited` is true
and plank's hide is implemented as a *drawing* offset
(`lib/DockRenderer.vala:256-283`, `lib/PositionManager.vala:1321-1350`):
the dock content slides out of the window. The window itself is **not**
moved off-screen in that mode — that branch only exists for
`!screen_is_composited` (`lib/PositionManager.vala:1296-1312`,
`lib/DockRenderer.vala:1030-1035`) — and the window surface is never cleared
to transparent, so what is left on screen is an opaque black strip.

The strip also **swallows clicks**: `xwininfo -shape` reports
"No window shape defined", i.e. the full 1920×237 rectangle accepts input.

**Planned fix.** On this platform the hide must be *positional*: when the
hide animation has fully completed, move the dock window off-screen (and back
when revealing), so a hidden dock is invisible **and** click-through, instead
of relying on alpha compositing that the window does not provide.

---

## D3 — `_NET_WM_STATE_ABOVE` / `_STICKY` are stripped: keep-above is a no-op

**Severity: MEDIUM (the v10 "keep-above" fix does nothing on Wayland)**

**Evidence.**

```
$ xprop -id <dock> _NET_WM_STATE
_NET_WM_STATE(ATOM) = _NET_WM_STATE_SKIP_PAGER, _NET_WM_STATE_SKIP_TASKBAR
```

The state set by `lib/Widgets/DockWindow.vala` (commit `3f782dc`,
`set_keep_above(true)` + `stick()`) is **removed by mutter**: it does not
implement `ABOVE`/`STICKY` for XWayland clients. Ordering above applications
has to come from the window *type* (`_NET_WM_WINDOW_TYPE_DOCK`, which the
dock does set correctly) instead of EWMH state bits.

**Planned fix.** Keep the type hint (that is the part that works), stop
pretending the state bits do anything on Wayland, and document that stacking
is owned by mutter's dock layer.

---

## D4 — X11 pointer barriers are created inside a Wayland session

**Severity: MEDIUM (source of the "keeps hiding and showing" pressure dance)**

**Evidence.** `lib/HideManager.vala:930-959` (`initialize_barriers_support`)
gates on `environment_is_session_type (XdgSessionType.X11)` — which the unit
file makes true — so `XFixes.create_pointer_barrier()` runs against XWayland,
and `pressure-reveal=true` in the live config activates it.

**Chain.** The barrier path was reworked in commit `2ebefb3` to only arm the
edge hold, but the barrier itself still physically traps the pointer at the
screen edge on XWayland, which is the jitter the earlier sessions logged
("pressure barrier jitter").

**Planned fix.** Same truthful-session check as D1: no pointer barriers on a
Wayland session (the 100 ms reveal poll already covers deliberate summons).

---

## D5 — `configure_event` retry loop fights the compositor (CRITICAL log spam)

**Severity: MEDIUM**

**Evidence.** `journalctl`: `[CRITICAL 15:13:31] [DockWindow:321] Retry #1
update_size_and_position() to force requested values!`

**Chain.** `lib/Widgets/DockWindow.vala:313-329` compares the compositor's
reported geometry with the requested one and, on mismatch, re-asserts the
requested position up to three times — while the compositor is the authority
on XWayland (it applies struts, panel avoidance and its own rules). Every
re-assert triggers another `configure` event.

**Planned fix.** Treat the compositor's position as authoritative after the
first re-assert; log at debug level instead of CRITICAL.

---

## D6 — Unresolvable application id (`nyx.desktop`) spams the journal and rescans disk

**Severity: MEDIUM (log noise + repeated filesystem scans)**

**Evidence.** Every few seconds:
`[WARN] [ApplicationDockItemProvider:406] Matching application for
'nyx.desktop' not found or not installed!` — while the bridge reports
`nyx.desktop` as running.

**Chain.** `lib/Items/ApplicationDockItemProvider.vala:380-407`: every Unity
launcher update for an app whose `.desktop` file cannot be located runs
`desktop_file_for_application_uri()` (line 111) again — a scan of every
applications directory in `Paths.DataDirFolders` — and then logs a warning.
There is no negative cache and no de-duplication.

**Planned fix.** Cache negative lookups per app id and log each unresolved id
once.

---

## D7 — Unity launcher entries "behaving badly, skipping requests"

**Severity: LOW/MEDIUM (dock items can miss launcher updates)**

**Evidence.** `[WARN] [Unity:249] LauncherEntry ':1.5826' is behaving badly,
skipping requests` — repeatedly, from several bus names.

**Chain.** `lib/Services/Unity.vala:239-272` throttles launcher updates; the
throttled path defers the update by `UNITY_UPDATE_THRESHOLD_DURATION`, and
the deferred `perform_update()` re-enters the same launcher flow. Combined
with D6 (unresolvable ids re-scanning disk) the loop keeps re-triggering.

**Planned fix.** Covered together with D6 (stop re-processing ids that
cannot be matched); the throttle itself stays as upstream has it.

---

## D8 — GSettings enum id collision with the installed plank schema

**Severity: HIGH (latent, breaks GSettings system-wide if the schema is installed system-wide)**

**Evidence.**

```
$ grep -n "enum id=" /usr/share/glib-2.0/schemas/net.launchpad.plank.gschema.xml
2:  <enum id="PlankHideType">
11: <enum id="GtkAlignType">
18: <enum id="GtkPositionType">
```

Our schema (`data/net.launchpad.wayplank.gschema.xml`) declares the same
three enum ids. Enum ids are global within a schema *source*; if this file
ever lands in a directory compiled together with the plank schema,
`glib-compile-schemas` fails with an enum-name conflict and **every**
GSettings application on the system breaks.

The working tree already contains the fix (uncommitted): `PlankHideType` →
`WayplankHideType`, `GtkAlignType` → `WayplankGtkAlignType`, `GtkPositionType`
→ `WayplankGtkPositionType`.

**Planned fix.** Commit the rename as its own change (it is correct and
necessary), then rebuild + reinstall the compiled schema.

---

## D9 — `src/wayplank` libtool wrapper hard-codes a stale source path

**Severity: LOW (local build artifact)**

**Evidence.** `git diff src/wayplank`:
`LD_LIBRARY_PATH="/home/neeraj-parekh/plank-wayland/plank/lib/.libs:..."` →
the source tree moved to `/home/neeraj-parekh/src/wayplank`.

**Planned fix.** Commit the path fix separately (the file is tracked in the
repository), per request.

---

## D10 — The hide state machine is invisible in the journal

**Severity: MEDIUM (blocks every future diagnosis)**

**Evidence.** With `G_MESSAGES_DEBUG=all` in the service unit, the journal
contains **zero** `hide state changed` lines even though the dock is
demonstrably hidden (`PlankStatus.Hidden = true`).

**Chain.** The transition log lives in `update_hidden()`
(`lib/HideManager.vala`), but the actual hide happens in the *timer callback*
installed by `hide()` (`lib/HideManager.vala:444-449`), which sets `Hidden`
directly — bypassing the log. Same for the breaker path, which returns before
the log line.

**Planned fix.** Log every `Hidden` transition where it happens (property
notify) plus a low-rate heartbeat with the state machine's live values.

---

## Behavioural contract (from the requirements of this conversation)

These are the invariants the fixes must preserve:

1. **Force-hide until explicitly shown** — hidden means *invisible and
   click-through*; only a deliberate edge rest (≈1 s) or a gated pressure push
   may summon it. Pointer position alone never summons it.
2. **Keep-above** — the dock must paint above application windows
   (`_NET_WM_WINDOW_TYPE_DOCK` + mutter's dock layer; EWMH `ABOVE` is
   stripped on Wayland, see D3).
3. **Plank behaviour** — hover keeps a visible dock up, leaving hides it,
   icons launch, right-click menus work, the dock does not crash.

## Verification gates for the fixes

- `journalctl --user -u plank-wayland | grep -c ABRT` → 0 after a full day
- `PlankStatus.Hidden` → true while the pointer is away, and the dock window
  must be **off-screen** (not a black strip) and not accept clicks
- `import -window <dock>` → transparent/empty while hidden, icons when shown
- `xprop -id <dock> _NET_WM_STATE` → no CRITICAL spam in the journal
