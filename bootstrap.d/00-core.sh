# bootstrap.d/00-core.sh — shared UI/logging primitives
# ==============================================================================
# Colors, log helpers (info/ok/err/warn/skip/die/sep), the generic
# checklist_select_or_all dialog helper, preflight checks, and the header
# banner. Sourced by ../bootstrap — every other module in this directory
# depends on this one loading first (hence the 00- prefix).
# ==============================================================================

RED='\e[38;2;191;97;106m'
GRN='\e[38;2;163;190;140m'
YLW='\e[38;2;235;203;139m'
BLU='\e[38;2;136;192;208m'
CYN='\e[38;2;143;188;187m'
DIM='\e[38;2;94;129;172m'
BLD='\e[1m'
RST='\e[0m'

info() { printf "${BLU}[INFO]${RST}  %s\n" "$*"; }
ok() { printf "${GRN}[OK]${RST}    %s\n" "$*"; }
err() { printf "${RED}[ERR]${RST}   %s\n" "$*" >&2; }
warn() { printf "${YLW}[WARN]${RST}  %s\n" "$*"; }
skip() { printf "${CYN}[SKIP]${RST}  %s\n" "$*"; }
die() {
  err "$*"
  exit 1
}
sep() { printf "${DIM}%s${RST}\n" "  ──────────────────────────────────────────────────"; }

# checklist_select_or_all <title> <prompt> <win_h> <win_w> <list_h> \
#                          <out_array_name> <keys_array_name> [labels_assoc_name]
#
# Checklist compartido con semántica "instalar algunos / todos / ninguno":
#   - Todos los items empiezan desmarcados, más una fila extra "__skip__".
#   - Si se marca __skip__          -> el array de salida queda vacío.
#   - Si no se marca nada (ENTER)   -> el array de salida = la lista completa.
#   - Si se marcan items concretos  -> el array de salida = solo esos.
#   - Devuelve 1 si el diálogo se cancela (ESC/Cancel).
checklist_select_or_all() {
  local _title="$1" _prompt="$2" _wh="$3" _ww="$4" _lh="$5"
  local -n _out_ref="$6"
  local -n _keys_ref="$7"
  local _has_labels=0
  if [[ -n "${8:-}" ]]; then
    local -n _labels_ref="$8"
    _has_labels=1
  fi

  _out_ref=()

  local _items=("__skip__" "Skip -- install none of the above" "off")
  local _key _label
  for _key in "${_keys_ref[@]}"; do
    [[ $_has_labels -eq 1 ]] && _label="${_labels_ref[$_key]}" || _label="$_key"
    _items+=("$_key" "$_label" "off")
  done

  local _raw
  _raw=$(dialog --clear --colors --backtitle "$BACKTITLE" \
    --title " $_title " --separate-output --checklist \
    "$_prompt" "$_wh" "$_ww" "$_lh" "${_items[@]}" \
    3>&1 1>&2 2>&3) || return 1

  clear

  local _raw_chosen=() _line
  while IFS= read -r _line; do [[ -n "$_line" ]] && _raw_chosen+=("$_line"); done <<< "$_raw"

  for _line in "${_raw_chosen[@]}"; do
    [[ "$_line" == "__skip__" ]] && { _out_ref=(); return 0; }
  done

  if [[ ${#_raw_chosen[@]} -eq 0 ]]; then
    _out_ref=("${_keys_ref[@]}")
  else
    _out_ref=("${_raw_chosen[@]}")
  fi
}

preflight() {
  if [[ "$NONINTERACTIVE" == "false" ]] && ! command -v dialog &>/dev/null; then
    info "dialog not found — installing..."
    sudo apt-get install -y dialog 2>/dev/null || die "Cannot install dialog. Install it manually: sudo apt install dialog"
  fi

  if ! command -v stow &>/dev/null; then
    info "stow not found — installing..."
    sudo apt-get install -y stow 2>/dev/null || die "Cannot install stow. Install it manually: sudo apt install stow"
  fi

  if [[ "$TEST_MODE" == true ]]; then
    mkdir -p "$TARGET"
    warn "TEST MODE active — all symlinks target: $TARGET"
    sleep 1
  fi
}

print_header() {
  clear
  printf "${DIM}  ════════════════════════════════════════════════${RST}\n"
  printf "${BLU}${BLD}   DOTFILES BOOTSTRAP${RST}\n"
  printf "${CYN}   Host: %s   Date: %s${RST}\n" "$(hostname)" "$(date '+%Y-%m-%d %H:%M')"
  if [[ "$TEST_MODE" == true ]]; then
    printf "${YLW}   [TEST MODE] Target: %s${RST}\n" "$TARGET"
  else
    printf "${DIM}   Target: %s${RST}\n" "$TARGET"
  fi
  printf "${DIM}  ════════════════════════════════════════════════${RST}\n"
  printf "\n"
}
