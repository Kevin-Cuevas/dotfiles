# ===============================================================================
# ZSH — nivek-dev
# ===============================================================================
# Portable across Debian machines. Tools degrade gracefully if missing.
# Only hard deps: zsh + git (zinit self-installs on first run).
# ===============================================================================

# `ZPROF=1 zsh` (o `just profile`) => perfil de funciones del arranque al final
# del archivo. Sin la variable no carga nada.
if [[ -n $ZPROF ]]; then zmodload zsh/zprof; fi

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

# Our own completions dir must be on fpath BEFORE compinit scans it. It holds
# the zsh-completions/ package (_ssh, _mycli, _tailscale, _tmuxp) plus any file
# a dev-* CLI drops here on its own host (e.g. `dev-pagipage-domains
# --set-autocompletions` on nivek-core -> ~/.zsh/completions/_dev-pagipage-domains).
# Added after compinit it only ever worked by luck: a stale ~/.zcompdump, or a
# $FPATH inherited from an already-running zsh. On a fresh machine (first login
# shell, dump just cleared by bootstrap) neither holds, so the completions went
# missing until the next day's full compinit — the nivek-core symptom.
if [[ " ${fpath[*]} " != *" $HOME/.zsh/completions "* ]]; then
  fpath=("$HOME/.zsh/completions" $fpath)
fi

# Fast path (compinit -C: load the dump, no fpath rescan) unless the dump is
# missing or ANY $fpath dir is newer than it. A dir's mtime bumps whenever an
# entry is added/removed: a stow symlink in ~/.zsh/completions (whose repo
# target may have an old mtime), a file a dev-* CLI drops in, apt installing
# into /usr/share/zsh/vendor-completions, a zinit plugin update... so a new
# completion shows up on the very next shell. It's ~25 stat() calls, ~free.
# Editing an existing _* file's body needs no rescan: zsh autoloads it fresh.
# This replaced a "dump is from today" rule that paid a full ~650 ms rescan on
# the first shell of every day and still missed same-day apt installs.
# After a full rescan the dump is touched: compinit only rewrites it when the
# file count changes, and an untouched old dump would rescan on every shell.
# The dump is then zcompile'd in the background (`&!`: never waited on); zsh
# loads the .zwc instead whenever it's newer. Anon function: no leaked vars.
autoload -Uz compinit
() {
  local zcd="${ZDOTDIR:-$HOME}/.zcompdump" dir
  local -i stale=0

  [[ -f $zcd ]] || stale=1
  for dir in $fpath; do
    (( stale )) && break
    [[ $dir -nt $zcd ]] && stale=1
  done

  if (( stale )); then
    compinit -d "$zcd" && touch "$zcd"
  else
    compinit -C -d "$zcd"
  fi

  { [[ -s $zcd && ( ! -s $zcd.zwc || $zcd -nt $zcd.zwc ) ]] && zcompile "$zcd" } &!
}
(( ${+functions[zinit]} )) && zinit cdreplay -q

# ===============================================================================
# ENVIRONMENT
# ===============================================================================

export EDITOR="nvim"
export VISUAL="$EDITOR"
export SYSTEMD_EDITOR="$EDITOR"

SDKMAN_DIR="$HOME/.sdkman"

# Every entry ends in (N-/): a dir that doesn't exist on this machine is simply
# dropped (no per-tool `if`), and the globs match any version (ruby gems,
# every SDKMAN candidate's `current`). Unquoted on purpose so they expand.
typeset -U path
path=(
  $HOME/.local/bin(N-/)
  $HOME/.cargo/bin(N-/)
  $HOME/.bun/bin(N-/)
  $HOME/.local/share/gem/ruby/*/bin(N-/)
  $SDKMAN_DIR/candidates/*/current/bin(N-/)
  $HOME/.fzf/bin(N-/)
  $HOME/.opencode/bin(N-/)
  /opt/nvim/bin(N-/)
  /opt/tmux/bin(N-/)
  /sbin(N-/)
  /usr/sbin(N-/)
  $path
)

# sudoedit needs an absolute path (sudo's secure_path doesn't know /opt/nvim).
# $commands is zsh's command hash: resolves wherever nvim lives on this host.
export SUDO_EDITOR="${commands[nvim]:-nvim}"

# FNM path. `fnm env` costs ~40 ms (a process + a per-shell "multishell"
# symlink, so its output can't be cached): it runs in zinit turbo, right after
# the first prompt. Without zinit it just runs inline.
FNM_PATH="$HOME/.local/share/fnm"
if [[ -d "$FNM_PATH" ]]; then
  path=("$FNM_PATH" $path)
  if (( ${+functions[zinit]} )); then
    zinit ice wait lucid id-as'fnm-env' atload'eval "$(fnm env)"'
    zinit light zdharma-continuum/null
  else
    eval "$(fnm env)"
  fi
fi

# CARGO (RUST) path
[[ -d "$HOME/.cargo" ]] && export CARGO_INCREMENTAL=1 RUST_LOG=info

# BUN (its bin is in the path block above)
[[ -d "$HOME/.bun" ]] && export BUN_INSTALL="$HOME/.bun"
[[ -f "$HOME/.deno/env" ]] && source "$HOME/.deno/env"

# SDKMAN (java). PATH (path block above) and JAVA_HOME are static: they point
# at candidates/<x>/current, the symlink `sdk default` repoints, so `java`
# resolves exactly as it did with sdkman-init. Only the `sdk` command is lazy:
# its ~30 ms init runs the first time you call it, then the stub is replaced.
# Nothing else is lost while sdkman_auto_env=false (~/.sdkman/etc/config); if
# that ever changes, source sdkman-init.sh here again instead.
if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
  export SDKMAN_DIR
  [[ -d "$SDKMAN_DIR/candidates/java/current" ]] \
    && export JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
  sdk() {
    unfunction sdk
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
    sdk "$@"
  }
fi

# TMUXP path
export TMUXP_CONFIGDIR="$HOME/dev/infra/tmuxp"

# ===============================================================================
# HISTORY
# ===============================================================================

HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

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

# (the fpath entry for our zsh-completions/ package now lives above compinit —
# it has to be scanned before compinit runs)

# BUN completions
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

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

# `if`, not `&&`: a trailing false test would leave $? = 1 for the first prompt.
if [[ -n $ZPROF ]]; then zprof; fi
