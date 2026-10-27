# bootstrap.d/20-runtimes.sh — language runtimes (rust, node, deno, bun, java)
# ==============================================================================
# RUNTIME_KEYS/LABEL/FN + install_runtimes() drive menu option 12's
# checklist; NPM_GLOBAL_KEYS/LABEL/PKG feed install_node_globals(), offered
# right after Node installs; install_java_jdks() does the same for JDKs right
# after SDKMAN installs. To add a runtime: add its key to RUNTIME_KEYS +
# a label/function entry in RUNTIME_LABEL/RUNTIME_FN, and define
# install_<name>().
# ==============================================================================

# Lenguajes/runtimes que NO vienen por apt. Para agregar uno: añade su clave a
# RUNTIME_KEYS y su etiqueta + función en los mapas, y define install_<algo>().
RUNTIME_KEYS=(rust node deno bun java)
declare -A RUNTIME_LABEL=(
  [rust]="Rust (rustup)"
  [node]="Node LTS (fnm)"
  [deno]="Deno"
  [bun]="Bun"
  [java]="Java JDKs (SDKMAN)"
)
declare -A RUNTIME_FN=(
  [rust]="install_rust"
  [node]="install_node"
  [deno]="install_deno"
  [bun]="install_bun"
  [java]="install_java"
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

# Distribuciones de JDK que usa install_java_jdks(), en orden de preferencia
# (sufijos de SDKMAN: tem = Eclipse Temurin, amzn = Corretto, zulu, librca =
# Liberica). Si un build no arranca en esta máquina (p. ej. Temurin 17 en la VM
# aarch64 de Android) se prueba la siguiente. Las versiones salen de
# 'sdk list java', así que el checklist trae la mayor más reciente sin tocar
# este archivo.
JDK_DISTS=(tem amzn zulu librca)

# 'sdk' es una función de shell, no un binario: hay que sourcear el init en
# este proceso. El init y sdk usan variables sin definir, y el bootstrap corre
# con 'set -u', así que lo apagamos solo mientras se ejecutan.
sdkman_load() {
  set +u
  # shellcheck source=/dev/null
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  local rc=$?
  set -u
  return $rc
}

sdk_run() {
  set +u
  sdk "$@"
  local rc=$?
  set -u
  return $rc
}

install_java() {
  sep
  export SDKMAN_DIR="$HOME/.sdkman"

  if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
    skip "SDKMAN already installed"
  else
    # El instalador exige zip/unzip (vienen en APT_PKGS).
    local dep
    for dep in curl zip unzip; do
      command -v "$dep" &>/dev/null || {
        warn "SDKMAN necesita '$dep' — instálalo (opción 2) y vuelve a intentar"
        return 1
      }
    done

    info "Installing SDKMAN..."
    # rcupdate=false: no toca ~/.zshrc (symlink al repo), el .zshrc ya lo carga
    if curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash &>/dev/null; then
      ok "SDKMAN installed at $SDKMAN_DIR"
    else
      warn "Failed to install SDKMAN — check network/curl"
      return 1
    fi
  fi

  sdkman_load || {
    warn "No se pudo cargar sdkman-init.sh"
    return 1
  }

  install_java_jdks
}

# Smoke test de un JDK ($1 = su home): compila y ejecuta una clase. Un JDK
# "instalado" no es uno que arranca: hay builds que mueren con SIGSEGV/SIGILL en
# ciertas CPUs. Corre en un tmpdir con ErrorFile=/dev/null y sin core dumps,
# así no deja hs_err_pid*.log ni cores en el cwd.
jdk_works() {
  local home="$1" tmp out
  [[ -x "$home/bin/java" && -x "$home/bin/javac" ]] || return 1
  tmp="$(mktemp -d)" || return 1
  out="$(
    cd "$tmp" || exit 1
    ulimit -c 0
    printf 'public class Hello { public static void main(String[] a) { System.out.println("ok"); } }\n' > Hello.java
    timeout 60 "$home/bin/javac" -J-XX:ErrorFile=/dev/null Hello.java &>/dev/null &&
      timeout 60 "$home/bin/java" -XX:ErrorFile=/dev/null -cp . Hello 2>/dev/null
  )"
  rm -rf "$tmp"
  [[ "$out" == "ok" ]]
}

# Instala la versión mayor $1 probando JDK_DISTS en orden: instala, corre
# jdk_works y, si no arranca, la desinstala y pasa a la siguiente distribución.
# Usa avail/broken de install_java_jdks (scope dinámico de bash) y deja el id
# instalado en JDK_NEW_ID. Si 'sdk install' falla (red, etc.) no se sigue: eso
# no es un problema del build.
install_jdk_major() {
  local major="$1" dist id tried=()
  JDK_NEW_ID=""
  for dist in "${JDK_DISTS[@]}"; do
    id="${avail[$major:$dist]:-}"
    # Si ya hay un build roto de esta distribución, ni se descarga otro
    [[ -z "$id" || " ${broken[$major]:-} " == *"-$dist "* ]] && continue
    tried+=("$id")

    info "Installing Java $id..."
    # "n" responde a "¿usar como default?"; el default se decide al final. Si
    # es el primer JDK, sdk lo pone de default sin preguntar.
    if ! sdk_run install java "$id" <<< "n"; then
      warn "Failed to install Java $id"
      return 1
    fi

    if jdk_works "$SDKMAN_DIR/candidates/java/$id"; then
      ok "Java $id installed (smoke test OK)"
      JDK_NEW_ID="$id"
      return 0
    fi

    warn "Java $id no arranca en esta máquina — desinstalando"
    sdk_run uninstall java "$id" --force &>/dev/null || warn "No se pudo desinstalar $id"
  done

  if [[ ${#tried[@]} -eq 0 ]]; then
    warn "No hay builds de Java $major en ${JDK_DISTS[*]} (¿sin red?)"
  else
    warn "Ningún build de Java $major arranca aquí (probados: ${tried[*]})"
  fi
  return 1
}

# Checklist de JDKs (una entrada por versión mayor) sobre SDKMAN. Verifica los
# ya instalados (cualquier distribución): los que arrancan salen como
# instalados y se saltan; los que no, salen marcados para repararlos con otra
# distribución. Marca por defecto la mayor más reciente y al final ofrece
# elegir el JDK por defecto. En modo no interactivo instala la más reciente,
# repara los rotos y conserva el default.
install_java_jdks() {
  local java_dir="$SDKMAN_DIR/candidates/java"

  local prev_default=""
  [[ -L "$java_dir/current" ]] && prev_default="$(basename "$(readlink -f "$java_dir/current")")"

  # Instalados: mayor => ids que arrancan / ids rotos (8.0.504+1-tem -> 8)
  local -A installed=() broken=()
  local working_ids=() dir id major
  for dir in "$java_dir"/*; do
    id="${dir##*/}"
    [[ -d "$dir" && "$id" != current ]] || continue
    major="${id%%[.+-]*}"
    if jdk_works "$dir"; then
      working_ids+=("$id")
      installed[$major]="${installed[$major]:+${installed[$major]} }$id"
    else
      broken[$major]="${broken[$major]:+${broken[$major]} }$id"
    fi
  done

  # Disponibles: "mayor:dist" => id más nuevo. 'sdk list' viene ordenado de
  # mayor a menor dentro de cada distribución, así que el primero gana.
  local -A avail=()
  local majors=() dist dist_re
  dist_re="-($(
    IFS='|'
    echo "${JDK_DISTS[*]}"
  ))\$"
  while IFS= read -r id; do
    major="${id%%[.+-]*}"
    dist="${id##*-}"
    [[ -n "$major" && -z "${avail[$major:$dist]:-}" ]] && avail[$major:$dist]="$id"
  done < <(PAGER=cat sdk_run list java 2>/dev/null |
    awk -F'|' -v re="$dist_re" '{gsub(/ /, "", $4)} $4 ~ re {print $4}')

  # Unión de mayores de todas las distribuciones, de 8 en adelante (zulu aún
  # ofrece 6 y 7)
  while IFS= read -r major; do
    [[ -n "$major" && "$major" -ge 8 ]] && majors+=("$major")
  done < <(for id in "${!avail[@]}"; do echo "${id%%:*}"; done | sort -rnu)

  if [[ ${#majors[@]} -eq 0 ]]; then
    warn "No se pudo obtener la lista de JDKs de SDKMAN (¿sin red?)"
  fi
  local newest="${majors[0]:-}"

  local chosen=()
  if [[ "$NONINTERACTIVE" == "true" ]]; then
    [[ -n "$newest" ]] && chosen=("$newest")
    for major in "${majors[@]}"; do
      [[ -n "${broken[$major]:-}" && -z "${installed[$major]:-}" && "$major" != "$newest" ]] &&
        chosen+=("$major")
    done
    info "Non-interactive mode — JDK(s): ${chosen[*]:-ninguno}"
  elif [[ ${#majors[@]} -gt 0 ]]; then
    local items=() state label pref
    for major in "${majors[@]}"; do
      # dialog solo tiene [*]/[ ]: el estado de lo ya instalado va en una
      # etiqueta de color (\Z2 verde, \Z1 rojo; requiere --colors).
      if [[ -n "${installed[$major]:-}" ]]; then
        label="Java $major  \Z2\Zb✓ instalado\Zn (${installed[$major]})"
        state="off"
      elif [[ -n "${broken[$major]:-}" ]]; then
        label="Java $major  \Z1\Zb✗ no arranca\Zn (${broken[$major]})"
        state="on"
      else
        pref=""
        for dist in "${JDK_DISTS[@]}"; do
          pref="${avail[$major:$dist]:-}"
          [[ -n "$pref" ]] && break
        done
        label="Java $major  ($pref)"
        [[ "$major" == "$newest" ]] && state="on" || state="off"
      fi
      items+=("$major" "$label" "$state")
    done

    local lh="${#majors[@]}"
    [[ $lh -lt 6 ]] && lh=6
    [[ $lh -gt 12 ]] && lh=12
    local wh=$((lh + 12))

    local raw
    raw=$(dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " Java JDKs (SDKMAN) " \
      --separate-output \
      --checklist \
      "¿Qué JDKs instalar?  [SPACE=toggle  ENTER=confirm]\n\nLos que dicen \Z2\Zb✓ instalado\Zn se saltan aunque los marques; los\n\Z1\Zb✗ no arranca\Zn se reinstalan con otra distribución.\nOrden: ${JDK_DISTS[*]} (si un build no arranca, se prueba el siguiente)." \
      "$wh" 76 "$lh" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || {
      clear
      warn "JDK install cancelled."
      raw=""
    }
    clear

    while IFS= read -r major; do
      [[ -n "$major" ]] && chosen+=("$major")
    done <<< "$raw"
  fi

  local old
  for major in "${chosen[@]}"; do
    if [[ -n "${installed[$major]:-}" ]]; then
      skip "Java $major already installed (${installed[$major]})"
      continue
    fi
    install_jdk_major "$major" || continue
    working_ids+=("$JDK_NEW_ID")

    # Reparado: retira los builds rotos de esa mayor. Si uno era el default,
    # el reemplazo hereda ese lugar.
    for old in ${broken[$major]:-}; do
      if sdk_run uninstall java "$old" --force &>/dev/null; then
        ok "Removed broken Java $old"
      else
        warn "No se pudo desinstalar $old"
      fi
      [[ "$old" == "$prev_default" ]] && prev_default="$JDK_NEW_ID"
    done
  done

  java_pick_default "$prev_default" "${working_ids[@]}"
}

# Elige el JDK por defecto de SDKMAN ($1 = default previo, resto = instalados).
# Interactivo: menú con los instalados (preselecciona el actual). No
# interactivo: conserva el previo; si no había, deja el que puso sdk.
java_pick_default() {
  local prev="$1"
  shift
  local ids=("$@")
  [[ ${#ids[@]} -eq 0 ]] && return

  local pick="$prev"
  if [[ "$NONINTERACTIVE" == false && ${#ids[@]} -gt 1 ]]; then
    local items=() id
    for id in "${ids[@]}"; do
      [[ "$id" == "$prev" ]] && items+=("$id" "default actual") || items+=("$id" "")
    done
    local lh=${#ids[@]}
    [[ $lh -gt 10 ]] && lh=10
    pick=$(dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " Java por defecto (SDKMAN) " \
      ${prev:+--default-item "$prev"} \
      --menu "¿Qué JDK usar por defecto en nuevas shells?" \
      $((lh + 8)) 64 "$lh" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || pick="$prev" # cancelar = conservar el actual
    clear
  fi

  [[ -z "$pick" ]] && return
  if sdk_run default java "$pick" &>/dev/null; then
    ok "Java por defecto: $pick"
  else
    warn "No se pudo establecer Java $pick como default"
  fi
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
