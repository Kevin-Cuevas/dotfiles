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

# ===============================================================================
# ENVIRONMENT
# ===============================================================================

export EDITOR="nvim"
export VISUAL="$EDITOR"
export SYSTEMD_EDITOR="$EDITOR"

typeset -U path
path=(
  "$HOME/.local/bin"
  "$HOME/.cargo/bin"
  "$HOME/.local/share/gem/ruby/3.3.0/bin"
  "$HOME/.fzf/bin"
  "$HOME/.opencode/bin"
  "/opt/nvim/bin"
  "/opt/tmux/bin"
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

# dotfiles zsh-completions package (originally added by the Deno installer,
# now the fpath entry for our own completions/ — see zsh-completions/)
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
