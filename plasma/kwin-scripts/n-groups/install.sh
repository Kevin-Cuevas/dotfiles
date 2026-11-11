#!/usr/bin/env bash
# n-groups — snap groups for KWin (Plasma 6.7+, Wayland).
#
# Two KDE packages from this folder:
#   script/    n-groups    KWin script: groups, Alt+Tab entries, shortcuts
#   switcher/  n-switcher  Alt+Tab layout: live mosaic + whole-group preview
# n-switcher reads the groups from n-groups, so it's only selected while
# n-groups is installed. Settings stay in the usual KDE places (kwinrc,
# kglobalshortcutsrc) and can be changed from System Settings.
#
# Usage:
#   install.sh [install]      install/update both, enable n-groups, use n-switcher
#   install.sh --no-switcher  same, but leave the Alt+Tab layout alone
#   install.sh uninstall      restore Alt+Tab, disable and remove both
#   install.sh status         what is installed, enabled and selected
#   install.sh doctor         check Plasma version and drift (exit 1 if broken)
#   install.sh -h | --help    this help
set -uo pipefail

RED='\e[38;2;191;97;106m'
GRN='\e[38;2;163;190;140m'
YLW='\e[38;2;235;203;139m'
BLU='\e[38;2;136;192;208m'
CYN='\e[38;2;143;188;187m'
RST='\e[0m'

info() { printf "${BLU}[INFO]${RST}  %s\n" "$*"; }
ok() { printf "${GRN}[OK]${RST}    %s\n" "$*"; }
err() { printf "${RED}[ERR]${RST}   %s\n" "$*" >&2; }
warn() { printf "${YLW}[WARN]${RST}  %s\n" "$*"; }
skip() { printf "${CYN}[SKIP]${RST}  %s\n" "$*"; }

DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/kwin"
KWINRC="${XDG_CONFIG_HOME:-$HOME/.config}/kwinrc"
SCRIPT_ID="n-groups"
SWITCHER_ID="n-switcher"
MIN_PLASMA="6.7"
QDBUS="$(command -v qdbus6 || command -v qdbus || true)"

script_dir() { printf '%s/scripts/%s' "$DATA" "$SCRIPT_ID"; }
switcher_dir() { printf '%s/tabbox/%s' "$DATA" "$SWITCHER_ID"; }

usage() {
  sed -n '/^# Usage:/,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"
}

need() {
  local c
  for c in "$@"; do
    command -v "$c" &>/dev/null || {
      err "$c not found (is KDE Plasma installed?)"
      return 1
    }
  done
}

kwin() { [[ -n "$QDBUS" ]] && "$QDBUS" org.kde.KWin "$@" 2>/dev/null; }
reconfigure() { kwin /KWin reconfigure >/dev/null || true; }
loaded() { [[ "$(kwin /Scripting org.kde.kwin.Scripting.isScriptLoaded "$SCRIPT_ID")" == true ]]; }
enabled() { [[ "$(kreadconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled")" == true ]]; }
layout() { kreadconfig6 --file kwinrc --group TabBox --key LayoutName; }
version_of() { sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$1/metadata.json" 2>/dev/null; }
same() { [[ -d "$2" ]] && diff -rq "$1" "$2" &>/dev/null; }

# Removes KEY from [GROUP] in kwinrc so the lower layers apply again (the
# Global Theme's ~/.config/kdedefaults). kwriteconfig6 --delete can't do it:
# it writes KEY[$d], which hides those layers too.
drop_key() {
  local group="$1" key="$2" tmp
  [[ -f "$KWINRC" ]] || return 0
  tmp="$(mktemp)" || return 1
  awk -v g="[$group]" -v k="$key" '
    /^\[/ { ingroup = ($0 == g) }
    ingroup && (index($0, k "=") == 1 || index($0, k "[$d]") == 1) { next }
    { print }
  ' "$KWINRC" >"$tmp" && cat "$tmp" >"$KWINRC"
  rm -f "$tmp"
}

# KWin loads enabled scripts on reconfigure; if it hasn't after a moment, load
# it the same way it would (same name, so the same [Script-n-groups] config).
ensure_loaded() {
  local tries=10
  while ((tries-- > 0)); do
    loaded && return 0
    sleep 0.2
  done
  kwin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
    "$(script_dir)/contents/ui/main.qml" "$SCRIPT_ID" >/dev/null
  kwin /Scripting org.kde.kwin.Scripting.start >/dev/null
  loaded
}

plasma_version() { plasmashell --version 2>/dev/null | awk '{print $2}'; }
plasma_ok() {
  local v
  v="$(plasma_version)"
  [[ -n "$v" && "$(printf '%s\n%s\n' "$MIN_PLASMA" "$v" | sort -V | head -1)" == "$MIN_PLASMA" ]]
}

# $1 package type, $2 source, $3 installed dir. Returns 0 if it changed.
sync_package() {
  local type="$1" src="$2" dst="$3" name
  name="$(basename "$dst")"
  if same "$src" "$dst"; then
    skip "$name $(version_of "$dst") is up to date"
    return 1
  fi
  if [[ -d "$dst" ]]; then
    kpackagetool6 --type "$type" --upgrade "$src" >/dev/null || {
      err "kpackagetool6 couldn't upgrade $name"
      return 2
    }
  else
    kpackagetool6 --type "$type" --install "$src" >/dev/null || {
      err "kpackagetool6 couldn't install $name"
      return 2
    }
  fi
  ok "$name $(version_of "$src") -> $dst"
  return 0
}

cmd_install() {
  local use_switcher="$1" was_loaded=false changed=false rc
  need kpackagetool6 kwriteconfig6 kreadconfig6 plasmashell || return 1
  plasma_ok || warn "Plasma $(plasma_version) is older than $MIN_PLASMA: n-groups may not work"
  loaded && was_loaded=true

  sync_package KWin/Script "$DIR/script" "$(script_dir)"
  rc=$?
  ((rc == 2)) && return 1
  ((rc == 0)) && changed=true
  sync_package KWin/WindowSwitcher "$DIR/switcher" "$(switcher_dir)"
  rc=$?
  ((rc == 2)) && return 1
  ((rc == 0)) && changed=true

  kwriteconfig6 --file kwinrc --group Plugins --key "${SCRIPT_ID}Enabled" true
  ok "$SCRIPT_ID enabled"
  if $use_switcher; then
    kwriteconfig6 --file kwinrc --group TabBox --key LayoutName "$SWITCHER_ID"
    ok "Alt+Tab uses $SWITCHER_ID"
  else
    skip "Alt+Tab layout left as $(layout)"
  fi
  reconfigure
  if [[ -z "$QDBUS" ]]; then
    skip "qdbus6 not found: $SCRIPT_ID starts with your next session"
  elif ensure_loaded; then
    ok "$SCRIPT_ID running"
  else
    warn "$SCRIPT_ID didn't start: check 'journalctl --user -b | grep n-groups'"
  fi

  # KWin's QML engine caches the script and the layout by URL for the whole
  # session: reloading them keeps running the old code.
  if $changed && $was_loaded; then
    warn "KWin caches scripts for the whole session: log out and back in to run the new code"
  fi
}

cmd_uninstall() {
  need kpackagetool6 kwriteconfig6 kreadconfig6 || return 1
  # Alt+Tab first: n-switcher can't load without n-groups.
  if [[ "$(layout)" == "$SWITCHER_ID" ]]; then
    drop_key TabBox LayoutName
    local now
    now="$(layout)"
    ok "Alt+Tab back to ${now:-the KWin default}"
  fi
  drop_key Plugins "${SCRIPT_ID}Enabled"
  kwin /Scripting org.kde.kwin.Scripting.unloadScript "$SCRIPT_ID" >/dev/null || true
  reconfigure
  ok "$SCRIPT_ID disabled (every window is back in Alt+Tab)"

  [[ -d "$(script_dir)" ]] && kpackagetool6 --type KWin/Script --remove "$SCRIPT_ID" >/dev/null \
    && ok "$SCRIPT_ID removed"
  [[ -d "$(switcher_dir)" ]] && kpackagetool6 --type KWin/WindowSwitcher --remove "$SWITCHER_ID" >/dev/null \
    && ok "$SWITCHER_ID removed"
  return 0
}

cmd_status() {
  local v
  v="$(version_of "$(script_dir)")"
  printf '%-10s %s\n' "$SCRIPT_ID" "${v:-not installed}$(enabled && printf ', enabled')$(loaded && printf ', loaded')"
  v="$(version_of "$(switcher_dir)")"
  printf '%-10s %s\n' "$SWITCHER_ID" "${v:-not installed}"
  printf '%-10s %s\n' "alt+tab" "$(layout)"
  printf '%-10s %s\n' "plasma" "$(plasma_version)"
}

cmd_doctor() {
  local fail=0
  if plasma_ok; then
    ok "Plasma $(plasma_version) (>= $MIN_PLASMA)"
  else
    err "Plasma $(plasma_version) is older than $MIN_PLASMA"
    fail=1
  fi

  local pair id src dst
  for pair in "$SCRIPT_ID:script" "$SWITCHER_ID:switcher"; do
    id="${pair%%:*}" src="$DIR/${pair#*:}"
    if [[ "$id" == "$SCRIPT_ID" ]]; then dst="$(script_dir)"; else dst="$(switcher_dir)"; fi
    if [[ ! -d "$dst" ]]; then
      warn "$id isn't installed (install.sh)"
    elif same "$src" "$dst"; then
      ok "$id $(version_of "$dst") matches $src"
    else
      warn "$id differs from $src (install.sh)"
    fi
  done

  if enabled; then
    ok "$SCRIPT_ID enabled$(loaded && printf ' and loaded')"
  else
    warn "$SCRIPT_ID disabled (System Settings → KWin Scripts)"
  fi

  if [[ "$(layout)" == "$SWITCHER_ID" ]]; then
    if [[ -d "$(script_dir)" ]]; then
      ok "Alt+Tab uses $SWITCHER_ID"
    else
      err "Alt+Tab uses $SWITCHER_ID but $SCRIPT_ID isn't installed: Alt+Tab can't load (install.sh uninstall)"
      fail=1
    fi
  else
    warn "Alt+Tab uses $(layout), not $SWITCHER_ID: no group mosaic"
  fi
  return "$fail"
}

case "${1:-install}" in
  install) cmd_install true ;;
  --no-switcher) cmd_install false ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  doctor) cmd_doctor ;;
  -h | --help) usage ;;
  *)
    err "Unknown command: $1"
    usage >&2
    exit 1
    ;;
esac
