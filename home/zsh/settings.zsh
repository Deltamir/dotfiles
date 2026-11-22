###
# Core ZSH options
###


setopt autocd
setopt interactivecomments
setopt magicequalsubst
setopt nonomatch
setopt notify
setopt numericglobsort
setopt promptsubst


WORDCHARS='_-'


### History ###
HISTFILE=~/.zsh_history
HISTSIZE=5000
SAVEHIST=5000
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_verify
# Kali keeps one history per terminal; OMZ turns sharing on, which mixes the
# commands of parallel terminals (one per target during an engagement).
unsetopt share_history
alias history="history 0"   # whole history, as on Kali

# `time` output and coloured man pages, as on Kali
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'
export MANROFFOPT="-c"


### Colors / ls / grep / diff ###
if command -v dircolors >/dev/null; then
  eval "$(dircolors -b)"
  export LS_COLORS="$LS_COLORS:ow=30;44:"   # readable 777 directories, as on Kali
  alias ls='ls --color=auto'
  alias grep='grep --color=auto'
  alias diff='diff --color=auto'
  alias egrep='egrep --color=auto'
  alias fgrep='fgrep --color=auto'
  alias ip='ip --color=auto'
  alias diff='diff --color=auto'

fi


### less colors ###
export LESS_TERMCAP_mb=$'\E[1;31m'
export LESS_TERMCAP_md=$'\E[1;36m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;33m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_us=$'\E[1;32m'
export LESS_TERMCAP_ue=$'\E[0m'
