# shellcheck shell=bash
# bootstrap.d/40-misc.sh — shell/permissions, dev-* launchers, fonts, TPM, TW hook
# ==============================================================================
# Small, mostly-independent menu-option implementations that don't warrant
# their own file: default-shell + dev-* script permissions, thin launchers
# for the standalone bin/.local/bin/dev-{packages,motd,ssh,plasma,boot} scripts, Nerd
# Fonts, the Timewarrior hook, and TPM. Named "misc", not "system", to avoid
# clashing with the repo's own system/ directory (MOTD + systemd units),
# which is a different, unrelated thing.
# ==============================================================================

set_default_shell() {
  sep
  local confirm=false
  [[ "${1:-}" == "confirm" ]] && confirm=true

  local zsh_path
  zsh_path="$(command -v zsh)" || {
    warn "zsh is not installed — skipping shell change"
    return 1
  }

  # chsh requires the shell to be listed in /etc/shells
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    info "Registering $zsh_path in /etc/shells..."
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  fi

  local current_shell
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$current_shell" == "$zsh_path" ]]; then
    skip "zsh is already the default shell ($zsh_path)"
    return
  fi

  # In an interactive "Run everything", confirm before changing the shell
  if [[ "$confirm" == true && "$NONINTERACTIVE" == false ]]; then
    if dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " Change default shell " \
      --yesno "Set zsh ($zsh_path) as your default shell?\n\nRuns: chsh -s $zsh_path $USER\nTakes effect on your next session." \
      10 64; then
      clear
    else
      clear
      skip "Shell change skipped by the user"
      return
    fi
  fi

  info "Setting zsh as the default shell..."
  if sudo chsh -s "$zsh_path" "$USER"; then
    ok "Default shell changed to $zsh_path (takes effect on your next session)"
  else
    warn "Couldn't change the shell — do it manually: chsh -s $zsh_path"
  fi
}

set_permissions() {
  sep
  info "Setting executable permissions on dev-* scripts..."
  local count=0

  while IFS= read -r -d '' script; do
    chmod +x "$script"
    ok "chmod +x $(basename "$script")"
    ((count++)) || true
  done < <(find "$DOTFILES_DIR/bin/.local/bin" -name "dev-*" -print0 2>/dev/null)

  if [[ $count -eq 0 ]]; then
    warn "No dev-* scripts found in bin/.local/bin/"
  else
    ok "$count script(s) made executable"
  fi
}

run_dev_packages() {
  sep
  local pkg_script="$DOTFILES_DIR/bin/.local/bin/dev-packages"
  [[ -f "$pkg_script" ]] || {
    err "dev-packages not found at $pkg_script"
    return 1
  }
  [[ -x "$pkg_script" ]] || chmod +x "$pkg_script"
  info "Launching dev-packages..."
  DEV_PACKAGES_BACKTITLE="$BACKTITLE" "$pkg_script"
}

run_dev_motd() {
  sep
  local motd_script="$DOTFILES_DIR/bin/.local/bin/dev-motd"
  [[ -f "$motd_script" ]] || {
    err "dev-motd not found at $motd_script"
    return 1
  }
  [[ -x "$motd_script" ]] || chmod +x "$motd_script"
  info "Launching dev-motd..."
  "$motd_script"
}

# dev-plasma exits on its own (with 0) when there's no KDE Plasma, so --all can
# call it on any machine. It runs after stow: the themes' cursor arrives with
# the icons/ package (the themes themselves are installed by dev-plasma from
# plasma/, which isn't stowed).
run_dev_plasma() {
  sep
  local plasma_script="$DOTFILES_DIR/bin/.local/bin/dev-plasma"
  [[ -f "$plasma_script" ]] || {
    err "dev-plasma not found at $plasma_script"
    return 1
  }
  [[ -x "$plasma_script" ]] || chmod +x "$plasma_script"
  info "Launching dev-plasma..."
  DEV_PLASMA_BACKTITLE="$BACKTITLE" "$plasma_script"
}

# dev-boot touches the boot process (GRUB + Plymouth, with sudo). Without GRUB
# or Plymouth it skips that part, so --all can call it on any machine; when
# there's nothing to change it doesn't ask for sudo.
run_dev_boot() {
  sep
  local boot_script="$DOTFILES_DIR/bin/.local/bin/dev-boot"
  [[ -f "$boot_script" ]] || {
    err "dev-boot not found at $boot_script"
    return 1
  }
  [[ -x "$boot_script" ]] || chmod +x "$boot_script"
  info "Launching dev-boot..."
  DEV_BOOT_BACKTITLE="$BACKTITLE" "$boot_script"
}

run_dev_ssh() {
  sep
  local ssh_script="$DOTFILES_DIR/bin/.local/bin/dev-ssh"
  [[ -f "$ssh_script" ]] || {
    err "dev-ssh not found at $ssh_script"
    return 1
  }
  [[ -x "$ssh_script" ]] || chmod +x "$ssh_script"
  info "Launching dev-ssh..."
  DEV_SSH_BACKTITLE="$BACKTITLE" "$ssh_script" --target="$TARGET" "$@"
}

install_fonts() {
  sep
  local font_dir="$HOME/.local/share/fonts"
  mkdir -p "$font_dir"
  local refreshed=false

  for font in FiraCode FiraMono; do
    if find "$font_dir" -maxdepth 1 -name "${font}*" | grep -q .; then
      skip "$font Nerd Font already installed"
      continue
    fi
    info "Downloading $font Nerd Font..."
    local tmp
    tmp="$(mktemp /tmp/${font}XXXXXX.zip)"
    if curl -fL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/${font}.zip" \
      -o "$tmp" 2>/dev/null; then
      unzip -o "$tmp" -d "$font_dir" &>/dev/null
      rm -f "$tmp"
      ok "$font Nerd Font installed"
      refreshed=true
    else
      rm -f "$tmp"
      warn "Failed to download $font Nerd Font"
    fi
  done

  if $refreshed; then
    info "Refreshing font cache..."
    if fc-cache -fv "$font_dir" &>/dev/null; then
      ok "Font cache updated"
    else
      warn "fc-cache failed"
    fi
  fi
}

setup_tw_hook() {
  sep
  local hook_src="/usr/share/doc/timewarrior/ext/on-modify.timewarrior"
  local hook_dir="$HOME/.task/hooks"
  local hook_dst="$hook_dir/on-modify.timewarrior"

  if [[ ! -f "$hook_src" ]]; then
    warn "Hook source not found: $hook_src (timewarrior may not be installed yet)"
    return 1
  fi
  if [[ -f "$hook_dst" ]]; then
    skip "Timewarrior hook already at $hook_dst"
    return
  fi
  mkdir -p "$hook_dir"
  cp "$hook_src" "$hook_dst"
  chmod +x "$hook_dst"
  ok "Timewarrior hook installed: $hook_dst"
}

install_tpm() {
  sep
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ -d "$tpm_dir" ]]; then
    skip "TPM already present at $tpm_dir"
    return
  fi
  info "Cloning TPM..."
  if git clone https://github.com/tmux-plugins/tpm "$tpm_dir" &>/dev/null; then
    ok "TPM installed at $tpm_dir"
  else
    warn "Failed to clone TPM — check network or git"
  fi
}
