# ===============================================================================
# ZSH — nivek-dev
# ===============================================================================
# Portable across Debian machines. Tools degrade gracefully if missing.
# Only hard deps: zsh + git (zinit self-installs on first run).
# ===============================================================================

export LC_TIME="en_US.UTF-8"

# MOTD Tailscale
if [[ -d /etc/update-motd.d ]] && [[ -z "$MOTD_SHOWN" ]] && [[ -n "$SSH_CONNECTION" ]]; then
  local _src_ip="${SSH_CONNECTION%% *}"
  if [[ "$_src_ip" == 100.* ]]; then
    export MOTD_SHOWN=1
    run-parts /etc/update-motd.d 2>/dev/null
  fi
fi

# -- powerlevel10k instant prompt -------------------------------------------- #

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ===============================================================================
# ZINIT + PLUGINS
# ===============================================================================

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [[ ! -d "$ZINIT_HOME" ]]; then
  print -P "%F{blue}:: Installing zinit...%f"
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" && \
    print -P "%F{green}:: Done.%f" || \
    print -P "%F{red}:: Failed — plugins unavailable.%f"
fi

if [[ -f "${ZINIT_HOME}/zinit.zsh" ]]; then
  source "${ZINIT_HOME}/zinit.zsh"

  zinit ice depth=1
  zinit light romkatv/powerlevel10k

  zinit ice wait lucid; zinit light zsh-users/zsh-completions
  zinit ice wait lucid; zinit light Aloxaf/fzf-tab
  zinit ice wait lucid atload"_zsh_autosuggest_start"; zinit light zsh-users/zsh-autosuggestions
  zinit ice wait lucid; zinit light zsh-users/zsh-syntax-highlighting

  zinit ice wait lucid; zinit snippet OMZP::git
  zinit ice wait lucid; zinit snippet OMZP::sudo
fi

autoload -Uz compinit
if [[ -f "${ZDOTDIR:-$HOME}/.zcompdump" ]] && \
   [[ $(date +'%j') == $(date -r "${ZDOTDIR:-$HOME}/.zcompdump" +'%j' 2>/dev/null) ]]; then
  compinit -C
else
  compinit
fi
(( ${+functions[zinit]} )) && zinit cdreplay -q

# tmuxp: lightweight native completion (the stock python one freezes the shell)
compdef -d tmuxp
_tmuxp_fast() {
  local -a subcmds sessions
  subcmds=(load ls kill freeze edit import convert debug info shell)
  _arguments '1:command:compadd -a subcmds' '*:session:->sessions'
  if [[ "$state" == sessions ]]; then
    local dir="${TMUXP_CONFIGDIR:-$HOME/.tmuxp}"
    [[ -d "$dir" ]] && sessions=(${dir}/*.{yaml,yml,json}(N:t:r))
    compadd -a sessions
  fi
}
compdef _tmuxp_fast tmuxp

# Lista de hosts SSH para completado, filtrada por la tailnet activa.
# Lee ~/.ssh/config y ~/.ssh/config.local. En config.local los hosts viven en un
# bloque gestionado por bootstrap, agrupados con cabeceras "#@ group:<gid>":
#   - sin grupo (sueltos / escritos a mano) -> siempre se ofrecen
#   - group:manual                          -> siempre se ofrecen
#   - group:tailnet:<name>                  -> solo si esa tailnet es la activa
# La tailnet activa se detecta con `tailscale switch --list` (fila con '*'); si no
# hay tailscale o tailnet activa, solo se ofrecen sueltos + manual.
#   With -c, emits "class<TAB>name" (class = loose | manual | tailnet) instead of
#   just the name — used by _ssh_hosts_complete to split online/offline/manual.
_ssh_host_list() {
  local classified=0
  [[ "${1:-}" == -c ]] && classified=1

  local cur=""
  (( $+commands[tailscale] )) && \
    cur="$(tailscale switch --list 2>/dev/null | awk 'NR>1 && index($0,"*"){print $2}')"

  local -a cfgs
  [[ -f ~/.ssh/config ]]       && cfgs+=(~/.ssh/config)
  [[ -f ~/.ssh/config.local ]] && cfgs+=(~/.ssh/config.local)
  (( ${#cfgs} )) || return

  awk -v cur="$cur" -v classified="$classified" '
    FNR==1 { inman=0; gid="" }
    /^# >>> dotfiles:ssh-hosts/ { inman=1; gid=""; next }
    /^# <<< dotfiles:ssh-hosts/ { inman=0; gid=""; next }
    inman && /^#@ group:/ { gid=substr($0, length("#@ group:")+1); next }
    /^Host / {
      cls = (gid=="" ? "loose" : (gid=="manual" ? "manual" : \
            ((cur!="" && gid==("tailnet:" cur)) ? "tailnet" : "")))
      if (cls=="") next
      for (i=2; i<=NF; i++) if ($i !~ /[*?]/) {
        if (classified) print cls "\t" $i; else print $i
      }
    }
  ' "${cfgs[@]}" 2>/dev/null
}

# Completion action for ssh hosts: classifies the active tailnet's hosts into
# online/offline (via `tailscale status`) and offers them as one ordered list —
# online (alpha) first, then offline (alpha), then manual/local (alpha) — each
# labelled. Manual/loose hosts are always shown and never reordered among groups.
_ssh_hosts_complete() {
  # Declare every local once (re-declaring an existing local makes zsh print it).
  local -A online cls_of
  local -a online_h offline_h other_h cands disp
  local nm st cls h lbl w=0

  if (( $+commands[tailscale] )); then
    while IFS=$'\t' read -r nm st; do
      online[$nm]=$st
    done < <(tailscale status 2>/dev/null \
      | awk '$1 ~ /^100\./ {print $2"\t"(index($0,"offline") ? "offline" : "online")}')
  fi

  while IFS=$'\t' read -r cls nm; do
    [[ -z "$nm" ]] && continue
    cls_of[$nm]=$cls
    if [[ "$cls" == tailnet ]]; then
      if [[ "${online[$nm]:-offline}" == online ]]; then
        online_h+=("$nm")
      else
        offline_h+=("$nm")
      fi
    else
      other_h+=("$nm")
    fi
  done < <(_ssh_host_list -c)

  online_h=(${(o)online_h})
  offline_h=(${(o)offline_h})
  other_h=(${(o)other_h})

  cands=($online_h $offline_h $other_h)
  (( ${#cands} )) || return

  # Pad names so the status column lines up in the fzf menu.
  for h in $cands; do (( ${#h} > w )) && w=${#h}; done

  for h in $online_h;  do disp+=("${(r:w:)h}   online"); done
  for h in $offline_h; do disp+=("${(r:w:)h}   offline"); done
  for h in $other_h; do
    lbl=manual; [[ "${cls_of[$h]}" == loose ]] && lbl=local
    disp+=("${(r:w:)h}   $lbl")
  done

  # -V: unsorted group -> keep our online/offline/manual order in the fzf menu.
  compadd -V ssh-hosts -d disp -a cands
}

# ssh: flags with proper values + hosts (tailnet-aware, online/offline ordered)
_ssh_hosts_fast() {
  _arguments -s \
    '-i[identity file]:key file:_files' \
    '-p[port]:port number:' \
    '-l[login name]:user:' \
    '-F[config file]:config:_files' \
    '-o[option]:option:' \
    '-J[jump host]:proxy host:_ssh_hosts_complete' \
    '*:host:_ssh_hosts_complete'
}
compdef _ssh_hosts_fast ssh

# scp: offer host: targets + local files
_scp_fast() {
  local -a hosts
  hosts=(${(f)"$(_ssh_host_list)"})
  if [[ "$PREFIX" == *:* ]]; then
    _files
  else
    local -a host_targets=("${hosts[@]/%/:}")
    _alternative \
      'files:local file:_files' \
      'hosts:remote host:compadd -a host_targets'
  fi
}
compdef _scp_fast scp

# tailscale: native completion (sudo delegates automatically via zsh's _sudo)
_tailscale_fast() {
  local -a subcmds
  subcmds=(
    up down set login logout switch status
    ping nc ssh serve funnel cert
    netcheck ip lock licenses exit-node
    update whois drive configure debug version
  )
  if (( CURRENT == 2 )); then
    compadd -a subcmds
  elif (( CURRENT == 3 )) && [[ "${words[2]}" == switch ]]; then
    local -a profiles
    profiles=(${(f)"$(tailscale switch --list 2>/dev/null | awk 'NR>1 {print $2}')"})
    compadd -a profiles
  fi
}
compdef _tailscale_fast tailscale

# ===============================================================================
# ENVIRONMENT
# ===============================================================================

export EDITOR="nvim"
export VISUAL="$EDITOR"

typeset -U path
path=(
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "$HOME/.local/share/gem/ruby/3.3.0/bin"
  "$HOME/.fzf/bin"
  "$HOME/.opencode/bin"
  "/opt/nvim/bin"
  "/sbin"
  "/usr/sbin"
  $path
)

# FNM path
FNM_PATH="$HOME/.local/share/fnm"
if [[ -d "$FNM_PATH" ]]; then
  path=("$FNM_PATH" $path)
  eval "$(fnm env)"
fi

# CARGO (RUST) path
[[ -d "$HOME/.cargo" ]] && export CARGO_INCREMENTAL=1 RUST_LOG=info

# BUN path
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[[ -f "$HOME/.deno/env" ]] && source "$HOME/.deno/env"

# TMUXP path
export TMUXP_CONFIGDIR="$HOME/dev/infra/tmuxp"

# ===============================================================================
# HISTORY
# ===============================================================================

HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
HISTDUP=erase

setopt appendhistory sharehistory
setopt hist_ignore_space hist_ignore_all_dups
setopt hist_save_no_dups hist_ignore_dups hist_find_no_dups

# ===============================================================================
# COMPLETIONS & FZF-TAB
# ===============================================================================

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu no

zstyle ':fzf-tab:complete:cd:*' fzf-preview \
  'eza --icons --group-directories-first --color=auto "$realpath" 2>/dev/null'

zstyle ':fzf-tab:complete:z:*' fzf-preview \
  'target="$(zoxide query -- "$word" 2>/dev/null || printf "%s" "$word")"; \
   eza --icons --group-directories-first --color=auto "$target" 2>/dev/null'

zstyle ':fzf-tab:complete:systemctl:*' disabled-on any

zstyle ':fzf-tab:*' fzf-min-height 15
zstyle ':fzf-tab:*' switch-group '<' '>'

# DENO completions
if [[ ":$FPATH:" != *":/home/nivek/.zsh/completions:"* ]]; then export FPATH="/home/nivek/.zsh/completions:$FPATH"; fi

# BUN completions
[ -s "/home/nivek/.bun/_bun" ] && source "/home/nivek/.bun/_bun"

# ===============================================================================
# FUNCTIONS
# ===============================================================================

function y() {
  local tmp cwd
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [[ -n "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}

txl() {
  local dir="${TMUXP_CONFIGDIR:-$HOME/.tmuxp}"
  local -a sessions
  local session

  # Obtener sesiones usando glob nativo de zsh (sin ls)
  sessions=(${dir}/*.{yaml,yml,json}(N:t:r))

  # Si no hay configs
  (( ${#sessions[@]} == 0 )) && {
    echo "No hay sesiones en $dir"
    return 1
  }

  # Selector con fzf si existe, fallback simple si no
  if command -v fzf >/dev/null 2>&1; then
    session=$(printf "%s\n" "${sessions[@]}" | fzf)
  else
    echo "Sesiones disponibles:"
    printf "%s\n" "${sessions[@]}"
    return 0
  fi

  # Si cancelas fzf
  [[ -z "$session" ]] && return 0

  # Si ya existe la sesión → attach
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux attach -t "$session"
  else
    tmuxp load "$session"
  fi
}

# ===============================================================================
# ALIASES
# ===============================================================================

alias ls="eza --icons --group-directories-first --color=auto"
alias ll="eza -lah --icons --group-directories-first"
alias lt="eza -T --level=2 --icons --group-directories-first"
alias la="eza -a --icons --group-directories-first"
alias ..="cd .."
alias ...="cd ../.."
alias mkdir="mkdir -p"
alias ip="ip -c"
alias vim="nvim"
alias fvim="nvim -u NONE"
alias bat="batcat"
alias fd="fdfind"
alias cmatrix="cmatrix -C blue"
alias lavat="lavat -c cyan -k magenta -R 3"

# ===============================================================================
# INTEGRATIONS
# ===============================================================================

[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# ===============================================================================
# KEYBINDINGS
# ===============================================================================

bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

# ===============================================================================
# INIT
# ===============================================================================

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
[[ -f "${ZDOTDIR:-$HOME}/.zshrc.local" ]] && source "${ZDOTDIR:-$HOME}/.zshrc.local"
