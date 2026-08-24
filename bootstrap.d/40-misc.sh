# bootstrap.d/40-misc.sh — shell/permissions, dev-* launchers, fonts, TPM, TW hook
# ==============================================================================
# Small, mostly-independent menu-option implementations that don't warrant
# their own file: default-shell + dev-* script permissions, thin launchers
# for the standalone bin/.local/bin/dev-{packages,motd,ssh} scripts, Nerd
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
    warn "zsh no está instalado — omitiendo cambio de shell"
    return 1
  }

  # chsh exige que el shell esté listado en /etc/shells
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    info "Registrando $zsh_path en /etc/shells..."
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  fi

  local current_shell
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$current_shell" == "$zsh_path" ]]; then
    skip "zsh ya es el shell por defecto ($zsh_path)"
    return
  fi

  # En Run everything interactivo, confirmar antes de cambiar el shell
  if [[ "$confirm" == true && "$NONINTERACTIVE" == false ]]; then
    if dialog \
        --clear --colors \
        --backtitle "$BACKTITLE" \
        --title " Cambiar shell por defecto " \
        --yesno "¿Establecer zsh ($zsh_path) como tu shell por defecto?\n\nEjecuta: chsh -s $zsh_path $USER\nEfectivo en la próxima sesión." \
        10 64; then
      clear
    else
      clear
      skip "Cambio de shell omitido por el usuario"
      return
    fi
  fi

  info "Estableciendo zsh como shell por defecto..."
  if sudo chsh -s "$zsh_path" "$USER"; then
    ok "Shell por defecto cambiado a $zsh_path (efectivo en la próxima sesión)"
  else
    warn "No se pudo cambiar el shell — hazlo manualmente: chsh -s $zsh_path"
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
    local tmp; tmp="$(mktemp /tmp/${font}XXXXXX.zip)"
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
    fc-cache -fv "$font_dir" &>/dev/null && ok "Font cache updated" || warn "fc-cache failed"
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
