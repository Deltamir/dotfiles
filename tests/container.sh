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
# A local bare repository stands in for GitHub: the user's checkout is a
# clone of it, so pull and push work as on a real machine.
cp -r /src /tmp/seed && rm -rf /tmp/seed/.git
git -C /tmp/seed init -q -b main && git -C /tmp/seed add -A
git -C /tmp/seed -c user.name=ci -c user.email=ci@example.invalid commit -qm seed
git clone -q --bare /tmp/seed /srv/origin.git && chown -R "$U:" /srv/origin.git
su - "$U" -c "git clone -q /srv/origin.git ~/dotfiles"
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

if [ "$MODE" = sudo ]; then
  echo "##### sync and push"
  # Another machine publishes a change.
  git config --global --add safe.directory '*'   # root works in the user's repositories
  upstream() {
    if [ -d /tmp/other ]; then git -C /tmp/other pull -q; else git clone -q /srv/origin.git /tmp/other; fi
    echo "$1" >> /tmp/other/home/zsh/aliases.zsh
    git -C /tmp/other -c user.name=ci -c user.email=ci@example.invalid commit -qam "$1"
    git -C /tmp/other push -q
    chown -R "$U:" /srv/origin.git
  }
  upstream "alias from_elsewhere=true"
  as '~/dotfiles/install.sh --sync' >/tmp/sync1.log 2>&1 || fail "sync exit code"
  as 'grep -q from_elsewhere ~/.zsh-custom/aliases.zsh' || fail "sync did not pull a clean checkout"

  # A local edit (through the ~/.zshrc link) survives the next sync.
  as 'echo "# local edit" >> ~/.zshrc'
  upstream "alias second=true"
  as '~/dotfiles/install.sh --sync' >/tmp/sync2.log 2>&1 || fail "sync exit code"
  as 'grep -q "# local edit" ~/.zshrc' || fail "local edit lost by sync"
  grep -q "pull skipped" /tmp/sync2.log || fail "sync pulled over local changes"

  # An application rewrites a copied file: the change is kept, in the repository.
  as 'echo "# set by gh" >> ~/.config/gh/config.yml'
  as '~/dotfiles/install.sh --sync' >/dev/null 2>&1 || fail "sync exit code"
  as 'grep -q "set by gh" ~/.config/gh/config.yml && grep -q "set by gh" ~/dotfiles/home/config/gh/config.yml' || fail "copied file change lost"

  # A fake secret stops `mise run push`: nothing committed, nothing pushed.
  before=$(git -C /srv/origin.git rev-parse main)
  # A realistic random token: gitleaks ignores low-entropy ones such as ghp_aaaa...
  token="ghp_$(head -c 300 /dev/urandom | base64 -w0 | tr -dc 'A-Za-z0-9' | cut -c1-36)"
  as "echo 'export GITHUB_TOKEN=$token' >> ~/.zsh-custom/aliases.zsh"
  as 'cd ~ && echo y | mise run push' >/tmp/push1.log 2>&1 && fail "push accepted a secret"
  grep -q "possible secret" /tmp/push1.log || { cat /tmp/push1.log; fail "no secret message"; }
  [ "$(git -C /srv/origin.git rev-parse main)" = "$before" ] || fail "secret reached the remote"
  as 'cd ~/dotfiles && git checkout -q -- home/zsh/aliases.zsh'

  # Without the secret: published, with the machine name, after a rebase.
  upstream "alias third=true"
  as 'cd ~ && echo y | mise run push' >/tmp/push2.log 2>&1 || { cat /tmp/push2.log; fail "push"; }
  git -C /srv/origin.git log -1 --format=%s main | grep -q "changes from" || fail "push did not reach the remote"
  git -C /srv/origin.git show main:home/zshrc | grep -q "# local edit" || fail "local edit not published"
  as 'test -z "$(git -C ~/dotfiles status --porcelain)"' || fail "checkout not clean after push"

  # Offline (unreachable origin): the sync still exits 0, quickly, and says so.
  as 'git -C ~/dotfiles remote set-url origin http://10.255.255.1/none.git'
  start=$(date +%s)
  as '~/dotfiles/install.sh --sync' >/tmp/sync4.log 2>&1 || fail "offline sync must exit 0"
  [ $(( $(date +%s) - start )) -lt 120 ] || fail "offline sync too slow"
  grep -q "keeping the local version" /tmp/sync4.log || fail "offline sync message"
fi

echo "ALL CHECKS PASSED ($MODE, $U)"
IN
