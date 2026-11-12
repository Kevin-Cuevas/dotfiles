# dotfiles

Portable dotfiles for Debian-based systems, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Each top-level directory is a Stow package that maps directly into `$HOME`.

---

## Quick start

From a fresh machine (only `git` and `curl` required):

```bash
curl -fsSL https://raw.githubusercontent.com/nvkcx/dotfiles/main/install | bash
```

Or non-interactively (installs everything without prompts, except the
Plasma and boot themes and the background services: run `dev-plasma` /
`dev-boot` / `dev-services` for those):

```bash
curl -fsSL https://raw.githubusercontent.com/nvkcx/dotfiles/main/install | bash -s -- --all
```

The apt packages follow a machine **profile**, detected on its own (KDE
Plasma installed → `desktop`, otherwise `server`); force one with
`--profile=desktop` or `--profile=server` (see
[Packages installed by bootstrap](#packages-installed-by-bootstrap)).

Or if you already have the repo cloned:

```bash
~/dotfiles/bootstrap
```

The bootstrap opens an interactive TUI (via `dialog`) where you can install
packages, stow configs, install Neovim, fonts, TPM, and more, individually or
all at once.

---

## Layout

```
dotfiles/
├── bin/          -> ~/.local/bin          personal CLI tools and dev-* helpers  [per-file]
├── boot/                                GRUB + Plymouth themes (not stowed: dev-boot)
├── cava/         -> ~/.config/cava
├── icons/        -> ~/.icons              cursor and icon themes
├── kitty/        -> ~/.config/kitty
├── konsole/      -> ~/.local/share/konsole  Konsole/Yakuake profiles + NivekDark/LightNordKonsoleColors  [per-file]
├── nvim/         -> ~/.config/nvim        LazyVim config
├── peaclock/     -> ~/.peaclock
├── plasma/                                KDE Plasma Global Themes + color schemes + light/dark wallpapers + Yakuake settings + own KWin scripts (not stowed: dev-plasma)
├── ssh/          -> ~/.ssh/config         shared defaults only; hosts & keys stay local [per-file]
├── system/                                MOTD + background jobs (not stowed)
│   ├── motd/                              root-run MOTD scripts (dev-motd)
│   ├── services/                          always-running jobs: dotfiles-*.service (dev-services)
│   └── timers/                            scheduled jobs: dotfiles-*.service + .timer (dev-services)
├── task/         -> ~/.config/task
├── templates/    -> ~/.templates
├── tmux/         -> ~/.tmux.conf, ~/.tmux-theme.conf
├── zsh/          -> ~/                    .zshrc, .p10k.zsh
├── zsh-completions/ -> ~/.zsh/completions  zsh #compdef files (ssh, mycli, tmuxp, tailscale...)  [per-file]
├── bootstrap                              interactive setup script (entrypoint)
├── bootstrap.d/                           bootstrap's implementation, one file per concern
└── README.md
```

`[per-file]` marks the packages stowed one-symlink-per-file instead of
one symlink for the whole directory — see **Stow strategy** below.

---

## Stow strategy

Every top-level directory is a Stow package, but not all of them get stowed
the same way — `stow_packages()` splits them into two groups
(`STOW_PER_FILE_PACKAGES` in `bootstrap.d/30-stow.sh`, right above the
function):

**Whole-folder** (`cava, icons, kitty, nvim, peaclock, task, templates, tmux,
zsh`) — the target directory is 100% owned by the repo, so stow links it as
a single symlink (e.g. `~/.config/nvim -> dotfiles/nvim/.config/nvim`).
Simplest option, and correct here because nothing else ever needs to write
into these directories.

**Per-file** (`bin, konsole, ssh, zsh-completions`) — their target directories
also receive files we don't track: new SSH keys, `ControlMaster` sockets in
`~/.ssh`, binaries dropped by `pipx`/`curl` in `~/.local/bin`, new
profiles/colorschemes Konsole creates from its GUI in
`~/.local/share/konsole`, and completion files a `dev-*` CLI generates for
itself on its own host (e.g. `dev-pagipage-domains --set-autocompletions` on
`nivek-core` writes straight into `~/.zsh/completions/_dev-pagipage-domains`
— that script lives only on that server, outside this repo on purpose, so its
completion file must be able to sit next to the tracked ones without git ever
seeing it). Folding these into one symlink would mean anything written there
later lands physically inside `~/dotfiles` instead of the real directory. So
`stow_packages()` runs these with `--no-folding`, creating a **real** target
directory plus one symlink per tracked file — only what we explicitly put in
the package is managed by stow. Add a new file to one of these packages and
re-run the stow step: it links just that new file, it never re-folds the
directory into a single symlink.

For `zsh-completions` specifically, `zsh/.zshrc` prepends `~/.zsh/completions`
to `fpath` **before** `compinit` — that ordering is what makes the tracked
files and any `dev-*`-generated ones actually load. After `compinit` it only
worked by luck (a stale `~/.zcompdump`, or a `$FPATH` inherited from an
already-running zsh); on a fresh machine both are absent, which is why the
completions were missing on `nivek-core` until the fix.

**`system/`** — excluded from stow entirely (`stow_packages()` skips it by
name). It needs two different non-stow mechanisms instead:

- MOTD (`system/motd/`) is installed with a root `cp` into
  `/etc/update-motd.d` via `dev-motd` (bootstrap menu option 6) — it can't be
  a user symlink since that directory is root-owned. `dev-motd` also creates
  `~/.hushlogin`, and `zsh/.zshrc` prints the MOTD instead of PAM: once per
  interactive SSH login, the same over OpenSSH and Tailscale SSH, and never in
  tmux panes, nested shells or local terminals. (`pam_motd` only prints on the
  first session of each connection, so with `ControlMaster` a `scp` or `git`
  that opened the connection swallowed it, and Tailscale SSH has no PAM.)
- Background jobs (`system/services/`, `system/timers/`) are installed as
  systemd `--user` units by `dev-services` (bootstrap menu option 15) — see
  [Background services](#background-services-systemd---user).

---

## Bootstrap

`bootstrap` is a standalone Bash script. It requires no dependencies beyond a
working Debian-based system, it will install `dialog` and `stow`
automatically if they are missing.

```bash
~/dotfiles/bootstrap
```

`bootstrap` itself is a thin entrypoint: parse args, source every
`bootstrap.d/*.sh` module, define the menu, run it. Each module owns one
concern and is just a library of functions/data — nothing in `bootstrap.d/`
runs on its own:

| Module | Concern |
| --- | --- |
| `00-core.sh` | logging, preflight, header — loads first, everything else depends on it |
| `10-packages.sh` | apt packages only (menu option 2), in groups and machine profiles — non-apt tools live in `dev-packages`, see below |
| `20-runtimes.sh` | language runtimes: rust, node, deno, java via SDKMAN (menu option 12) |
| `30-stow.sh` | stow strategy (menu option 4) + systemd `--user` unit linking |
| `40-misc.sh` | default shell, `dev-*` permissions, `dev-packages`/`dev-motd`/`dev-ssh`/`dev-plasma`/`dev-boot`/`dev-services` launchers, fonts, TPM, Timewarrior hook |

Modules are sourced in lexical order (`NN-` prefixes, stepped by 10 so a new
one can slot in without renumbering) purely to guarantee `00-core.sh` loads
first — beyond that, load order doesn't matter, since nothing in
`bootstrap.d/` calls a function at source time. **To add a new installer**:
add a function to the relevant module (or drop a new `bootstrap.d/NN-name.sh`
file — it's picked up automatically, nothing to register), then wire it into
`RUNTIME_FN` or the menu in `bootstrap` if it needs to be reachable from
there. For a new non-apt tool, add it to `dev-packages` instead (see below).

**Menu options:**

| #   | Action                                       |
| --- | -------------------------------------------- |
| 1   | Run everything (2 through 15)                |
| 2   | Install apt packages                         |
| 3   | Set permissions on `dev-*` scripts           |
| 4   | Stow packages into `$HOME`                   |
| 5   | Install/update extra packages via `dev-packages` |
| 6   | Install MOTD via `dev-motd`                  |
| 7   | Install/update Nerd Fonts (FiraCode + FiraMono); option 1 runs it on `desktop` only |
| 8   | Set up Timewarrior hook for Taskwarrior      |
| 9   | Install TPM (Tmux Plugin Manager)            |
| 10  | Configure SSH (control dir + servers)        |
| 11  | Set zsh as default shell                     |
| 12  | Install language runtimes (rust, node, ...)  |
| 13  | KDE Plasma themes via `dev-plasma`           |
| 14  | Boot themes (GRUB + Plymouth) via `dev-boot` |
| 15  | Background services via `dev-services`       |

**Test mode** — stow into a throwaway directory instead of `$HOME`:

```bash
~/dotfiles/bootstrap /tmp/test-home
```

---

## SSH configuration

The tracked `ssh/.ssh/config` holds **only generic defaults** (the `Host *` block:
ControlMaster, keepalives, the tmux `LocalCommand`, etc.) plus an
`Include ~/.ssh/config.local` at the top. **No host aliases are tracked** — your
connection topology never leaves your machine.

Per-machine hosts live in `~/.ssh/config.local`, which is **not tracked** and is
split into two zones:

```
# ... your own content (IdentityFile, hand-written hosts) — PRESERVED ...

# >>> dotfiles:ssh-hosts (managed — no editar a mano) >>>
#@ group:manual
Host my-box
    HostName 10.0.0.5
    User root
#@ group:tailnet:you@example.com
Host nivek-lab
    HostName nivek-lab
    User nivek
# <<< dotfiles:ssh-hosts <<<
```

Inside the managed block, hosts are grouped with `#@ group:<id>` comment headers
(SSH ignores them). Groups are `manual` or `tailnet:<name>`. Only the region
**between the markers** is ever rewritten; everything outside is kept across runs.

The whole SSH module lives in the standalone helper **`dev-ssh`** (stowed to
`~/.local/bin/dev-ssh`). Run `dev-ssh` directly to open the menu below, or reach it
from bootstrap menu option **10 → Configure SSH** (which just launches `dev-ssh`).
`dev-ssh --setup` does the non-interactive part only (control dir + ensure
`config.local`), which is what the `--all` bootstrap run uses.
`dev-ssh --add-host=ALIAS [--user=U] [--port=P] [--group=G]` adds or updates a single
host with no prompts, for other scripts to call: the same entry the Tailscale flow writes,
under the active tailnet's group unless `--group` says otherwise (`manual` when there is
no tailnet), and recorded in the username history. It only upserts that one alias; the
rest of the group is left alone.

- **Control dir + ensure config.local** — creates `~/.ssh/cm` (700) and, if missing,
  `config.local` with an empty managed block. This is what the non-interactive
  `--all` run does (markers present, block empty).
- **Manual** — a form for `Host` (required), `HostName` (defaults to `Host`), `User`
  (defaults to `$USER`), `Port` and `IdentityFile` (optional). Saved under
  `group:manual`.
- **Autocomplete (Tailscale)** — requires `tailscale` installed and logged in. First
  you **pick a tailnet** from `tailscale switch --list` (defaults to the active one);
  if it isn't the active profile, bootstrap runs `tailscale switch <id>` (and stays on
  it). Then it lists that tailnet's peers (MagicDNS labels, **self excluded**) and you
  check one or many. Finally it asks the `User` **per node** (see _Username history_
  below). Saved under `group:tailnet:<name>`.

Entries are upserted by alias, **globally deduped** — re-adding a host updates it and
moves it to the new group instead of duplicating.

### Username history (Tailscale flow only)

The per-node `User` prompt is backed by a per-machine history file
`~/.ssh/.ssh_user_history` — **not tracked** (gitignored); share it between your own
nodes manually with `scp` to seed their autocomplete. It is a TSV of
`tailnet⇥node⇥username⇥epoch`, `chmod 600`, append-only.

For each node, suggestions are scoped strictly to `(tailnet, node)` — a node may have
several usernames, but you never get cross-node noise:

- node **with** history → a menu of its previously-used usernames (most recent first,
  pre-selected) plus _"✎ Escribir otro…"_ to type a new one;
- node **without** history → a plain input that defaults to the last username you typed
  this session (session carry; first node defaults to `$USER`).

Every choice is recorded, so the most recent username for a node bubbles to the top next
time. The **Manual** flow does not use this history.

### Tailnet-aware shell completion

`ssh`/`scp` tab-completion (`zsh/.zshrc`, `_ssh_host_list`) reads both `~/.ssh/config`
and `~/.ssh/config.local` and filters by the **active tailnet** (detected from
`tailscale switch --list`):

- ungrouped/hand-written hosts and `group:manual` → **always** offered;
- `group:tailnet:<name>` → offered **only when that tailnet is active**;
- no active tailnet (or no `tailscale`) → only manual + ungrouped.

So you only ever tab-complete the hosts reachable on your current tailnet, plus your
manual ones.

> **History note:** host aliases removed from `ssh/.ssh/config` still exist in older
> git commits. To scrub them from history you'd rewrite it (e.g. `git filter-repo`)
> and **force-push** — coordinate with any clones and check repo visibility first.
> This is intentionally left as a manual step.

---

## Packages installed by bootstrap

apt packages come in groups, and a machine **profile** decides which groups
it gets:

| Group          | Packages | `server` | `desktop` |
| -------------- | -------- | :------: | :-------: |
| `core`         | git stow zsh curl wget kitty-terminfo fzf ripgrep fd-find bat zoxide eza direnv zip unzip figlet toilet | ✔ | ✔ |
| `dev`          | build-essential cmake libicu-dev golang pipx (`dev-packages` builds with them) | ✔ | ✔ |
| `productivity` | taskwarrior timewarrior | ✔ | ✔ |
| `desktop`      | yakuake wl-clipboard | | ✔ |
| `login`        | plasma-login-manager (opt-in: in no profile, `--all` skips it) | | |

The profile is detected on its own (KDE Plasma installed → `desktop`,
otherwise `server`: servers, the Termux VM) and can be forced with
`bootstrap --profile=desktop|server`. `--all` installs the profile's groups.
The menu (option 2) preselects them, shows how many packages of each group
are missing, and optionally lets you pick packages inside each group (with
a description and `✔ installed`). Everything missing goes to apt in a single
`apt-get install`; if that fails, each package is retried alone to tell which
one broke. Packages the Debian release doesn't have (`plasma-login-manager`
exists only in forky/sid, not in 13) show as `— not in this release` and are
skipped, so they never break the run. With `--all`, apt runs without
questions, so installing `plasma-login-manager` keeps the current login
manager; from the menu, debconf asks which one to use. Switching is up to
you, and `dev-plasma` sets the cursor on whichever one is installed. Java comes from SDKMAN (language runtimes, option 12), not apt.

To add a package: `APT_PKGS` (listing order), `APT_PKG_GROUP` and
`APT_PKG_DESC` in `bootstrap.d/10-packages.sh`.

---

## Extra (non-apt) packages

Tools that don't come from apt (or whose apt version lags too far behind
upstream) are installed and updated by a single standalone script,
**`dev-packages`** (stowed to `~/.local/bin/dev-packages`), instead of being
hardcoded into `bootstrap.d/`. Run it directly, or reach it from bootstrap
menu option **5**:

```bash
dev-packages                 # interactive checklist (dialog)
dev-packages --all           # install/update everything, no prompts
dev-packages --only=kitty    # install/update just one, no prompts
dev-packages --keep-apt      # don't purge a same-named apt package (nvim/tmux/tree-sitter)
dev-packages --help          # usage + the list of package keys
```

It manages:

| Tool       | Update mechanism                                                |
| ---------- | ----------------------------------------------------------------- |
| `nvim`     | its own `install_nvim` function: choice of build-from-source (`-march=native`) or precompiled tarball, version-compared before reinstalling |
| `tmux`     | build-from-source only (no upstream precompiled binaries) — latest git tag compared against the installed version |
| `kitty`    | compares the official `current-version.txt` against the installed version; if needed, downloads the official installer to a file and runs it (replaces in-place) |
| `yazi`, `tree-sitter` | shared `github_release_install`: downloads the latest GitHub release asset, compares the downloaded binary's version against the installed one |
| `tmuxp`, `pgcli`, `mycli`, `csvkit` | `pipx install` if missing, `pipx upgrade` if already installed |
| `peaclock` | no upstream releases — compares the remote git HEAD sha against one saved after the last build |
| `lavat`    | same as peaclock: remote git HEAD sha comparison                 |

`nvim`, `tmux` and `tree-sitter` also have a same-named apt package: by default, installing
them via `dev-packages` purges the apt version afterward so only one binary
ends up on the `PATH` — pass `--keep-apt` (or set `KEEP_APT_PKGS=true`) to
leave the apt package installed alongside it instead.

In its checklists, leave everything unchecked and press ENTER to
install/update all of them, or check "Skip" to do nothing.

Everything temporary (downloads, clones, builds) lives in a single work
directory that a trap removes on exit, Ctrl-C included.

---

## KDE Plasma themes

Two Global Themes travel with the repo, as a light/dark pair for Plasma's
**Automatic** mode:

| Global Theme     | Colors                 | Icons                    | Cursor              | Splash |
| ---------------- | ---------------------- | ------------------------ | ------------------- | ------ |
| `NivekDarkNord`  | `NivekDarkNordColors`  | Papirus-Dark (nordic folders)  | Bibata-Modern-Ice | Kuro |
| `NivekLightNord` | `NivekLightNordColors` | Papirus-Light (nordic folders) | Bibata-Modern-Ice | Kuro |

Application style, Plasma style and window decorations are Breeze; system
sounds (Ocean) and the login screen (Debian Breeze) are left at their
defaults — a Global Theme doesn't control either of them. Naming is
`Nivek<Mode><Style>` / `Nivek<Mode><Style>Colors`, so other styles can sit
next to Nord later. In each `.colors` file the filename, `[General]ColorScheme=`
and `Name=` are the same id: Plasma resolves `ColorScheme=` against that id,
and when they disagree it marks the Global Theme as applied while silently
keeping the old colors.

The themes, their color schemes and the wallpapers live in `plasma/`, which
is **not** stowed. Each wallpaper is a package with `images/` + `images_dark/`,
so it follows light/dark on its own: Nord Flare (the default) plus Nord
Astronaut, Bedroom, Data Breach, Deer, Great Wave, Lighthouse, Sakura,
Samurai, Study Room and Watchtower (Nord-recolored art, 1920x1080, both
variants cropped the same way). Adding one is adding its folder under
`plasma/wallpapers/`. Plasma reads Global Themes (and wallpaper
packages) through KPackage, which rejects any file whose real path falls
outside the package folder (`kf.package: Path traversal attempt detected` in
the journal): a theme symlinked into `~/dotfiles` gets its `contents/defaults`
ignored and Plasma silently applies Breeze. So they're installed as **copies**,
like any "Get New…" theme — the repo is the source of truth, edits happen
there and `dev-plasma --only=themes` reinstalls whatever changed. The themes carry
**no desktop/panel layout** on purpose: a layout replaces the whole panel,
pinned apps included. The launcher icon (`nivek-debian`, a Nord frost Debian
swirl kept in `plasma/icons/hicolor`) is set by its own key instead, which
changes only that icon.

Installing the themes and everything they *reference* but don't contain is
handled by **`dev-plasma`** (bootstrap menu option **13**). It finds `plasma/`
from its own real path, so it works from `~/.local/bin` too:

```bash
dev-plasma                  # interactive checklist (dialog)
dev-plasma --all            # every key, no prompts
dev-plasma --only=themes    # just one key
dev-plasma --list-wallpapers           # the repo's wallpapers (* = applied)
dev-plasma --wallpaper=Nord-lighthouse # set one (alone, implies --only=wallpaper)
dev-plasma --list-kwin-scripts         # the repo's KWin scripts (* = installed)
dev-plasma --kwin-script=n-groups      # install one (alone, implies --only=kwin-scripts)
dev-plasma --doctor         # check that every referenced piece exists; changes nothing
dev-plasma --help           # usage + the list of keys
```

| Key           | What it does |
| ------------- | ------------ |
| `themes`      | installs the Global Themes from `plasma/look-and-feel` with `kpackagetool6` (Plasma's official package installer: `--install`, or `--upgrade` when it's already there), and copies the `.colors` files, the wallpapers and the launcher icon (`kpackagetool6` can't install image wallpapers: `Wallpaper/Images` has no package root and its `--upgrade`/`--remove` fail). Only touches what differs from the repo; leftover symlinks from an older stow setup are replaced |
| `icons`       | `papirus-icon-theme` from apt + [`papirus-folders`](https://github.com/PapirusDevelopmentTeam/papirus-folders) (not in apt) set to `nordic`. Offers to remove a Papirus copy in `~/.local/share/icons` (from "Get New…"), which would shadow the apt one. The folder color is re-checked every run, since an apt upgrade resets it to blue. When something actually changed it rebuilds KDE's cache (`kbuildsycoca6`) and restarts plasmashell once, so the panel doesn't keep showing broken icons; apps that were already open need a restart (or a re-login) |
| `splash`      | Kuro from [its git repo](https://github.com/bouteillerAlan/kuro) (GPLv3), remote HEAD sha compared like peaclock — not from the KDE store, whose download URLs expire |
| `login-cursor` | the theme's cursor on the login screen, for both login managers (formerly `sddm-cursor`, still accepted). Copies it to `/usr/share/icons` first: the login screen runs as its own user, which can't read a `0710` home. **SDDM**: writes `CursorTheme=` to `/etc/sddm.conf.d/dev-plasma.conf` only if nothing sets it yet (System Settings' `kde_settings.conf` sorts after it and still wins). **Plasma Login** (KDE's SDDM fork) ignores that file: its greeter is a small Plasma session of the `plasmalogin` user, so only `[Mouse] cursorTheme` is written to that user's `kcminputrc`, as that user. The cursor is also pinned in your own `~/.config/kcminputrc`: the Global Theme's value lives in `~/.config/kdedefaults/`, and System Settings' "Apply Plasma Settings…" copies only your own files, so without it the login screen fell back to Breeze's cursor. The doctor can't read the `plasmalogin` user's config without root, so it skips that one |
| `apply`       | applies the theme matching the current mode (light/dark is read from the active window background) and records the light/dark pair in `kdeglobals`. Leaves the "Switch to Dark Mode at Night" toggle exactly as it was (applying a theme clears it, so it's saved and restored), and never touches your panel |
| `wallpaper`   | sets one of the wallpapers in `plasma/wallpapers` (each follows light/dark on its own). From the checklist it opens a list: **Preview** puts the highlighted one on your desktop right away and comes back to the list, **Light/dark** opens both of its variants in the image viewer (Preview only shows the current mode's), **Apply** keeps it and **Cancel** puts back exactly what every desktop had. There's no state file: the applied wallpaper is the choice, so `--all` keeps it when it's one of the repo's, sets Nord Flare over a stock KDE one, and keeps a hand-picked one (replaced only when this key is picked explicitly) |
| `launcher-icon` | sets the `nivek-debian` icon on the launcher (Kickoff/Kicker) of your existing panels through plasmashell's scripting (DBus), changing only that key — pinned apps, widgets and layout stay as they are. Same rule as the wallpaper: a hand-picked icon is kept on `--all` |
| `yakuake`     | writes the keys listed in `plasma/yakuake/yakuakerc` (no skin borders, no title or tab bar, no tray icon, `KeepOpen=false`, no session-switch shortcuts) one by one with `kwriteconfig6`, so size, position and anything else you set stay yours. Yakuake writes its whole config back when it quits, so if it's running it offers to quit and restart it (on `--all` it only warns). Also removes links to Konsole profiles renamed in the repo and points `DefaultProfile` at an existing one |
| `kwin-scripts` | the repo's own KWin scripts, one standalone folder each under `plasma/kwin-scripts/` with its own `install.sh` (`install`, `uninstall`, `status`, `doctor`): this key only runs it, so adding a script is adding a folder. From the checklist it opens a list to pick from; turning them on/off later is up to System Settings → KWin Scripts. The doctor runs each installed one's `install.sh doctor` |

The doctor also applies KPackage's own rule (every file must resolve inside its package folder), so a theme Plasma would silently ignore shows up as an error, and warns when an installed theme, color scheme or wallpaper differs from the repo.
For every wallpaper it also checks that `metadata.json`'s `Id` matches the
folder, that `contents/images/` isn't empty, that each file's `WxH` name
matches its real size (Plasma picks the file by its name) and that the light
and dark variants come in the same sizes.

### KWin scripts

| Script | What it does |
| ------ | ------------ |
| [`n-groups`](plasma/kwin-scripts/n-groups/) | Window groups made by hand: `Meta+Space` opens a pick mode (click the windows, Enter to link) and the group then shares **one Alt+Tab entry** and raises, minimizes and restores together; `Meta+Shift+Space` unlinks. Brings the `n-switcher` Alt+Tab layout, which draws each group as a live mosaic and previews the whole group on screen. Code changes need a re-login: KWin caches scripts for the whole session |

Outside KDE Plasma `dev-plasma` does nothing and exits 0, so `--all` is safe
on servers. `bootstrap --all` skips it (and `dev-boot`): themes are opt-in. A run always ends with the doctor.

**Konsole / Yakuake** use the profiles `NivekDarkNordKonsole` /
`NivekLightNordKonsole` with the color schemes `NivekDarkNordKonsoleColors` /
`NivekLightNordKonsoleColors` (the `konsole/` stow package; the terminal
palettes match kitty's). Switching them with Plasma's light/dark mode is the
job of the `konsole-theme-sync` background service (`dev-services`): it sets
the default profile of Yakuake and Konsole and recolors the open sessions
live. Autostart and the toggle shortcut are left to you.

Yakuake starts with `QT_SCALE_FACTOR_ROUNDING_POLICY=Ceil` so block characters
(lavat, cava) show no grid on a fractional-scale monitor. The `yakuake` wrapper
in `bin/` and the D-Bus service in `konsole/` set it; if you autostart Yakuake,
use `Exec=/usr/bin/env QT_SCALE_FACTOR_ROUNDING_POLICY=Ceil /usr/bin/yakuake`.
After stowing the D-Bus service for the first time, log out or reload the bus.

---

## Boot themes (GRUB + Plymouth)

The GRUB theme **`nord`** (plus two alternative icon sets) and the Plymouth
animation **`cuts_alt`** are vendored in `boot/`: copies of their GPLv3 upstreams, byte-identical to them,
with their `LICENSE`, so a fresh machine never depends on those repos still
existing. Sources, commits and how the GRUB variant was built are in
[`boot/README.md`](boot/README.md). They're installed system-wide by
**`dev-boot`** (bootstrap menu option **14**), which finds `boot/` from its own
real path:

```bash
dev-boot                      # interactive menu (dialog)
dev-boot --all                # both keys, no prompts (keeps whatever was chosen before)
dev-boot --only=plymouth      # just one key
dev-boot --plymouth=liquid    # pick the animation: from boot/ or from the upstream repo
dev-boot --grub-icons=color   # GRUB icon set: white | color | whitesur
dev-boot --list-plymouth      # list every available Plymouth theme
dev-boot --dry-run            # print every sudo command it would run; changes nothing
dev-boot --doctor             # check what the next boot will actually show; changes nothing
```

The menu shows the current state (theme, icon set, whether it's up to date)
and has entries to apply everything, **pick the Plymouth animation**, **pick
the GRUB icon set** and run the doctor. Before anything runs with sudo it
shows a summary of what will change, computed by the same code in
`--dry-run`, with *Apply* / *Cancel*; `update-grub` and `update-initramfs`
output is shown in a dialog box. Simulating is a CLI flag like the rest:
`dev-boot --dry-run` (also in combination with the menu, which then only
shows the plans).

- **Plymouth animation**: the themes saved in `boot/plymouth/themes`
  (`cuts_alt`, the default), the ones already installed from upstream, and
  *View the upstream themes…*: the 80 themes of
  [adi1090x/plymouth-themes](https://github.com/adi1090x/plymouth-themes),
  pinned to the same commit as `cuts_alt`, with a name filter. Only the chosen
  theme's folder is downloaded (sparse git checkout, not the whole ~270 MB) and
  installed **on this machine only** — it is not added to the dotfiles. Before
  installing, it must be in upstream's list, contain no symlinks or special
  files, weigh under 50 MB, be a `script` theme whose `ImageDir`/`ScriptFile`
  point to its own folder, and it never overwrites a theme owned by a Debian
  package. It's marked with `.dev-boot-source` (repo, commit, path). The
  choice isn't stored anywhere else: it's `Theme=` in `plymouthd.conf`, so
  `--all` keeps it (and falls back to `cuts_alt` if it's a theme `dev-boot`
  doesn't know).
- **GRUB icons**: `white` (the default, inside the theme), `color` or
  `whitesur` (in `boot/grub/icons/`). The theme is assembled in a temp dir with
  the chosen set and marked with `.dev-boot-icons`.

| Key        | What it does |
| ---------- | ------------ |
| `grub`     | installs the theme (with the chosen icon set) to `/boot/grub/themes/nord` and writes **only** `/etc/default/grub.d/dev-boot.cfg` (`GRUB_THEME` + `GRUB_GFXMODE=1920x1080,auto`, which falls back to `auto` on other screens, and — when Plymouth is installed — `quiet splash` appended to the kernel command line). `/etc/default/grub` is never touched — it holds per-machine settings such as the kernel command line. `grub-mkconfig` reads `grub.d/*.cfg` after `/etc/default/grub`, so the drop-in wins. `update-grub` only runs when something changed; if it fails, the drop-in is restored (and `grub-mkconfig` validates `grub.cfg.new` before replacing the real one, so the bootable `grub.cfg` is never lost) |
| `plymouth` | installs the chosen theme to `/usr/share/plymouth/themes/<name>` and keeps Debian's layers consistent: **(1)** `Theme=` in `/etc/plymouth/plymouthd.conf` — the one that wins; only that line is edited, with a backup; **(2)** `/usr/share/plymouth/plymouthd.defaults` belongs to the package (desktop-base) and is left alone; **(3)** the `default.plymouth` alternative, registered at priority 100 as a fallback. `plymouth-set-default-theme` isn't used: it edits with `sed -ie` and leaves a stray `plymouthd.confe`. Since the theme lives **inside the initramfs**, `update-initramfs` runs when something changed or the current initrd lacks the theme, after checking free space (it builds `.new` and only swaps it in on success) |

Themes are installed atomically (copied next to the target, then swapped), and
every file `dev-boot` rewrites under `/etc` keeps a `*.dev-boot.bak` of its
previous version. Plymouth only shows with `splash` on the kernel command
line, and Debian only adds it when installed with a desktop, so the drop-in
appends `quiet` and `splash` to `GRUB_CMDLINE_LINUX_DEFAULT` when they're
missing — the machine's own options stay as they are, and deleting the drop-in
undoes it. Without GRUB or
Plymouth (VMs, Termux, servers) a key is skipped, and when there's nothing to
change `dev-boot` doesn't even ask for sudo. The doctor checks the effective
`GRUB_THEME`, the three Plymouth layers and whether the theme is actually
inside the initramfs — what the next boot will really show.

---

## Background services (systemd --user)

Jobs that run in the background live in `system/`, one folder per project,
and are installed as systemd `--user` units named `dotfiles-*` by
**`dev-services`** (bootstrap menu option **15**):

```
system/services/<name>/          always running
├── dotfiles-<name>.service
└── app/main                     what runs (any language, with a shebang)

system/timers/<name>/            run on a schedule
├── dotfiles-<name>.service      Type=oneshot: does the work and exits
├── dotfiles-<name>.timer        when (it triggers the .service)
└── app/main
```

```bash
dev-services                     # interactive menu (dialog)
dev-services --list              # every project: kind and state
dev-services --install=NAME      # install/update (comma-separated list)
dev-services --all               # install/update every project
dev-services --remove=NAME       # stop, disable and delete its units and app
dev-services --new=NAME [--timer]  # scaffold a project in the repo
dev-services --dry-run           # with --install/--all/--remove: print what it would do
dev-services --doctor            # repo vs installed; changes nothing
```

- A project brings its own units: nothing is generated at install time.
  `ExecStart` runs `%h/.local/lib/dotfiles-services/<name>/main`, so the units
  don't depend on where the repo is cloned. Projects are validated before
  installing (layout, names, `Type=oneshot` for timers, allowed `WantedBy=`).
- Installing **copies** `app/` to `~/.local/lib/dotfiles-services/<name>/`
  and the units to `~/.config/systemd/user/`; editing the repo never changes
  a running job until it's reinstalled (the doctor reports the drift). A
  service is enabled and started; for a timer only the `.timer` is enabled.
- It only touches `dotfiles-*` units and its own folder. It never enables
  lingering, edits `default.target` or writes drop-ins, so user units run
  while you're logged in; timers use `Persistent=true` to catch up a run
  missed while logged out.
- Projects with dependencies to install (`app/package.json`) aren't supported
  yet.

| Project              | Kind    | What it does |
| -------------------- | ------- | ------------ |
| `konsole-theme-sync` | service | follows Plasma's light/dark mode (freedesktop portal): sets the default profile of Yakuake and Konsole and recolors the open sessions live with OSC 50, without typing anything into them. Starts with the graphical session |

---

## Manual stow

If you prefer to skip the TUI and stow packages by hand:

```bash
cd ~/dotfiles
# Whole-folder packages (one symlink per package)
stow cava icons kitty nvim peaclock task templates tmux zsh
# Per-file packages (--no-folding: real directory + one symlink per file)
stow --no-folding bin konsole ssh zsh-completions
```

---

## What stays local (not tracked)

| File / path                     | Reason                       |
| ------------------------------- | ---------------------------- |
| `~/.ssh/config.local`           | Machine-specific SSH aliases |
| `~/.ssh/id_*`, `codecommit_rsa` | Private keys                 |
| Host-specific shell overrides   | Machine-specific environment |

---

## Notes

- Optimized for Debian-based machines.
- `stow` works best when each app lives in its own directory.
- Per-package stow strategy (whole-folder vs per-file) and how `system/` is
  handled outside of stow is documented in **Stow strategy** above.
- `bin/` only ever holds tools we actually maintain as dotfiles (`dev-*`,
  `tmux-theme-*`). Everything installed by a native installer (pipx, curl
  releases, the aws-cli installer, ...) lands in the *real*
  `~/.local/bin` and is invisible to git.
- Neovim, tmux, kitty, yazi, tree-sitter, tmuxp, pgcli, mycli, csvkit,
  peaclock and lavat are all installed/updated via **`dev-packages`**, not
  apt — see **Extra (non-apt) packages** above for how each one detects
  updates.
- The Timewarrior hook (`on-modify.timewarrior`) must be installed once per
  machine; the bootstrap handles it via option 8.
