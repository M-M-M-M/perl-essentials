export ZSH=/opt/oh-my-zsh
export ZSH_THEME=
export DISABLE_AUTO_UPDATE=true
export DISABLE_UPDATE_PROMPT=true
export XDG_CACHE_HOME="${TMPDIR:-/tmp}/xdg-${EUID}"
export ZSH_COMPDUMP="${TMPDIR:-/tmp}/.zcompdump-${EUID}"
export ZSH_CACHE_DIR="${TMPDIR:-/tmp}/oh-my-zsh-${EUID}"

source "$ZSH/oh-my-zsh.sh"

if [[ $EUID -eq 0 ]]; then
  PROMPT='[%n@%m][%h][%~] #'
else
  PROMPT='[%n@%m][%h][%~] >'
fi

alias ls='ls -F'
alias l='ls -m'
alias ll='ls -Fl'
alias d='ls -Fl'
alias c='clear'
