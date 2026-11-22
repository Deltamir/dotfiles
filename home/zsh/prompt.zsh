PROMPT_ALTERNATIVE=twoline
NEWLINE_BEFORE_PROMPT=yes

# The symbol between user and host tells at a glance where you type.
# Container first: a devcontainer built on the Kali image also says ID=kali.
if [[ -n $REMOTE_CONTAINERS || -n $CODESPACES ]]; then
  prompt_symbol="⬢"     # VS Code devcontainer
elif [[ -n $WSL_DISTRO_NAME ]]; then
  prompt_symbol="⊞"     # WSL
elif grep -qx 'ID=kali' /etc/os-release 2>/dev/null; then
  prompt_symbol="㉿"    # Kali (Sarasvati)
else
  prompt_symbol="@"
fi


ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}%1{✗%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"

configure_prompt() {
case "$PROMPT_ALTERNATIVE" in
  twoline)
    PROMPT=$'%F{%(#.blue.green)}┌──${debian_chroot:+($debian_chroot)─}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))─}(%B%F{%(#.red.blue)}%n'$prompt_symbol$'%m%b%F{%(#.blue.green)})-[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]
└─%B%(#.%F{red}#.%F{blue}$)%b%F{reset} '
    ;;
  oneline)
    PROMPT=$'${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%B%F{%(#.red.blue)}%n@%m%b%F{reset}:%B%F{%(#.blue.green)}%~%b%F{reset}%(#.#.$) '
    ;;
esac
}


# Add newline before each prompt (except very first)
precmd() {
  if [ "$NEWLINE_BEFORE_PROMPT" = yes ]; then
    if [ -z "$_NEW_LINE_BEFORE_PROMPT" ]; then
      _NEW_LINE_BEFORE_PROMPT=1
    else
      print ""
    fi
  fi
}


configure_prompt

# Ctrl+P: switch between the two-line and the one-line prompt, as on Kali.
toggle_oneline_prompt() {
  if [ "$PROMPT_ALTERNATIVE" = oneline ]; then
    PROMPT_ALTERNATIVE=twoline
  else
    PROMPT_ALTERNATIVE=oneline
  fi
  configure_prompt
  zle reset-prompt
}
zle -N toggle_oneline_prompt
bindkey '^P' toggle_oneline_prompt
