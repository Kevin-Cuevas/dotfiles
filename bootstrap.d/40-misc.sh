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

# dev-services installs the dotfiles' systemd --user jobs (system/services,
# system/timers). Opt-in like the themes: it opens its own menu, and
# bootstrap --all doesn't call it.
run_dev_services() {
  sep
  local services_script="$DOTFILES_DIR/bin/.local/bin/dev-services"
  [[ -f "$services_script" ]] || {
    err "dev-services not found at $services_script"
    return 1
  }
  [[ -x "$services_script" ]] || chmod +x "$services_script"
  info "Launching dev-services..."
  DEV_SERVICES_BACKTITLE="$BACKTITLE" "$services_script"
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

# Nerd Fonts self-update. The installed version is read from the font file
# itself (the name table carries "Nerd Fonts X.Y.Z"), not from a state file:
# fonts installed by hand or by an older run are picked up as-is and nothing
# can drift. The latest tag comes from the releases/latest redirect, which
# isn't rate-limited like the API. Offline, installed fonts are left alone and
# a missing one falls back to NERD_FONTS_FALLBACK.
NERD_FONTS=(FiraCode FiraMono)
NERD_FONTS_FALLBACK="3.5.1"
NERD_FONTS_URL="https://github.com/ryanoasis/nerd-fonts/releases"

# Prints the installed version of one family, or nothing if it's missing.
# FiraCode ships .ttf and FiraMono .otf, so both extensions are checked.
nerd_font_version() {
  local font_dir="$1" font="$2" f
  for f in "$font_dir/${font}NerdFont-Regular".{ttf,otf}; do
    [[ -f "$f" ]] || continue
    grep -a -o -m1 'Nerd Fonts [0-9][0-9.]*' "$f" | head -1 | awk '{print $3}'
    return
  done
}

nerd_fonts_latest() {
  curl -fsSI --max-time 10 "$NERD_FONTS_URL/latest" 2>/dev/null \
    | tr -d '\r' | sed -n 's|^[Ll]ocation: .*/tag/v\([0-9][0-9.]*\)$|\1|p'
}

# True if $1 is strictly newer than $2 (never downgrades).
version_gt() {
  [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

# Runs in a subshell so the EXIT trap cleans the download dir without
# clobbering a trap of the caller (run_all calls this directly).
install_fonts() (
  sep
  local font_dir="$HOME/.local/share/fonts"
  mkdir -p "$font_dir"
  local refreshed=false

  for cmd in curl unzip sha256sum; do
    command -v "$cmd" &>/dev/null || {
      warn "$cmd not found — skipping Nerd Fonts"
      return 1
    }
  done

  local latest
  latest="$(nerd_fonts_latest)"
  [[ -z "$latest" ]] && warn "Couldn't reach GitHub for the latest Nerd Fonts release"

  local work
  work="$(mktemp -d)" || return 1
  trap 'rm -rf "$work"' EXIT

  local sums_version="" font installed version
  for font in "${NERD_FONTS[@]}"; do
    installed="$(nerd_font_version "$font_dir" "$font")"
    if [[ -n "$installed" ]]; then
      if [[ -z "$latest" ]]; then
        skip "$font Nerd Font $installed (kept: latest version unknown)"
        continue
      fi
      if ! version_gt "$latest" "$installed"; then
        skip "$font Nerd Font $installed is up to date"
        continue
      fi
      version="$latest"
      info "Updating $font Nerd Font $installed -> $version..."
    else
      version="${latest:-$NERD_FONTS_FALLBACK}"
      info "Installing $font Nerd Font $version..."
    fi

    # One checksum file per release; fetched once, only when something is due.
    if [[ "$sums_version" != "$version" ]]; then
      if ! curl -fsSL "$NERD_FONTS_URL/download/v$version/SHA-256.txt" -o "$work/sums" 2>/dev/null; then
        warn "Failed to download the Nerd Fonts $version checksums — skipping $font"
        continue
      fi
      sums_version="$version"
    fi

    local zip="$work/$font.zip" stage="$work/$font"
    if ! curl -fsSL "$NERD_FONTS_URL/download/v$version/$font.zip" -o "$zip" 2>/dev/null; then
      warn "Failed to download $font Nerd Font $version"
      continue
    fi
    local want got
    want="$(awk -v f="$font.zip" '$2 == f {print $1}' "$work/sums")"
    got="$(sha256sum "$zip" | awk '{print $1}')"
    if [[ -z "$want" || "$want" != "$got" ]]; then
      warn "$font.zip checksum mismatch — nothing changed"
      continue
    fi
    # Unpacked whole (filtering by '*.ttf' '*.otf' makes unzip fail when one
    # extension is absent); only the font files are moved below. The zip also
    # carries LICENSE and README.md, which older runs dumped loose into the
    # fonts dir.
    mkdir -p "$stage"
    if ! unzip -oq "$zip" -d "$stage" 2>/dev/null \
      || ! compgen -G "$stage/${font}NerdFont*" >/dev/null; then
      warn "$font.zip has no ${font}NerdFont files — nothing changed"
      continue
    fi
    # Old files are removed only once the new set is verified and unpacked, so
    # a failure anywhere above leaves the previous version intact. The glob is
    # per family: other Nerd Fonts in the dir are never touched.
    rm -f "$font_dir/${font}NerdFont"*.{ttf,otf}
    mv "$stage/${font}NerdFont"* "$font_dir/"
    ok "$font Nerd Font $version installed"
    refreshed=true
  done

  # Leftovers of the old full-zip unzip; removed only if they're the Nerd
  # Fonts readme / the Fira OFL text, never a file someone else put there.
  local f
  for f in "$font_dir"/readme.md "$font_dir"/README.md; do
    [[ -f "$f" ]] && head -3 "$f" | grep -qx '# Nerd Fonts' && rm -f "$f"
  done
  f="$font_dir/LICENSE"
  [[ -f "$f" ]] && grep -q "The Mozilla Foundation and Telefonica" "$f" && rm -f "$f"

  if $refreshed; then
    info "Refreshing font cache..."
    if fc-cache -f "$font_dir" &>/dev/null; then
      ok "Font cache updated — restart open terminals (kitty, Konsole, Yakuake) to pick it up"
    else
      warn "fc-cache failed"
    fi
  fi
)

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
