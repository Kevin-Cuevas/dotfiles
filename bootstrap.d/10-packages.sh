# bootstrap.d/10-packages.sh — apt packages + non-apt "extra" packages
# ==============================================================================
# APT_PKGS + install_packages() handle menu option 2's apt half; EXTRA_KEYS/
# LABEL/FN + install_extra_packages() handle the non-apt half (checklist
# right after apt), dispatching to the individual installers below. To add
# an apt package, add it to APT_PKGS. To add a non-apt one, add its key to
# EXTRA_KEYS + a label/function entry in EXTRA_LABEL/EXTRA_FN, and define
# install_<name>() (or reuse an existing function like run_dev_nvim).
# ==============================================================================

APT_PKGS=(
  git
  stow
  zsh
  wget
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
  kitty-terminfo
  yakuake
)

# Paquetes "extra" que no vienen por apt (checklist justo después del de apt
# packages). Para agregar uno: añade su clave a EXTRA_KEYS y su etiqueta +
# función en los mapas, y define install_<algo>() (o reutiliza una función
# existente como run_dev_nvim).
EXTRA_KEYS=(nvim yazi peaclock tmuxp lavat)
declare -A EXTRA_LABEL=(
  [nvim]="Neovim (dev-nvim)"
  [yazi]="Yazi (file manager)"
  [peaclock]="Peaclock (terminal clock)"
  [tmuxp]="tmuxp (tmux session manager, via pipx)"
  [lavat]="lavat (terminal lava lamp)"
)
declare -A EXTRA_FN=(
  [nvim]="run_dev_nvim"
  [yazi]="install_yazi"
  [peaclock]="install_peaclock"
  [tmuxp]="install_tmuxp"
  [lavat]="install_lavat"
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
  else
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
  fi

  install_extra_packages
}

# Checklist de paquetes "extra" que no vienen por apt (nvim, yazi, ...). Se
# ejecuta siempre justo después de install_packages, como parte del mismo
# flujo de la opción 2 del menú.
install_extra_packages() {
  sep
  local chosen=()

  if [[ "$NONINTERACTIVE" == "true" ]]; then
    chosen=("${EXTRA_KEYS[@]}")
    info "Non-interactive mode — installing all ${#chosen[@]} extra package(s)"
  else
    local list_h=$((${#EXTRA_KEYS[@]} + 1))
    [[ $list_h -lt 6 ]] && list_h=6
    local win_h=$((list_h + 9))
    if ! checklist_select_or_all "extra packages" \
      "Select extra (non-apt) packages to install  [SPACE=toggle  ENTER=confirm]\n\nLeave everything unchecked and press ENTER to install ALL.\nCheck 'Skip' to install none." \
      "$win_h" 64 "$list_h" chosen EXTRA_KEYS EXTRA_LABEL; then
      warn "Extra packages dialog cancelled — installing nothing."
      chosen=()
    fi
  fi

  if [[ ${#chosen[@]} -eq 0 ]]; then
    skip "No extra packages selected."
    return
  fi

  local key
  for key in "${chosen[@]}"; do
    "${EXTRA_FN[$key]}" || warn "Install failed: ${EXTRA_LABEL[$key]}"
  done
}

# Installs/updates yazi (terminal file manager) from the official
# precompiled binary release — never builds from source. Downloads and
# extracts first so the new version can be read straight from the binary,
# then compares it against whatever's currently installed before touching
# ~/.local/bin: if it's the exact same version, ask before reinstalling
# (same UX as dev-nvim's version check), otherwise install right away.
install_yazi() {
  sep
  local arch triple
  arch="$(uname -m)"
  case "$arch" in
  x86_64) triple="x86_64-unknown-linux-gnu" ;;
  aarch64) triple="aarch64-unknown-linux-gnu" ;;
  *)
    warn "No official yazi binary for architecture '$arch' — skipping."
    return 1
    ;;
  esac

  command -v unzip &>/dev/null || {
    err "unzip not found — select it in the apt packages step or install it manually first."
    return 1
  }

  local current_version=""
  if command -v yazi &>/dev/null; then
    current_version="$(yazi --version 2>/dev/null | head -1)"
    info "Current yazi version: ${current_version:-unknown}"
  else
    info "yazi is not currently installed."
  fi

  local tmp
  tmp="$(mktemp -d)" || {
    err "Could not create temp dir for yazi download"
    return 1
  }
  # Note: do NOT use `trap ... RETURN` here. In bash, a RETURN trap set
  # inside this function isn't cleared just by returning: it stays armed
  # and fires again when the function that CALLED this one (e.g.
  # install_extra_packages, and from there run_all) also returns — at that
  # point "$tmp" no longer exists and, under `set -u`, referencing it kills
  # the ENTIRE script with "tmp: unbound variable". That's why "$tmp" is
  # cleaned up by hand at every exit point instead.

  local asset="yazi-${triple}.zip"
  local url="https://github.com/sxyazi/yazi/releases/latest/download/${asset}"

  info "Downloading $url ..."
  if ! curl -fL --progress-bar -o "$tmp/$asset" "$url"; then
    err "Failed to download $asset"
    rm -rf "$tmp"
    return 1
  fi

  info "Extracting..."
  if ! unzip -q -o "$tmp/$asset" -d "$tmp"; then
    err "Failed to extract $asset"
    rm -rf "$tmp"
    return 1
  fi

  local extracted_dir="$tmp/yazi-${triple}"
  if [[ ! -x "$extracted_dir/yazi" || ! -x "$extracted_dir/ya" ]]; then
    err "Expected yazi/ya binaries not found in $extracted_dir"
    rm -rf "$tmp"
    return 1
  fi

  local new_version
  new_version="$("$extracted_dir/yazi" --version 2>/dev/null | head -1)"

  if [[ -n "$current_version" && "$current_version" == "$new_version" ]]; then
    if [[ "$NONINTERACTIVE" == "true" ]]; then
      info "Non-interactive — reinstalling the same version ($new_version)."
    else
      if dialog \
          --clear --colors \
          --backtitle "$BACKTITLE" \
          --title " yazi " \
          --defaultno \
          --yesno "You already have $new_version installed.\n\nDownload and reinstall it anyway?" \
          9 64; then
        clear
      else
        clear
        skip "yazi reinstall skipped — already on $new_version"
        rm -rf "$tmp"
        return 0
      fi
    fi
  else
    info "Updating: ${current_version:-<none>} -> ${new_version:-<unknown>}"
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 755 "$extracted_dir/yazi" "$HOME/.local/bin/yazi"
  install -m 755 "$extracted_dir/ya" "$HOME/.local/bin/ya"
  rm -rf "$tmp"

  ok "Installed yazi + ya -> $HOME/.local/bin ($new_version)"
}

# Compila peaclock (reloj estético de terminal) desde fuente. No hay binario
# oficial precompilado. El repo NO tiene Makefile en la raíz — usa CMake a
# través de su propio wrapper ./RUNME.sh (build/install), y requiere ICU
# (libicu-dev) además de cmake/build-essential.
install_peaclock() {
  sep
  if command -v peaclock &>/dev/null; then
    skip "peaclock ya está instalado ($(command -v peaclock))"
    return
  fi

  command -v git &>/dev/null || {
    err "git no encontrado — selecciónalo en apt packages o instálalo manualmente."
    return 1
  }
  command -v cmake &>/dev/null || {
    err "cmake no encontrado — selecciónalo en apt packages o instálalo manualmente (sudo apt install cmake)."
    return 1
  }
  dpkg -s libicu-dev &>/dev/null || {
    err "Falta ICU — selecciona libicu-dev en apt packages o instálalo manualmente (sudo apt install libicu-dev)."
    return 1
  }

  local tmp
  tmp="$(mktemp -d)" || {
    err "No se pudo crear directorio temporal para peaclock"
    return 1
  }

  info "Clonando peaclock..."
  if ! git clone --depth=1 https://github.com/octobanana/peaclock "$tmp/peaclock" &>/dev/null; then
    err "Falló el clone de peaclock"
    rm -rf "$tmp"
    return 1
  fi

  info "Compilando peaclock (RUNME.sh build)..."
  if ! (cd "$tmp/peaclock" && ./RUNME.sh build --release) &>/dev/null; then
    err "Falló la compilación de peaclock"
    rm -rf "$tmp"
    return 1
  fi

  info "Instalando peaclock (RUNME.sh install)..."
  if ! (cd "$tmp/peaclock" && ./RUNME.sh install --release); then
    err "Falló la instalación de peaclock"
    rm -rf "$tmp"
    return 1
  fi

  rm -rf "$tmp"
  ok "peaclock instalado -> $(command -v peaclock)"
}

# Instala tmuxp (session manager de tmux) vía pipx, aislado en su propio venv
# en vez de vía apt/pip global — mismo criterio que usamos para herramientas
# de dev en Python.
install_tmuxp() {
  sep
  if command -v tmuxp &>/dev/null; then
    skip "tmuxp ya está instalado ($(command -v tmuxp))"
    return
  fi

  command -v pipx &>/dev/null || {
    err "pipx no encontrado — selecciónalo en apt packages o instálalo manualmente."
    return 1
  }

  info "Instalando tmuxp vía pipx..."
  if ! pipx install tmuxp &>/dev/null; then
    err "Falló 'pipx install tmuxp'"
    return 1
  fi

  ok "tmuxp instalado vía pipx -> $HOME/.local/bin/tmuxp"
}

# Compila lavat (lava lamp de terminal) desde fuente — no publica binarios
# precompilados, solo "git clone && make && sudo make install".
install_lavat() {
  sep
  if command -v lavat &>/dev/null; then
    skip "lavat ya está instalado ($(command -v lavat))"
    return
  fi

  command -v git &>/dev/null || {
    err "git no encontrado — selecciónalo en apt packages o instálalo manualmente."
    return 1
  }

  local tmp
  tmp="$(mktemp -d)" || {
    err "No se pudo crear directorio temporal para lavat"
    return 1
  }

  info "Clonando lavat..."
  if ! git clone --depth=1 https://github.com/AngelJumbo/lavat "$tmp/lavat" &>/dev/null; then
    err "Falló el clone de lavat"
    rm -rf "$tmp"
    return 1
  fi

  info "Compilando lavat (make)..."
  if ! (cd "$tmp/lavat" && make) &>/dev/null; then
    err "Falló la compilación de lavat"
    rm -rf "$tmp"
    return 1
  fi

  info "Instalando lavat (sudo make install)..."
  if ! (cd "$tmp/lavat" && sudo make install) &>/dev/null; then
    err "Falló 'sudo make install' de lavat"
    rm -rf "$tmp"
    return 1
  fi

  rm -rf "$tmp"
  ok "lavat instalado -> $(command -v lavat)"
}
