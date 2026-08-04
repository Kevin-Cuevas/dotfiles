# dotfiles

Portable dotfiles for Debian-based systems, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Each top-level directory is a Stow package that maps directly into `$HOME`.

---

## Quick start

From a fresh machine (only `git` and `curl` required):

```bash
curl -fsSL https://raw.githubusercontent.com/Kevin-Cuevas/dotfiles/main/install | bash
```

Or non-interactively (installs everything without prompts):

```bash
curl -fsSL https://raw.githubusercontent.com/Kevin-Cuevas/dotfiles/main/install | bash -s -- --all
```

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
├── bin/          -> ~/.local/bin          personal CLI tools and dev-* helpers
├── cava/         -> ~/.config/cava
├── icons/        -> ~/.local/share/...    cursor and icon themes
├── kitty/        -> ~/.config/kitty
├── konsole/      -> ~/.local/share/konsole yakuake profile + colorscheme
├── nvim/         -> ~/.config/nvim        LazyVim config
├── peaclock/     -> ~/.config/peaclock
├── ssh/          -> ~/.ssh/config         shared defaults only; hosts & keys stay local
├── system/                                MOTD and system-level scripts (not stowed)
├── task/         -> ~/.config/task
├── templates/    -> ~/templates
├── tmux/         -> ~/.config/tmux
├── zsh/          -> ~/                    .zshrc, .zshenv, and shell helpers
├── bootstrap                              interactive setup script
└── README.md
```

---

## Bootstrap

`bootstrap` is a standalone Bash script. It requires no dependencies beyond a
working Debian-based system, it will install `dialog` and `stow`
automatically if they are missing.

```bash
~/dotfiles/bootstrap
```

**Menu options:**

| #   | Action                                       |
| --- | -------------------------------------------- |
| 1   | Run everything (2 through 12)                |
| 2   | Install apt packages & extra packages        |
| 3   | Set permissions on `dev-*` scripts           |
| 4   | Stow packages into `$HOME`                   |
| 5   | Install Neovim via `dev-nvim`                |
| 6   | Install MOTD via `dev-motd`                  |
| 7   | Install Nerd Fonts (FiraCode + FiraMono)     |
| 8   | Set up Timewarrior hook for Taskwarrior      |
| 9   | Install TPM (Tmux Plugin Manager)            |
| 10  | Configure SSH (control dir + servers)        |
| 11  | Set zsh as default shell                     |
| 12  | Install language runtimes (rust, node, ...)  |

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
#@ group:tailnet:nivekcuevas.dev@gmail.com
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

```
git stow zsh wget curl tmux fzf ripgrep fd-find bat zoxide
taskwarrior timewarrior build-essential figlet wl-clipboard
direnv eza tmuxp unzip yakuake
```

---

## Manual stow

If you prefer to skip the TUI and stow packages by hand:

```bash
cd ~/dotfiles
stow bin cava icons kitty konsole nvim peaclock ssh task templates tmux zsh
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
- `system/` is intentionally excluded from stow — it contains MOTD scripts run
  as root that do not belong in `$HOME`.
- Neovim is managed via `dev-nvim` to stay on the upstream binary release
  rather than the distro package.
- The Timewarrior hook (`on-modify.timewarrior`) must be installed once per
  machine; the bootstrap handles it via option 7.
