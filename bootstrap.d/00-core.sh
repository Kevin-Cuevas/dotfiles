# shellcheck shell=bash
# bootstrap.d/00-core.sh — shared UI/logging primitives
# ==============================================================================
# Colors, log helpers (info/ok/err/warn/skip/die/sep), preflight checks,
# and the header banner. Sourced by ../bootstrap — every other module in this directory
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
