# n-groups

Snap groups for KWin (Plasma 6.7+, Wayland). Windows tiled together, or linked
by hand, become **one Alt+Tab entry** and **raise, minimize and restore
together**. The bundled `n-switcher` Alt+Tab layout draws every group as a live
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
| Options | KWin Scripts → n-groups → ⚙ |
| Alt+Tab layout | Window Management → Task Switcher → Visualization |
| Shortcuts | Shortcuts → KWin → search "n-groups" |

## Usage

Groups form on their own:

- **Meta+T tiling:** windows in the same custom tile layout (same screen,
  desktop and activity).
- **Quick tiling:** Meta+Arrow or dragging to a screen edge (optional).

| Shortcut | Action |
|---|---|
| `Meta+Space` ×2 | Link: press on one window, then on another. Both bring their whole group, so A+B then B→C is A+B+C. Pressing twice on the same window, or waiting 8 s, cancels. |
| `Meta+Alt+Space` | Unlink the active window. In a tiling group, until it leaves the tile. |
| `Meta+Shift+Space` | Ungroup the active window's whole group |
| `Meta+Ctrl+Space` | Focus the next window in the group, left to right |

Links made by hand live in memory and are gone after logging out.

## How it works

- **One Alt+Tab entry.** Only the last used member of a group stays in the
  switcher; the rest get `skipSwitcher`. Every KWin signal just schedules a
  `reconcile()`, which rebuilds all groups from scratch and applies the
  difference, so a missed event can't leave windows hidden.
- **Tiling groups.** A window's tile is walked up to its root. Meta+T layouts
  hang from `Workspace.rootTile(output, desktop)`; quick tiles don't.
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
