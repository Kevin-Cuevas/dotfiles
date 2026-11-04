# shellcheck shell=bash
# bootstrap.d/10-packages.sh — apt packages (menu option 2)
# ==============================================================================
# Plain apt packages only, in groups. Non-apt tools (nvim, tmux, kitty, yazi,
# peaclock, tmuxp, lavat) live in the standalone bin/.local/bin/dev-packages
# script (menu option 5) instead — see README.md's "Extra (non-apt) packages".
#
# To add an apt package: add it to APT_PKGS (listing order), APT_PKG_GROUP
# and APT_PKG_DESC. To add a group: APT_GROUP_ORDER + APT_GROUP_TITLE, and
# PROFILE_GROUPS for the profiles that should get it. A group left out of
# every profile is opt-in: only the menu checklist offers it.
#
# A package may not exist in every Debian release (plasma-login-manager is
# forky/sid only). Packages with no apt candidate are shown as "not in this
# release" and skipped, so they never break the single apt-get run.
#
# Profiles say which groups a kind of machine gets:
#   server  -> everything that makes sense over SSH (servers, the Termux VM)
#   desktop -> the same plus the desktop group (yakuake alone pulls ~870 KDE
#              packages: it has no place on a server)
# bootstrap picks one on its own (KDE Plasma installed -> desktop) unless
# --profile=desktop|server says otherwise. --all installs the profile's
# groups; the menu preselects them.
# ==============================================================================

APT_GROUP_ORDER=(core dev productivity desktop login)
declare -A APT_GROUP_TITLE=(
  [core]="Core: shell, stow and the CLI tools the dotfiles use"
  [dev]="Dev: compilers and build tools (dev-packages needs them)"
  [productivity]="Productivity: Taskwarrior + Timewarrior"
  [desktop]="Desktop: KDE/Wayland only"
  [login]="Login: Plasma Login Manager (opt-in, forky/sid only)"
)

declare -A PROFILE_GROUPS=(
  [server]="core dev productivity"
  [desktop]="core dev productivity desktop"
)

# Listing order (bash associative arrays have none).
APT_PKGS=(
  git stow zsh curl wget kitty-terminfo fzf ripgrep fd-find bat zoxide eza
  direnv zip unzip figlet toilet
  build-essential cmake libicu-dev golang pipx
  taskwarrior timewarrior
  yakuake wl-clipboard
  plasma-login-manager
)
declare -A APT_PKG_GROUP=(
  [git]=core [stow]=core [zsh]=core [curl]=core [wget]=core
  ["kitty-terminfo"]=core [fzf]=core [ripgrep]=core ["fd-find"]=core
  [bat]=core [zoxide]=core [eza]=core [direnv]=core [zip]=core [unzip]=core
  [figlet]=core [toilet]=core
  ["build-essential"]=dev [cmake]=dev ["libicu-dev"]=dev [golang]=dev
  [pipx]=dev
  [taskwarrior]=productivity [timewarrior]=productivity
  [yakuake]=desktop ["wl-clipboard"]=desktop
  ["plasma-login-manager"]=login
)
declare -A APT_PKG_DESC=(
  [git]="version control"
  [stow]="links the dotfiles packages into \$HOME"
  [zsh]="the shell"
  [curl]="downloads (installers, plugins)"
  [wget]="downloads"
  ["kitty-terminfo"]="kitty's terminfo (keys/colors over SSH)"
  [fzf]="fuzzy finder (fzf-tab, txl, sessionx)"
  [ripgrep]="fast grep (nvim pickers)"
  ["fd-find"]="fast find (nvim pickers, fzf)"
  [bat]="cat with syntax highlighting"
  [zoxide]="smarter cd"
  [eza]="ls replacement (aliases)"
  [direnv]="per-directory environment"
  [zip]="zip archives"
  [unzip]="unzip archives (Nerd Fonts, releases)"
  [figlet]="ASCII banners"
  [toilet]="hostname banner (MOTD, nvim dashboard)"
  ["build-essential"]="gcc/make (tmux build, nvim plugins)"
  [cmake]="builds nvim from source"
  ["libicu-dev"]="ICU headers (build dependency)"
  [golang]="Go toolchain"
  [pipx]="Python CLIs in their own venvs (tmuxp, pgcli...)"
  [taskwarrior]="task manager"
  [timewarrior]="time tracking (Taskwarrior hook)"
  [yakuake]="drop-down terminal (dev-plasma configures it)"
  ["wl-clipboard"]="Wayland clipboard (tmux copy)"
  ["plasma-login-manager"]="KDE's login screen (dev-plasma sets its cursor)"
)

# desktop when KDE Plasma is installed, server otherwise.
detect_profile() {
  if command -v plasmashell &>/dev/null; then echo desktop; else echo server; fi
}

# MACHINE_PROFILE comes from bootstrap's --profile=; empty means auto-detect.
apt_profile() {
  if [[ -n "${MACHINE_PROFILE:-}" ]]; then echo "$MACHINE_PROFILE"; else detect_profile; fi
}

# dpkg -s also succeeds for removed-but-not-purged packages (config-files).
apt_installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

# True when apt knows a version of the package in the current sources.
apt_available() {
  local cand
  cand="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  [[ -n "$cand" && "$cand" != "(none)" ]]
}

# Packages of a group, in listing order.
apt_group_pkgs() {
  local pkg
  for pkg in "${APT_PKGS[@]}"; do
    [[ "${APT_PKG_GROUP[$pkg]}" == "$1" ]] && echo "$pkg"
  done
}

# Appends every package of the given groups to the array named $1.
add_group_pkgs() {
  local -n _dst="$1"
  shift
  local group
  for group in "$@"; do
    mapfile -t -O "${#_dst[@]}" _dst < <(apt_group_pkgs "$group")
  done
}

# Group checklist, preselected with the profile's groups. Result in $1.
select_apt_groups() {
  local -n _groups="$1"
  local profile="$2" items=() group pkg n missing on source
  for group in "${APT_GROUP_ORDER[@]}"; do
    n=0 missing=0
    while IFS= read -r pkg; do
      ((n++)) || true
      apt_installed "$pkg" || ! apt_available "$pkg" || ((missing++)) || true
    done < <(apt_group_pkgs "$group")
    on=off
    [[ " ${PROFILE_GROUPS[$profile]} " == *" $group "* ]] && on=on
    items+=("$group" "${APT_GROUP_TITLE[$group]} ($n, $missing missing)" "$on")
  done
  source="auto-detected, --profile=desktop|server to override"
  [[ -n "${MACHINE_PROFILE:-}" ]] && source="--profile"
  local raw line
  raw=$(dialog --clear --backtitle "$BACKTITLE" --title " apt packages " \
    --separate-output --checklist \
    "Profile: $profile ($source)\n\nSelect the groups to install  [SPACE=toggle  ENTER=confirm]" \
    15 80 "${#APT_GROUP_ORDER[@]}" "${items[@]}" 3>&1 1>&2 2>&3) || return 1
  _groups=()
  while IFS= read -r line; do [[ -n "$line" ]] && _groups+=("$line"); done <<<"$raw"
}

# Package checklist of one group (all preselected, installed ones marked).
# Appends the picked packages to the array named $2.
select_apt_pkgs() {
  local group="$1"
  local -n _pkgs="$2"
  local items=() pkg mark
  while IFS= read -r pkg; do
    mark=""
    apt_installed "$pkg" && mark="  ✔ installed"
    apt_installed "$pkg" || apt_available "$pkg" || mark="  — not in this release"
    items+=("$pkg" "${APT_PKG_DESC[$pkg]}$mark" on)
  done < <(apt_group_pkgs "$group")
  local raw line h=$((${#items[@]} / 3))
  [[ $h -gt 14 ]] && h=14
  raw=$(dialog --clear --backtitle "$BACKTITLE" --title " $group " \
    --separate-output --checklist "${APT_GROUP_TITLE[$group]}\n[SPACE=toggle  ENTER=confirm]" \
    $((h + 8)) 80 "$h" "${items[@]}" 3>&1 1>&2 2>&3) || return 1
  while IFS= read -r line; do [[ -n "$line" ]] && _pkgs+=("$line"); done <<<"$raw"
}

install_packages() {
  sep
  local profile chosen=() groups=() group pkg
  profile="$(apt_profile)"

  if [[ "$NONINTERACTIVE" == "true" ]]; then
    read -ra groups <<<"${PROFILE_GROUPS[$profile]}"
    info "Profile $profile — apt groups: ${groups[*]}"
    add_group_pkgs chosen "${groups[@]}"
  else
    if ! select_apt_groups groups "$profile"; then
      clear
      warn "apt packages dialog cancelled — installing nothing."
      return 0
    fi
    if [[ ${#groups[@]} -gt 0 ]] && dialog --clear --backtitle "$BACKTITLE" \
      --title " apt packages " --defaultno --yesno \
      "Groups: ${groups[*]}\n\nPick individual packages inside those groups?\n(No = every package of the selected groups)" 10 64; then
      for group in "${groups[@]}"; do
        select_apt_pkgs "$group" chosen || {
          clear
          warn "apt packages dialog cancelled — installing nothing."
          return 0
        }
      done
    else
      add_group_pkgs chosen "${groups[@]}"
    fi
    clear
  fi

  if [[ ${#chosen[@]} -eq 0 ]]; then
    skip "No apt packages selected — skipping apt install."
    return
  fi

  local missing=()
  for pkg in "${chosen[@]}"; do
    apt_installed "$pkg" || missing+=("$pkg")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "All ${#chosen[@]} selected apt package(s) are already installed"
    return
  fi

  sep
  info "Updating package index..."
  sudo apt-get update -qq 2>/dev/null || warn "apt-get update failed — continuing anyway"

  # Drop what this release doesn't have: one unknown name fails the whole run.
  local installable=()
  for pkg in "${missing[@]}"; do
    if apt_available "$pkg"; then
      installable+=("$pkg")
    else
      skip "$pkg is not available in this Debian release"
    fi
  done
  missing=("${installable[@]}")
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "Nothing installable is missing"
    return
  fi

  # One apt run for everything (much faster than one per package). If it
  # fails, each package is retried alone to tell which one broke.
  info "Installing ${#missing[@]} package(s): ${missing[*]}"
  local failed=()
  # --all never opens dialogs: some packages ask debconf questions that -y
  # doesn't answer (plasma-login-manager asks which display manager to use),
  # so noninteractive keeps the current choice instead of hanging. The menu
  # lets debconf ask.
  local apt_env=()
  [[ "$NONINTERACTIVE" == "true" ]] && apt_env=(env DEBIAN_FRONTEND=noninteractive)
  if ! sudo "${apt_env[@]}" apt-get install -y "${missing[@]}"; then
    warn "apt-get failed as a whole — retrying package by package..."
    for pkg in "${missing[@]}"; do
      apt_installed "$pkg" && continue
      # Output is hidden here, so a question would hang unseen: never ask.
      sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" &>/dev/null || failed+=("$pkg")
    done
  fi

  sep
  ok "Done — installed: $((${#missing[@]} - ${#failed[@]}))  already there: $((${#chosen[@]} - ${#missing[@]}))  failed: ${#failed[@]}"
  if [[ ${#failed[@]} -gt 0 ]]; then
    warn "Packages that could not be installed: ${failed[*]}"
    warn "You may need to add extra apt repos or install them manually."
  fi
}
