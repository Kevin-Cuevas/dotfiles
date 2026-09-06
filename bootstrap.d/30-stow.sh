# bootstrap.d/30-stow.sh — stow strategy + systemd --user unit linking
# ==============================================================================
# stow_packages() (menu option 4) dispatches each package to
# stow_whole_folder() or stow_per_file() based on STOW_PER_FILE_PACKAGES —
# see the comment above that array for the whole-folder vs per-file
# rationale, also documented in README.md's "Stow strategy" section.
# link_systemd_units() runs at the end of stow_packages(): system/ is
# excluded from stow entirely, so this is the mechanism that actually links
# system/services/ and system/timers/ infra-*.service/.timer units into
# ~/.config/systemd/user and enables them.
# ==============================================================================

# ==============================================================================
# Stow strategy per package
# ==============================================================================
# Whole-folder packages (default): the target directory is 100% owned by the
# repo, so a single folded symlink is simplest — e.g. ~/.config/nvim is
# ENTIRELY our LazyVim config, so it becomes one symlink to
# dotfiles/nvim/.config/nvim. This is every package NOT listed below:
# cava, icons, kitty, nvim, peaclock, task, templates, tmux, zsh.
#
# Per-file packages: their target directory also receives files we do NOT
# track (new SSH keys, ControlMaster sockets in ~/.ssh, binaries dropped by
# pipx/curl in ~/.local/bin..., new Konsole profiles/colorschemes created
# from the GUI in ~/.local/share/konsole..., completion files dev-* CLIs
# generate for themselves on their own host — e.g. `dev-pagipage-domains
# --set-autocompletions` on nivek-core writes straight into
# ~/.zsh/completions). Folding these into one symlink would mean anything
# written there later lands physically inside ~/dotfiles instead of the
# real directory. These get --no-folding: a REAL target directory plus one
# symlink per tracked file, so only what we explicitly put in the package
# is managed — adding a new file to the package and re-running the stow
# step links just that file, it never re-folds the directory.
STOW_PER_FILE_PACKAGES=(bin konsole ssh zsh-completions)

# Explicit target directory for each per-file package (relative to $TARGET),
# so we can create it as a real directory ourselves before stowing — this
# matters on a from-scratch machine, e.g. ~/.ssh doesn't exist yet.
declare -A STOW_PER_FILE_TARGET=(
  [bin]=".local/bin"
  [konsole]=".local/share/konsole"
  [ssh]=".ssh"
  [zsh-completions]=".zsh/completions"
)

# Whole-folder packages: one symlink for the entire package directory.
stow_whole_folder() {
  stow --target="$TARGET" --dir="$DOTFILES_DIR" --restow "$1"
}

# Per-file packages: create the real target dir first, then stow with
# --no-folding so only tracked files get individually symlinked.
stow_per_file() {
  local pkg="$1"
  mkdir -p "$TARGET/${STOW_PER_FILE_TARGET[$pkg]}"
  stow --no-folding --target="$TARGET" --dir="$DOTFILES_DIR" --restow "$pkg"
}

stow_packages() {
  sep

  local pkgs=()
  for d in "$DOTFILES_DIR"/*/; do
    local name
    name="$(basename "$d")"
    [[ "$name" == "system" ]] && continue
    [[ "$name" == "bootstrap"* ]] && continue
    [[ "$name" == "."* ]] && continue
    pkgs+=("$name")
  done

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    warn "No stowable packages found."
    return
  fi

  local chosen=()

  if [[ "$NONINTERACTIVE" == "true" ]]; then
    chosen=("${pkgs[@]}")
    info "Non-interactive mode — stowing all ${#chosen[@]} package(s)"
  else
    local items=()
    for pkg in "${pkgs[@]}"; do
      items+=("$pkg" "" "on")
    done

    local list_height="${#pkgs[@]}"
    local win_height=$((list_height + 9))
    [[ $win_height -gt 22 ]] && win_height=22
    [[ $list_height -gt 14 ]] && list_height=14

    local raw
    raw=$(dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " Stow Packages " \
      --separate-output \
      --checklist \
      "Select packages to stow  [SPACE=toggle  ENTER=confirm]\n\nTarget: $TARGET\n\nNote: system/ is always excluded (use MOTD option instead)" \
      "$win_height" 64 "$list_height" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || {
      warn "Stow cancelled."
      return
    }

    clear   # wipe dialog remnants before stow logs

    while IFS= read -r item; do
      [[ -n "$item" ]] && chosen+=("$item")
    done <<< "$raw"

    if [[ ${#chosen[@]} -eq 0 ]]; then
      warn "No packages selected."
      return
    fi

  fi

  # En una máquina desde cero, ~/.config puede no existir todavía. Si el
  # primer paquete en tocarlo (p.ej. cava) lo encuentra ausente, el folding
  # normal de stow enlaza ~/.config ENTERO como un solo symlink hacia
  # dotfiles/cava/.config — y el siguiente paquete que use ~/.config (kitty,
  # nvim, task...) terminaría escribiendo sus archivos dentro del paquete de
  # cava. Pre-creamos ~/.config como carpeta real (es el único destino que
  # comparten varios paquetes "todo o nada") para que el folding de stow
  # solo pueda ocurrir al nivel de cada paquete individual
  # (~/.config/nvim, ~/.config/kitty, ...), nunca en la raíz compartida.
  mkdir -p "$HOME/.config"

  local stowed=0 conflicts=0 zsh_completions_stowed=false

  for pkg in "${chosen[@]}"; do
    local stow_err
    if [[ " ${STOW_PER_FILE_PACKAGES[*]} " == *" $pkg "* ]]; then
      stow_err=$(stow_per_file "$pkg" 2>&1)
    else
      stow_err=$(stow_whole_folder "$pkg" 2>&1)
    fi
    if [[ $? -eq 0 ]]; then
      ok "Stowed: $pkg"
      ((stowed++)) || true
      [[ "$pkg" == "zsh-completions" ]] && zsh_completions_stowed=true
    else
      warn "Conflict stowing $pkg:"
      echo "$stow_err" | sed 's/^/         /' >&2
      warn "Remove conflicting files or run stow manually to resolve."
      ((conflicts++)) || true
    fi
  done

  sep
  ok "Stow done — OK: $stowed  conflicts: $conflicts"

  # zsh caches the fpath scan in ~/.zcompdump and, per zsh/.zshrc, skips
  # rescanning it (compinit -C) if that dump was already rebuilt today — so
  # a completion file that just got linked here wouldn't be picked up until
  # tomorrow otherwise. Clearing it makes the very next shell start do a
  # full compinit rescan and see it immediately.
  if [[ "$zsh_completions_stowed" == true ]]; then
    rm -f "$TARGET/.zcompdump"*
    ok "Cleared cached zsh completions dump — next shell rebuilds it"
  fi

  link_systemd_units
}

# Enlaza las unidades systemd --user de system/services/ (servicios que
# corren de forma persistente) y system/timers/ (pares oneshot .service +
# .timer) hacia ~/.config/systemd/user, y las habilita. system/ está excluido
# de los paquetes de stow (ver stow_packages), así que este es el mecanismo
# que las pone a funcionar. Nomenclatura: todo archivo se llama infra-*.
link_systemd_units() {
  sep

  if [[ "$TEST_MODE" == true ]]; then
    skip "TEST MODE — no se tocan las unidades systemd reales"
    return
  fi

  if ! command -v systemctl &>/dev/null || ! systemctl --user show-environment &>/dev/null 2>&1; then
    skip "systemd --user no disponible — omitiendo unidades systemd"
    return
  fi

  local unit_dir="$TARGET/.config/systemd/user"
  mkdir -p "$unit_dir"

  local linked=0 f name
  for f in "$DOTFILES_DIR"/system/services/infra-*.service \
           "$DOTFILES_DIR"/system/timers/infra-*.service \
           "$DOTFILES_DIR"/system/timers/infra-*.timer; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f")"
    ln -sf "$f" "$unit_dir/$name"
    ok "Linked $name"
    ((linked++)) || true
  done

  if [[ $linked -eq 0 ]]; then
    skip "No hay unidades infra-* en system/services o system/timers."
    return
  fi

  systemctl --user daemon-reload

  # Servicios persistentes: se habilitan y arrancan directamente.
  for f in "$DOTFILES_DIR"/system/services/infra-*.service; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f")"
    if systemctl --user enable --now "$name" &>/dev/null; then
      ok "Enabled $name"
    else
      warn "No se pudo habilitar $name"
    fi
  done

  # Pares oneshot + timer: solo se habilita el .timer (él dispara al .service).
  for f in "$DOTFILES_DIR"/system/timers/infra-*.timer; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f")"
    if systemctl --user enable --now "$name" &>/dev/null; then
      ok "Enabled $name"
    else
      warn "No se pudo habilitar $name"
    fi
  done
}
