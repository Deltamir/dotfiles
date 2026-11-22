#!/usr/bin/env bash
# Run install.sh twice in a fresh container, as a non-root user.
#   tests/container.sh <image> <sudo|nosudo> [user]
# The second run must change nothing. Used by CI and locally (needs docker).
set -euo pipefail
image="$1"; mode="$2"; user="${3:-dev}"
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
# EXTRA_CA: a CA file to trust inside the container (TLS-intercepting proxy
# on a dev machine). Not used in CI.
ca=()
[ -n "${EXTRA_CA:-}" ] && ca=(-v "$EXTRA_CA:/extra-ca.crt:ro")
docker run --rm -i -v "$repo:/src:ro" "${ca[@]}" -e MODE="$mode" -e U="$user" "$image" bash -s <<'IN'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if [ -f /extra-ca.crt ]; then
  apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates >/dev/null
  cp /extra-ca.crt /usr/local/share/ca-certificates/extra.crt && update-ca-certificates >/dev/null
fi
# What any machine that cloned this repository has: git, curl, sudo, a user.
if ! command -v sudo >/dev/null || ! command -v curl >/dev/null || ! command -v git >/dev/null; then
  apt-get update -qq && apt-get install -y -qq --no-install-recommends sudo curl git ca-certificates >/dev/null
fi
id "$U" >/dev/null 2>&1 || useradd -m -s /bin/bash "$U"
if [ "$MODE" = sudo ]; then
  echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$U
else
  rm -f /etc/sudoers.d/* 2>/dev/null || true
  # Without sudo, install.sh skips the system packages: this simulates a
  # machine where they were installed once by hand (`mise bootstrap packages
  # apply` asks for the password). node needs libatomic1 from them.
  apt-get install -y -qq --no-install-recommends libatomic1 >/dev/null
fi
home=$(getent passwd "$U" | cut -d: -f6)
cp -r /src "$home/dotfiles" && chown -R "$U:" "$home/dotfiles"
run() { su - "$U" -c "cd ~ && ./dotfiles/install.sh"; }
echo "##### run 1"; run
echo "##### run 2"; run 2>&1 | tee /tmp/run2.log
echo "##### checks"
fail() { echo "CHECK FAILED: $*"; exit 1; }
# Idempotence: the second run must not change anything.
if grep -E 'installing mise|linked |moved existing|created symlink|copied |rendered |Cloning|applied ~|Setting up ' /tmp/run2.log; then
  fail "second run changed something (lines above)"
fi
as() { su - "$U" -c "$1"; }
as 'test -L ~/.zshrc && test -L ~/.zsh-custom/prompt.zsh && test -f ~/.oh-my-zsh/oh-my-zsh.sh' || fail "files"
as 'grep -q "$HOME/.local/share/mise/shims/gh auth" ~/.gitconfig' || fail "gitconfig template"
as 'test "$(stat -c %a ~/.aws/config)" = 600' || fail "aws config permissions"
# The original ~/.bashrc from /etc/skel is kept, not overwritten.
as 'ls ~/.local/state/dotfiles/backup/*/.bashrc' || fail "backup of the original ~/.bashrc"
as 'grep -rnE "(^|[[:space:]\"=:!])/(home|root)/" ~/.dotfiles/home ~/.dotfiles/config' && fail "hard-coded home path"
if [ "$MODE" = sudo ]; then
  as 'zsh -ic "command -v gh && echo zsh-ok"' 2>&1 | tail -2 | grep -q zsh-ok || fail "zsh with mise tools"
  # Kali-like shell on every distribution: the two-line prompt and the plugins.
  # One symbol per kind of machine (home/zsh/prompt.zsh). WSL and VS Code set
  # the variables in the terminal's environment; here they are set by hand.
  sym() { as "$1 zsh -ic 'print -r -- \$PROMPT'" 2>/dev/null | grep -q "┌──.*$2" || fail "prompt symbol $2 ($1)"; }
  if grep -qx 'ID=kali' /etc/os-release; then sym "" "㉿"; else sym "" "@"; fi
  sym "REMOTE_CONTAINERS=true" "⬢"
  sym "WSL_DISTRO_NAME=Debian" "⊞"
  as 'zsh -ic "(( \$+functions[_zsh_autosuggest_start] )) && (( \$+functions[_zsh_highlight] )) && echo plugins-ok"' 2>/dev/null | grep -q plugins-ok || fail "zsh plugins"
  # Kali behaviours that Oh My Zsh would otherwise change: Ctrl+P prompt
  # toggle, Kali's highlighting colours, one history per terminal.
  as 'zsh -ic "bindkey ^P"' 2>/dev/null | grep -q toggle_oneline_prompt || fail "Ctrl+P prompt toggle"
  as 'zsh -ic "print -r -- \${ZSH_HIGHLIGHT_STYLES[unknown-token]}"' 2>/dev/null | grep -qx underline || fail "Kali highlighting colours"
  as 'zsh -ic "[[ -o sharehistory ]] || echo separate"' 2>/dev/null | grep -q separate || fail "history not shared between terminals"
else
  grep -q "system packages skipped" /tmp/run2.log || fail "no-sudo message"
  as 'bash -ic "command -v gh"' >/dev/null 2>&1 || fail "tools without sudo"
fi
echo "ALL CHECKS PASSED ($MODE, $U)"
IN
