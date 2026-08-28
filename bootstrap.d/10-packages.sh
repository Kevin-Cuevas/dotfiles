# bootstrap.d/10-packages.sh — apt packages (menu option 2)
# ==============================================================================
# APT_PKGS + install_packages() handle menu option 2 — plain apt packages
# only. Non-apt tools (nvim, kitty, yazi, peaclock, tmuxp, lavat) live in the
# standalone bin/.local/bin/dev-packages script (menu option 5, see
# run_dev_packages in 40-misc.sh) instead of being hardcoded here — see
# README.md's "Extra (non-apt) packages" section. To add an apt package, add
# it to APT_PKGS; to add a non-apt one, edit dev-packages directly.
# ==============================================================================

APT_PKGS=(
  git
  stow
  zsh
  wget
  kitty-terminfo
  curl
  tmux
  fzf
  ripgrep
  fd-find
  bat
  zoxide
  taskwarrior
  timewarrior
  build-essential
  cmake
  libicu-dev
  golang
  figlet
  toilet
  wl-clipboard
  direnv
  eza
  pipx
  unzip
)

install_packages() {
  sep
  local chosen=()

  if [[ "$NONINTERACTIVE" == "true" ]]; then
    chosen=("${APT_PKGS[@]}")
    info "Non-interactive mode — installing all ${#chosen[@]} apt package(s)"
  else
    local list_h=$((${#APT_PKGS[@]} + 1))
    [[ $list_h -gt 12 ]] && list_h=12
    local win_h=$((list_h + 9))
    if ! checklist_select_or_all "apt packages" \
      "Select apt packages to install  [SPACE=toggle  ENTER=confirm]\n\nLeave everything unchecked and press ENTER to install ALL packages.\nCheck 'Skip' to install none." \
      "$win_h" 64 "$list_h" chosen APT_PKGS; then
      warn "apt packages dialog cancelled — installing nothing."
      chosen=()
    fi
  fi

  if [[ ${#chosen[@]} -eq 0 ]]; then
    skip "No apt packages selected — skipping apt install."
    return
  fi

  sep
  info "Updating package index..."
  sudo apt-get update -qq 2>/dev/null || warn "apt-get update failed — continuing anyway"

  local installed=0 skipped=0 failed=()

  for pkg in "${chosen[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
      skip "$pkg"
      ((skipped++)) || true
    else
      info "Installing $pkg..."
      if sudo apt-get install -y "$pkg" &>/dev/null; then
        ok "$pkg"
        ((installed++)) || true
      else
        warn "Could not install $pkg (not available or dependency error)"
        failed+=("$pkg")
      fi
    fi
  done

  sep
  ok "Done — installed: $installed  skipped: $skipped  failed: ${#failed[@]}"

  if [[ ${#failed[@]} -gt 0 ]]; then
    warn "Packages that could not be installed: ${failed[*]}"
    warn "You may need to add extra apt repos or install them manually."
  fi
}
