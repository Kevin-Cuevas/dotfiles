# shellcheck shell=bash
# bootstrap.d/30-stow.sh — stow strategy
# ==============================================================================
# stow_packages() (menu option 4) dispatches each package to
# stow_whole_folder() or stow_per_file() based on STOW_PER_FILE_PACKAGES —
# see the comment above that array for the whole-folder vs per-file
# rationale, also documented in README.md's "Stow strategy" section.
# system/ is never stowed: its systemd --user jobs are installed by
# dev-services (menu option 15) and the MOTD by dev-motd.
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
  ["zsh-completions"]=".zsh/completions"
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
    # plasma/ isn't stowed either: Plasma reads Global Themes through KPackage,
    # which rejects files symlinked from outside the package folder. dev-plasma
    # installs them (kpackagetool6 + copies), menu 13.
    [[ "$name" == "plasma" ]] && continue
    # boot/ (GRUB and Plymouth themes) goes to root-owned paths: dev-boot installs it.
    [[ "$name" == "boot" ]] && continue
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
      "Select packages to stow  [SPACE=toggle  ENTER=confirm]\n\nTarget: $TARGET\n\nNote: system/, plasma/ and boot/ are always excluded (use the MOTD / dev-plasma / dev-boot options instead)" \
      "$win_height" 64 "$list_height" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || {
      warn "Stow cancelled."
      return
    }

    clear # wipe dialog remnants before stow logs

    while IFS= read -r item; do
      [[ -n "$item" ]] && chosen+=("$item")
    done <<<"$raw"

    if [[ ${#chosen[@]} -eq 0 ]]; then
      warn "No packages selected."
      return
    fi

  fi

  # On a from-scratch machine, ~/.config may not exist yet. If the first
  # package to touch it (e.g. cava) finds it missing, stow's normal folding
  # links the WHOLE ~/.config as a single symlink to dotfiles/cava/.config —
  # and the next package using ~/.config (kitty, nvim, task...) would end up
  # writing its files inside the cava package. We pre-create ~/.config as a
  # real directory (it's the only target shared by several "all or nothing"
  # packages) so stow's folding can only happen at each individual package's
  # level (~/.config/nvim, ~/.config/kitty, ...), never at the shared root.
  mkdir -p "$HOME/.config"

  local stowed=0 conflicts=0

  for pkg in "${chosen[@]}"; do
    local stow_err stow_fn=stow_whole_folder
    [[ " ${STOW_PER_FILE_PACKAGES[*]} " == *" $pkg "* ]] && stow_fn=stow_per_file
    if stow_err=$("$stow_fn" "$pkg" 2>&1); then
      ok "Stowed: $pkg"
      ((stowed++)) || true
    else
      warn "Conflict stowing $pkg:"
      printf '         %s\n' "${stow_err//$'\n'/$'\n'         }" >&2
      warn "Remove conflicting files or run stow manually to resolve."
      ((conflicts++)) || true
    fi
  done

  sep
  ok "Stow done — OK: $stowed  conflicts: $conflicts"

  # No need to touch ~/.zcompdump here: zsh/.zshrc only takes the compinit -C
  # fast path when the dump is newer than every file in ~/.zsh/completions, so
  # a completion just linked here is picked up on the next shell on its own.
}
