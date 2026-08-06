# bootstrap.d/20-runtimes.sh — language runtimes (rust, node, deno, bun)
# ==============================================================================
# RUNTIME_KEYS/LABEL/FN + install_runtimes() drive menu option 12's
# checklist; NPM_GLOBAL_KEYS/LABEL/PKG feed install_node_globals(), offered
# right after Node installs. To add a runtime: add its key to RUNTIME_KEYS +
# a label/function entry in RUNTIME_LABEL/RUNTIME_FN, and define
# install_<name>().
# ==============================================================================

# Lenguajes/runtimes que NO vienen por apt. Para agregar uno: añade su clave a
# RUNTIME_KEYS y su etiqueta + función en los mapas, y define install_<algo>().
RUNTIME_KEYS=(rust node deno bun)
declare -A RUNTIME_LABEL=(
  [rust]="Rust (rustup)"
  [node]="Node LTS (fnm)"
  [deno]="Deno"
  [bun]="Bun"
)
declare -A RUNTIME_FN=(
  [rust]="install_rust"
  [node]="install_node"
  [deno]="install_deno"
  [bun]="install_bun"
)

# Paquetes npm globales que se ofrecen tras instalar Node (checklist).
# Para agregar uno: añade su clave aquí y su etiqueta + spec npm en los mapas.
NPM_GLOBAL_KEYS=(live-server commitizen angular)
declare -A NPM_GLOBAL_LABEL=(
  [live-server]="live-server"
  [commitizen]="commitizen"
  [angular]="Angular CLI"
)
declare -A NPM_GLOBAL_PKG=(
  [live-server]="live-server"
  [commitizen]="commitizen cz-conventional-changelog"
  [angular]="@angular/cli"
)

install_node() {
  sep
  local fnm_dir="$HOME/.local/share/fnm"

  # Node por apt choca con fnm (binario en PATH del sistema). Lo purgamos antes.
  if dpkg -s nodejs &>/dev/null; then
    warn "nodejs instalado vía apt — desinstalando para usar fnm..."
    if sudo apt-get remove --purge -y nodejs npm &>/dev/null; then
      sudo apt-get autoremove -y &>/dev/null || true
      ok "nodejs/npm de apt eliminados"
    else
      warn "No se pudo desinstalar nodejs de apt — continúa, pero fnm puede chocar en PATH"
    fi
  fi

  if command -v fnm &>/dev/null || [[ -x "$fnm_dir/fnm" ]]; then
    skip "fnm already installed"
  else
    info "Installing fnm..."
    if curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "$fnm_dir" &>/dev/null; then
      ok "fnm installed at $fnm_dir"
    else
      warn "Failed to install fnm — check network/curl"
      return 1
    fi
  fi

  # Disponible en esta sesión (no tocamos el shell; el .zshrc ya maneja fnm)
  export PATH="$fnm_dir:$PATH"
  command -v fnm &>/dev/null || {
    warn "fnm no quedó en PATH tras instalar"
    return 1
  }
  eval "$(fnm env)" 2>/dev/null || true

  # Versiones de Node ya instaladas con fnm (excluye 'system').
  local installed_versions=() v
  while IFS= read -r v; do
    [[ -n "$v" ]] && installed_versions+=("$v")
  done < <(fnm list 2>/dev/null | awk '$2 ~ /^v[0-9]/ {print $2}')

  local action="lts" # por defecto: instalar el LTS más reciente

  # Solo preguntamos si es interactivo Y ya hay versiones instaladas.
  if [[ "$NONINTERACTIVE" == false && ${#installed_versions[@]} -gt 0 ]]; then
    local menu_items=("lts" "Instalar el Node LTS más reciente (fnm install --lts)")
    for v in "${installed_versions[@]}"; do
      menu_items+=("$v" "Usar esta versión ya instalada (fnm default $v)")
    done
    local lh=$((${#installed_versions[@]} + 1))
    [[ $lh -gt 10 ]] && lh=10
    local wh=$((lh + 9))
    action=$(dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " Node.js (fnm) " \
      --menu "Ya hay versiones de Node instaladas con fnm.\n\n¿Usar una versión existente o instalar el LTS más reciente?" \
      "$wh" 70 "$lh" \
      "${menu_items[@]}" \
      3>&1 1>&2 2>&3) || action="lts" # cancelar = LTS por defecto
    clear
  fi

  local node_alias=""
  if [[ "$action" == "lts" ]]; then
    info "Installing Node.js LTS via fnm..."
    if fnm install --lts; then
      fnm default lts-latest &>/dev/null || true # nuevas shells usan LTS por defecto
      ok "Node.js LTS installed ($(fnm exec --using=lts-latest node -v 2>/dev/null))"
      node_alias="lts-latest"
    else
      warn "fnm install --lts failed — check output above"
      return 1
    fi
  else
    info "Estableciendo Node $action como versión por defecto..."
    fnm default "$action" &>/dev/null || true
    ok "Node por defecto: $action ($(fnm exec --using="$action" node -v 2>/dev/null))"
    node_alias="$action"
  fi

  install_node_globals "$node_alias"
}

# Ofrece instalar paquetes npm globales sobre la versión de Node $1 (alias de
# fnm: lts-latest o vXX...). En modo no interactivo instala todos; interactivo
# muestra un checklist (todo desmarcado).
install_node_globals() {
  local using="$1"
  local chosen=()

  if [[ "$NONINTERACTIVE" == "true" ]]; then
    chosen=("${NPM_GLOBAL_KEYS[@]}")
    info "Non-interactive mode — installing all ${#chosen[@]} global npm package(s)"
  else
    local items=() key
    for key in "${NPM_GLOBAL_KEYS[@]}"; do
      items+=("$key" "${NPM_GLOBAL_LABEL[$key]}" "off")
    done

    local lh="${#NPM_GLOBAL_KEYS[@]}"
    [[ $lh -lt 5 ]] && lh=5
    local wh=$((lh + 9))

    local raw
    raw=$(dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " npm global packages " \
      --separate-output \
      --checklist \
      "¿Instalar paquetes npm globales?  [SPACE=toggle  ENTER=confirm]\n\nSe instalan con 'npm install -g' sobre Node $using." \
      "$wh" 64 "$lh" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || {
      warn "Global npm packages skipped."
      return
    }

    clear # limpiar restos del diálogo antes de los logs

    while IFS= read -r key; do
      [[ -n "$key" ]] && chosen+=("$key")
    done <<< "$raw"

    if [[ ${#chosen[@]} -eq 0 ]]; then
      skip "No global npm packages selected."
      return
    fi
  fi

  local key pkg sub all_present
  for key in "${chosen[@]}"; do
    pkg="${NPM_GLOBAL_PKG[$key]}"

    all_present=true
    for sub in $pkg; do
      fnm exec --using="$using" npm ls -g --depth=0 "$sub" &>/dev/null || all_present=false
    done

    if [[ "$all_present" == true ]]; then
      skip "$pkg already installed globally"
    else
      info "npm install -g $pkg ..."
      if fnm exec --using="$using" npm install -g $pkg &>/dev/null; then
        ok "Installed global: $pkg"
      else
        warn "Failed to install global: $pkg"
      fi
    fi

    [[ "$key" == "commitizen" ]] && write_czrc
  done
}

# Escribe ~/.czrc para que 'git cz' use cz-conventional-changelog. Se llama
# siempre que el usuario elija instalar commitizen, sin importar si el
# 'npm install -g' de arriba se ejecutó, falló, o se saltó por ya-instalado.
write_czrc() {
  echo '{ "path": "cz-conventional-changelog" }' > "$HOME/.czrc"
  ok "Wrote $HOME/.czrc"
}

install_rust() {
  sep
  if command -v rustc &>/dev/null || [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    skip "Rust already installed"
    return
  fi

  info "Installing Rust (rustup)..."
  # --no-modify-path: el .zshrc ya agrega ~/.cargo/bin; -y: no interactivo
  if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
    ok "Rust installed ($("$HOME/.cargo/bin/rustc" --version 2>/dev/null))"
  else
    warn "Failed to install Rust — check network/curl"
    return 1
  fi
}

install_deno() {
  sep
  if command -v deno &>/dev/null || [[ -x "$HOME/.deno/bin/deno" ]]; then
    skip "Deno already installed"
    return
  fi

  info "Installing Deno..."
  # -y: no interactivo; --no-modify-path: el .zshrc ya sourcea ~/.deno/env
  if curl -fsSL https://deno.land/install.sh | sh -s -- -y --no-modify-path &>/dev/null; then
    ok "Deno installed ($("$HOME/.deno/bin/deno" --version 2>/dev/null | head -1))"
  else
    warn "Failed to install Deno — check network/curl"
    return 1
  fi
}

install_bun() {
  sep
  if command -v bun &>/dev/null || [[ -x "$HOME/.bun/bin/bun" ]]; then
    skip "Bun already installed"
    return
  fi

  info "Installing Bun..."
  # El instalador de bun no tiene flag para no tocar el rc, y ~/.zshrc es un
  # symlink al repo (stow). Lo protegemos quitándole permiso de escritura: bun ve
  # que no es escribible e imprime instrucciones en vez de modificar el archivo
  # (el .zshrc ya maneja bun de todos modos). Restauramos los permisos al final.
  local rc="$HOME/.zshrc" rc_mode=""
  if [[ -e "$rc" ]]; then
    rc_mode="$(stat -c '%a' "$rc" 2>/dev/null)"
    chmod a-w "$rc" 2>/dev/null || true
  fi

  local rc_result=0
  curl -fsSL https://bun.sh/install | bash &>/dev/null || rc_result=$?

  [[ -n "$rc_mode" ]] && chmod "$rc_mode" "$rc" 2>/dev/null || true

  if [[ $rc_result -eq 0 ]]; then
    ok "Bun installed ($("$HOME/.bun/bin/bun" --version 2>/dev/null))"
  else
    warn "Failed to install Bun — check network/curl"
    return 1
  fi
}

# Menú/checklist de runtimes que no usan apt (rust, node, ...). En modo no
# interactivo instala todos; interactivo muestra un checklist (todo marcado).
install_runtimes() {
  sep

  local chosen=()

  if [[ "$NONINTERACTIVE" == "true" ]]; then
    chosen=("${RUNTIME_KEYS[@]}")
    info "Non-interactive mode — installing all ${#chosen[@]} runtime(s)"
  else
    local items=() key
    for key in "${RUNTIME_KEYS[@]}"; do
      items+=("$key" "${RUNTIME_LABEL[$key]}" "on")
    done

    # Mínimo de filas para que el cuadro no se vea apretado (como el de stow),
    # aunque haya pocos runtimes.
    local list_height="${#RUNTIME_KEYS[@]}"
    [[ $list_height -lt 6 ]] && list_height=6
    local win_height=$((list_height + 9))

    local raw
    raw=$(dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " Language Runtimes " \
      --separate-output \
      --checklist \
      "Select language runtimes to install  [SPACE=toggle  ENTER=confirm]\n\nInstaladores que NO usan apt (rustup, fnm, ...)." \
      "$win_height" 64 "$list_height" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || {
      warn "Runtime install cancelled."
      return
    }

    clear # limpiar restos del diálogo antes de los logs

    while IFS= read -r item; do
      [[ -n "$item" ]] && chosen+=("$item")
    done <<< "$raw"

    if [[ ${#chosen[@]} -eq 0 ]]; then
      warn "No runtimes selected."
      return
    fi
  fi

  local key
  for key in "${chosen[@]}"; do
    "${RUNTIME_FN[$key]}" || warn "Install failed: ${RUNTIME_LABEL[$key]}"
  done
}
