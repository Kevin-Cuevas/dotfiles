# shellcheck shell=bash
# bootstrap.d/20-runtimes.sh — language runtimes (rust, node, deno, bun, java)
# ==============================================================================
# RUNTIME_KEYS/LABEL/FN + install_runtimes() drive menu option 12's
# checklist; NPM_GLOBAL_KEYS/LABEL/PKG feed install_node_globals(), offered
# right after Node installs; install_java_jdks() does the same for JDKs right
# after SDKMAN installs. To add a runtime: add its key to RUNTIME_KEYS +
# a label/function entry in RUNTIME_LABEL/RUNTIME_FN, and define
# install_<name>().
# ==============================================================================

# Languages/runtimes that do NOT come from apt. To add one: add its key to
# RUNTIME_KEYS and its label + function to the maps, and define install_<name>().
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

# Global npm packages offered after installing Node (checklist).
# To add one: add its key here and its label + npm spec to the maps.
NPM_GLOBAL_KEYS=(live-server commitizen angular)
declare -A NPM_GLOBAL_LABEL=(
  ["live-server"]="live-server"
  [commitizen]="commitizen"
  [angular]="Angular CLI"
)
declare -A NPM_GLOBAL_PKG=(
  ["live-server"]="live-server"
  [commitizen]="commitizen cz-conventional-changelog"
  [angular]="@angular/cli"
)

install_node() {
  sep
  local fnm_dir="$HOME/.local/share/fnm"

  # Node from apt clashes with fnm (binary in the system PATH). Purge it first.
  if dpkg -s nodejs &>/dev/null; then
    warn "nodejs installed via apt — removing it to use fnm..."
    if sudo apt-get remove --purge -y nodejs npm &>/dev/null; then
      sudo apt-get autoremove -y &>/dev/null || true
      ok "apt nodejs/npm removed"
    else
      warn "Couldn't remove apt's nodejs — continuing, but fnm may clash in PATH"
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

  # Available in this session (the shell isn't touched; .zshrc already handles fnm)
  export PATH="$fnm_dir:$PATH"
  command -v fnm &>/dev/null || {
    warn "fnm isn't in PATH after installing"
    return 1
  }
  eval "$(fnm env)" 2>/dev/null || true

  # Node versions already installed with fnm (excluding 'system').
  local installed_versions=() v
  while IFS= read -r v; do
    [[ -n "$v" ]] && installed_versions+=("$v")
  done < <(fnm list 2>/dev/null | awk '$2 ~ /^v[0-9]/ {print $2}')

  local action="lts" # default: install the latest LTS

  # Only ask if interactive AND there are versions installed already.
  if [[ "$NONINTERACTIVE" == false && ${#installed_versions[@]} -gt 0 ]]; then
    local menu_items=("lts" "Install the latest Node LTS (fnm install --lts)")
    for v in "${installed_versions[@]}"; do
      menu_items+=("$v" "Use this installed version (fnm default $v)")
    done
    local lh=$((${#installed_versions[@]} + 1))
    [[ $lh -gt 10 ]] && lh=10
    local wh=$((lh + 9))
    action=$(dialog \
      --clear --colors \
      --backtitle "$BACKTITLE" \
      --title " Node.js (fnm) " \
      --menu "There are Node versions already installed with fnm.\n\nUse an existing version or install the latest LTS?" \
      "$wh" 70 "$lh" \
      "${menu_items[@]}" \
      3>&1 1>&2 2>&3) || action="lts" # cancel = default LTS
    clear
  fi

  local node_alias=""
  if [[ "$action" == "lts" ]]; then
    info "Installing Node.js LTS via fnm..."
    if fnm install --lts; then
      fnm default lts-latest &>/dev/null || true # new shells use the LTS by default
      ok "Node.js LTS installed ($(fnm exec --using=lts-latest node -v 2>/dev/null))"
      node_alias="lts-latest"
    else
      warn "fnm install --lts failed — check output above"
      return 1
    fi
  else
    info "Setting Node $action as the default version..."
    fnm default "$action" &>/dev/null || true
    ok "Default Node: $action ($(fnm exec --using="$action" node -v 2>/dev/null))"
    node_alias="$action"
  fi

  install_node_globals "$node_alias"
}

# Offers to install global npm packages on Node version $1 (an fnm alias:
# lts-latest or vXX...). Non-interactive mode installs them all; interactive
# shows a checklist (everything unchecked).
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
      "Install global npm packages?  [SPACE=toggle  ENTER=confirm]\n\nInstalled with 'npm install -g' on Node $using." \
      "$wh" 64 "$lh" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || {
      warn "Global npm packages skipped."
      return
    }

    clear # wipe dialog leftovers before the logs

    while IFS= read -r key; do
      [[ -n "$key" ]] && chosen+=("$key")
    done <<<"$raw"

    if [[ ${#chosen[@]} -eq 0 ]]; then
      skip "No global npm packages selected."
      return
    fi
  fi

  local key pkg sub all_present specs
  for key in "${chosen[@]}"; do
    pkg="${NPM_GLOBAL_PKG[$key]}"
    # A key can carry several space-separated npm specs (commitizen + its
    # adapter): they're split once, into an array.
    read -ra specs <<<"$pkg"

    all_present=true
    for sub in "${specs[@]}"; do
      fnm exec --using="$using" npm ls -g --depth=0 "$sub" &>/dev/null || all_present=false
    done

    if [[ "$all_present" == true ]]; then
      skip "$pkg already installed globally"
    else
      info "npm install -g $pkg ..."
      if fnm exec --using="$using" npm install -g "${specs[@]}" &>/dev/null; then
        ok "Installed global: $pkg"
      else
        warn "Failed to install global: $pkg"
      fi
    fi

    [[ "$key" == "commitizen" ]] && write_czrc
  done
}

# Writes ~/.czrc so 'git cz' uses cz-conventional-changelog. Called whenever
# the user chooses to install commitizen, regardless of whether the
# 'npm install -g' above ran, failed, or was skipped as already installed.
write_czrc() {
  echo '{ "path": "cz-conventional-changelog" }' >"$HOME/.czrc"
  ok "Wrote $HOME/.czrc"
}

# JDK distributions used by install_java_jdks(), in order of preference
# (SDKMAN suffixes: tem = Eclipse Temurin, amzn = Corretto, zulu, librca =
# Liberica). If a build doesn't start on this machine (e.g. Temurin 17 on the
# Android aarch64 VM) the next one is tried. Versions come from
# 'sdk list java', so the checklist offers the newest major without touching
# this file.
JDK_DISTS=(tem amzn zulu librca)

# 'sdk' is a shell function, not a binary: its init has to be sourced into
# this process. The init and sdk use unset variables, and the bootstrap runs
# with 'set -u', so it's turned off only while they run.
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
    # The installer requires zip/unzip (they come with APT_PKGS).
    local dep
    for dep in curl zip unzip; do
      command -v "$dep" &>/dev/null || {
        warn "SDKMAN needs '$dep' — install it (option 2) and try again"
        return 1
      }
    done

    info "Installing SDKMAN..."
    # rcupdate=false: leaves ~/.zshrc alone (a symlink into the repo); .zshrc already loads it
    if curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash &>/dev/null; then
      ok "SDKMAN installed at $SDKMAN_DIR"
    else
      warn "Failed to install SDKMAN — check network/curl"
      return 1
    fi
  fi

  sdkman_load || {
    warn "Couldn't load sdkman-init.sh"
    return 1
  }

  install_java_jdks
}

# Smoke test for a JDK ($1 = its home): compiles and runs a class. An
# "installed" JDK isn't one that starts: some builds die with SIGSEGV/SIGILL on
# certain CPUs. It runs in a tmpdir with ErrorFile=/dev/null and no core dumps,
# so it leaves no hs_err_pid*.log or cores in the cwd.
jdk_works() {
  local home="$1" tmp out
  [[ -x "$home/bin/java" && -x "$home/bin/javac" ]] || return 1
  tmp="$(mktemp -d)" || return 1
  out="$(
    cd "$tmp" || exit 1
    ulimit -c 0
    printf 'public class Hello { public static void main(String[] a) { System.out.println("ok"); } }\n' >Hello.java
    timeout 60 "$home/bin/javac" -J-XX:ErrorFile=/dev/null Hello.java &>/dev/null \
      && timeout 60 "$home/bin/java" -XX:ErrorFile=/dev/null -cp . Hello 2>/dev/null
  )"
  rm -rf "$tmp"
  [[ "$out" == "ok" ]]
}

# Installs major version $1 trying JDK_DISTS in order: installs, runs
# jdk_works and, if it doesn't start, uninstalls it and moves on to the next
# distribution. Uses install_java_jdks' avail/broken (bash dynamic scope) and
# leaves the installed id in JDK_NEW_ID. If 'sdk install' fails (network,
# etc.) it stops there: that isn't a problem with the build.
install_jdk_major() {
  local major="$1" dist id tried=()
  JDK_NEW_ID=""
  for dist in "${JDK_DISTS[@]}"; do
    id="${avail["$major:$dist"]:-}"
    # If there's already a broken build of this distribution, don't even download another
    [[ -z "$id" || " ${broken[$major]:-} " == *"-$dist "* ]] && continue
    tried+=("$id")

    info "Installing Java $id..."
    # "n" answers "use as default?"; the default is decided at the end. If
    # it's the first JDK, sdk makes it the default without asking.
    if ! sdk_run install java "$id" <<<"n"; then
      warn "Failed to install Java $id"
      return 1
    fi

    if jdk_works "$SDKMAN_DIR/candidates/java/$id"; then
      ok "Java $id installed (smoke test OK)"
      JDK_NEW_ID="$id"
      return 0
    fi

    warn "Java $id doesn't start on this machine — uninstalling"
    sdk_run uninstall java "$id" --force &>/dev/null || warn "Couldn't uninstall $id"
  done

  if [[ ${#tried[@]} -eq 0 ]]; then
    warn "No Java $major builds in ${JDK_DISTS[*]} (offline?)"
  else
    warn "No Java $major build starts here (tried: ${tried[*]})"
  fi
  return 1
}

# JDK checklist (one entry per major version) on top of SDKMAN. Checks the
# ones already installed (any distribution): those that start show as
# installed and are skipped; those that don't come pre-checked so they get
# repaired with another distribution. The newest major is checked by default
# and at the end it offers to pick the default JDK. Non-interactive mode
# installs the newest one, repairs broken ones and keeps the default.
install_java_jdks() {
  local java_dir="$SDKMAN_DIR/candidates/java"

  local prev_default=""
  [[ -L "$java_dir/current" ]] && prev_default="$(basename "$(readlink -f "$java_dir/current")")"

  # Installed: major => ids that start / broken ids (8.0.504+1-tem -> 8)
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

  # Available: "major:dist" => newest id. 'sdk list' comes sorted from
  # highest to lowest within each distribution, so the first one wins.
  local -A avail=()
  local majors=() dist dist_re
  dist_re="-($(
    IFS='|'
    echo "${JDK_DISTS[*]}"
  ))\$"
  # shellcheck disable=SC2209 # PAGER=cat is an env var for sdk_run, not an assignment
  while IFS= read -r id; do
    major="${id%%[.+-]*}"
    dist="${id##*-}"
    [[ -n "$major" && -z "${avail["$major:$dist"]:-}" ]] && avail["$major:$dist"]="$id"
  done < <(PAGER=cat sdk_run list java 2>/dev/null \
    | awk -F'|' -v re="$dist_re" '{gsub(/ /, "", $4)} $4 ~ re {print $4}')

  # Union of the majors of every distribution, from 8 up (zulu still offers
  # 6 and 7)
  while IFS= read -r major; do
    [[ -n "$major" && "$major" -ge 8 ]] && majors+=("$major")
  done < <(for id in "${!avail[@]}"; do echo "${id%%:*}"; done | sort -rnu)

  if [[ ${#majors[@]} -eq 0 ]]; then
    warn "Couldn't get the JDK list from SDKMAN (offline?)"
  fi
  local newest="${majors[0]:-}"

  local chosen=()
  if [[ "$NONINTERACTIVE" == "true" ]]; then
    [[ -n "$newest" ]] && chosen=("$newest")
    for major in "${majors[@]}"; do
      [[ -n "${broken[$major]:-}" && -z "${installed[$major]:-}" && "$major" != "$newest" ]] \
        && chosen+=("$major")
    done
    info "Non-interactive mode — JDK(s): ${chosen[*]:-ninguno}"
  elif [[ ${#majors[@]} -gt 0 ]]; then
    local items=() state label pref
    for major in "${majors[@]}"; do
      # dialog only has [*]/[ ]: the state of what's installed goes in a
      # colored label (\Z2 green, \Z1 red; requires --colors).
      if [[ -n "${installed[$major]:-}" ]]; then
        label="Java $major  \Z2\Zb✓ installed\Zn (${installed[$major]})"
        state="off"
      elif [[ -n "${broken[$major]:-}" ]]; then
        label="Java $major  \Z1\Zb✗ doesn't start\Zn (${broken[$major]})"
        state="on"
      else
        pref=""
        for dist in "${JDK_DISTS[@]}"; do
          pref="${avail["$major:$dist"]:-}"
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
      "Which JDKs to install?  [SPACE=toggle  ENTER=confirm]\n\nThose marked \Z2\Zb✓ installed\Zn are skipped even if checked; those marked\n\Z1\Zb✗ doesn't start\Zn are reinstalled from another distribution.\nOrder: ${JDK_DISTS[*]} (if a build doesn't start, the next one is tried)." \
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
    done <<<"$raw"
  fi

  local old
  for major in "${chosen[@]}"; do
    if [[ -n "${installed[$major]:-}" ]]; then
      skip "Java $major already installed (${installed[$major]})"
      continue
    fi
    install_jdk_major "$major" || continue
    working_ids+=("$JDK_NEW_ID")

    # Repaired: remove that major's broken builds. If one was the default,
    # the replacement takes its place.
    for old in ${broken[$major]:-}; do
      if sdk_run uninstall java "$old" --force &>/dev/null; then
        ok "Removed broken Java $old"
      else
        warn "Couldn't uninstall $old"
      fi
      [[ "$old" == "$prev_default" ]] && prev_default="$JDK_NEW_ID"
    done
  done

  java_pick_default "$prev_default" "${working_ids[@]}"
}

# Picks SDKMAN's default JDK ($1 = previous default, rest = installed).
# Interactive: a menu with the installed ones (current one preselected).
# Non-interactive: keeps the previous one; if there was none, leaves sdk's.
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
      --title " Default Java (SDKMAN) " \
      ${prev:+--default-item "$prev"} \
      --menu "Which JDK should new shells use by default?" \
      $((lh + 8)) 64 "$lh" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || pick="$prev" # cancel = keep the current one
    clear
  fi

  [[ -z "$pick" ]] && return
  if sdk_run default java "$pick" &>/dev/null; then
    ok "Default Java: $pick"
  else
    warn "Couldn't set Java $pick as the default"
  fi
}

install_rust() {
  sep
  if command -v rustc &>/dev/null || [[ -x "$HOME/.cargo/bin/rustup" ]]; then
    skip "Rust already installed"
    return
  fi

  info "Installing Rust (rustup)..."
  # --no-modify-path: .zshrc already adds ~/.cargo/bin; -y: non-interactive
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
  # -y: non-interactive; --no-modify-path: .zshrc already sources ~/.deno/env
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
  # bun's installer has no flag to leave the rc alone, and ~/.zshrc is a
  # symlink into the repo (stow). We protect it by removing write permission:
  # bun sees it isn't writable and prints instructions instead of modifying the
  # file (.zshrc handles bun anyway). Permissions are restored at the end.
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

# Menu/checklist of runtimes that don't use apt (rust, node, ...). Non-
# interactive mode installs them all; interactive shows a checklist (all checked).
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

    # Minimum rows so the box doesn't look cramped (like stow's), even with
    # few runtimes.
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
      "Select language runtimes to install  [SPACE=toggle  ENTER=confirm]\n\nInstallers that do NOT use apt (rustup, fnm, ...)." \
      "$win_height" 64 "$list_height" \
      "${items[@]}" \
      3>&1 1>&2 2>&3) || {
      warn "Runtime install cancelled."
      return
    }

    clear # wipe dialog leftovers before the logs

    while IFS= read -r item; do
      [[ -n "$item" ]] && chosen+=("$item")
    done <<<"$raw"

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
