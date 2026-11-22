### ------------------------------------------------------------
###  Zsh Completion — Optimized & Enhanced
### ------------------------------------------------------------

# Load and activate completion system
autoload -Uz compinit
compinit -u

# Enable completion menu with nice UI
zstyle ':completion:*' menu select

# Better matching: case-insensitive, partial-word, and abbreviations
zstyle ':completion:*' matcher-list \
    'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=* r:|=*' \
    'l:|=* r:|=*'

# Use colors consistent with LS_COLORS
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Show what we are completing
zstyle ':completion:*' verbose yes
zstyle ':completion:*' format '%B%F{yellow}Completing %d…%f%b'
zstyle ':completion:*' group-name ''

# Long list when pressing Tab multiple times
zstyle ':completion:*' list-prompt '%SAt %p: press TAB for more, or a character to insert%s'
zstyle ':completion:*' select-prompt '%SScrolling: %p (TAB to move)%s'

# Rehash automatically (useful when installing commands)
zstyle ':completion:*' rehash true

# Fix for OMZ: prefer compinit over legacy compctl
zstyle ':completion:*' use-compctl false

# Don’t add menu items that would duplicate entries
zstyle ':completion:*' accept-exact '*(N)'

# Add processes list to kill completion
zstyle ':completion:*:kill:*' command \
  "ps -u $USER -o pid,%cpu,tty,cputime,cmd"

# Enable hidden files completion if dot typed
zstyle ':completion:*' special-dirs true

# Faster autocomplete caching
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/zsh

### ------------------------------------------------------------
###  Small usability improvements
### ------------------------------------------------------------

# Prevent completion from overwriting the command line
setopt NO_LIST_BEEP
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END

# Tab-complete “cd” paths even if typed anywhere
zstyle ':completion:*:cd:*' tag-order local-directories directory-stack

### ------------------------------------------------------------
### End of completion setup
### ------------------------------------------------------------
