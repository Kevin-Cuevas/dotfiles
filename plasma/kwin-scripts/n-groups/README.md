# n-groups

Window groups for KWin (Plasma 6.7+, Wayland). Windows you link by hand become
**one Alt+Tab entry** and **raise, minimize and restore together**. Nothing is
grouped behind your back: Meta+Space, click the windows, done. The bundled `n-switcher` Alt+Tab layout draws every group as a live
mosaic of its windows and previews the whole group on screen while it's
selected.

```
script/     n-groups     KWin script: groups, Alt+Tab entries, shortcuts
switcher/   n-switcher   Alt+Tab layout: live mosaic + whole-group preview
install.sh               install, uninstall, status, doctor
```

No daemons, no services: both are plain KDE packages that KWin loads itself.

## Install

```bash
./install.sh              # install/update both, enable n-groups, use n-switcher
./install.sh --no-switcher  # same, but keep your Alt+Tab layout
./install.sh status
./install.sh doctor       # Plasma version + drift between this folder and the install
./install.sh uninstall    # restore Alt+Tab, disable and remove both
```

Packages go to `~/.local/share/kwin/{scripts,tabbox}/`. Everything else can be
changed from System Settings:

| What | Where |
|---|---|
| Turn n-groups on/off | Window Management → KWin Scripts |
| Options (mouse picking, minimize together, on-screen messages) | KWin Scripts → n-groups → ⚙ |
| Alt+Tab layout | Window Management → Task Switcher → Visualization |
| Shortcuts | Shortcuts → KWin → search "n-groups" |

## Usage

**Meta+Space** opens pick mode: the screen dims and the window under the
pointer is lifted above it with a breathing frame.

- **Click** windows to pick them (numbered 1, 2, 3…); click again to drop one.
  The active window starts picked.
- Picking a window that's already grouped brings its whole group along
  (marked with the link icon), so A+B then picking B and C gives A+B+C.
- **Enter** or **Meta+Space** links them; the new group is shown alone for a
  moment. **Esc** or **right-click** cancels.

| Shortcut | Action |
|---|---|
| `Meta+Space` | Pick mode (or, with "Pick windows with the mouse" off: press on one window, then on another) |
| `Meta+Shift+Space` | Unlink the active window from its group |
| `Meta+Ctrl+Space` | Focus the next window in the group, left to right |
| *(no key)* | Ungroup the active window's whole group |

Groups live in memory and are gone after logging out.

## How it works

- **One Alt+Tab entry.** Only the last used member of a group stays in the
  switcher; the rest get `skipSwitcher`. Every KWin signal just schedules a
  `reconcile()`, which rebuilds all groups from scratch and applies the
  difference, so a missed event can't leave windows hidden.
- **Pick mode.** A borderless OSD-type `PlasmaCore.Dialog` spans every screen
  and takes the clicks. The window under the pointer comes from
  `Workspace.cursorPos` and the stacking order, and picked windows are drawn
  above the dim with live `WindowThumbnail`s. Esc only works if the overlay
  gets keyboard focus; right-click and Meta+Space always do.
- **Raise together.** Entering a group from outside (Alt+Tab, taskbar, a click
  from another app) raises every member with `Workspace.raiseWindow`.
- **Script ↔ switcher.** KWin builds Alt+Tab layouts in the same `QQmlEngine`
  as declarative scripts (`tabboxhandler.cpp`). n-switcher imports the
  script's `groups.mjs` by the same URL, so both share one module instance and
  the switcher reads live groups through `switcherGroup(windowId)`. That's why
  n-switcher needs n-groups next to it: `install.sh` never selects it without
  the script, and `uninstall` restores Alt+Tab first.
- **Whole-group preview.** The `highlightwindow` effect has a D-Bus API
  (`org.kde.KWin.HighlightWindow.highlightWindows`, signature `as`) and the
  last call wins. Shortly after TabBox's own call, n-switcher sends every
  member plus its own popup (found by the Dialog title). The popup has to be
  in the list, otherwise the effect ghosts Alt+Tab itself. From QML the IDs
  must be a `list<string>`: a JS array goes out as `av` and KWin rejects it.

## Notes

- **KWin caches scripts for the whole session.** The `.mjs` and the QML are
  cached by URL, so reloading a script keeps running the old code. After
  updating, log out and back in (`install.sh` says so when needed). For the
  same reason, on reload the old instance is destroyed after the new one is
  created: `init()` returns a generation token and only the matching
  `teardown()` clears state.
- Overview (Meta+W) and Grid (Meta+G) show only one window per group: KWin
  hides `skipSwitcher` windows there too (`WindowHeapDelegate.qml`).
- The mosaic and the preview rely on KWin internals (the shared QML engine and
  the effect's D-Bus API). If they break after a Plasma update, look there
  first; groups and shortcuts only use the public scripting API.
- Turning n-groups off brings every window back to Alt+Tab, Overview and Grid.
  n-switcher then shows a plain grid.

## Testing

Tested in a nested headless KWin (`kwin_wayland --virtual`) with its own
`XDG_CONFIG_HOME`/`XDG_DATA_HOME` and session bus, never touching the real
session: probe scripts loaded through D-Bus (`/Scripting loadScript`) read
window state, and shortcuts are triggered for real with
`qdbus6 org.kde.kglobalaccel /component/kwin …invokeShortcut n-groups-link`.

## License

GPL-2.0-only. Inspired by
[kwin-window-groups](https://github.com/HiluaGhoest/kwin-window-groups).
