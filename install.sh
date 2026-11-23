#!/usr/bin/env bash
# Single, idempotent entry point for every machine: VS Code devcontainers
# (dotfiles.installCommand), WSL by hand, the Sarasvati VM. Re-running it only
# changes what differs from the config.
#
#   ./install.sh                   install or update; any error is fatal
#   ./install.sh --identity <url>  also use this identity repository (see below);
#                                  replaces the current one, if any
#   ./install.sh --identity none   drop the identity layer
#   ./install.sh --sync            at login (dotfiles-sync unit): pull the
#                                  repositories first when nothing is modified
#                                  locally; never fails the login, a network
#                                  error is logged and the local version is kept
#
# What it does:
#   1. install mise (pinned version, checksum verified) into ~/.local/bin
#   2. link ~/.dotfiles -> this repository, ~/.config/mise -> config/mise
#   3. identity layer: clone or swap the identity repository
#   4. mise bootstrap: apt packages (only with passwordless sudo), Oh My Zsh,
#      files, tools, then the checks of [tasks.bootstrap]
#
# Identity layer: who you are on this machine (Git name and email, AWS
# profiles, work-only tools), kept out of this public repository. A Git
# repository with a mise.toml at its root, cloned to IDENTITY_DIR, linked as
# ~/.dotfiles-identity, its mise.toml linked into config/mise/conf.d/ where mise
# merges it with config.toml. Its files form the dotfile group "identity", so
# swapping identities removes the previous one's files (`mise dot unapply
# --group identity`) before the next one is applied. See README.md.
# Log: ~/.local/state/dotfiles/install.log
set -euo pipefail

MISE_VERSION="2026.11.12"
declare -A MISE_SHA256=(
  [x64]="4b029e19afc575875a4962dfe5d5e31cc93ab0317242768d0234adec219d3e14"
  [arm64]="9a125763f8445ea28d2da0e943fe5ad7d81b397d78f173cc07c1cc18ee2bee47"
)

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
BIN="$HOME/.local/bin"
IDENTITY_DIR="$HOME/.local/share/dotfiles-identity"
IDENTITY_LINK="$HOME/.dotfiles-identity"
IDENTITY_CONF="$REPO/config/mise/conf.d/identity.toml"
mkdir -p "$STATE" "$BIN"

log() { echo "[dotfiles] $*"; }
usage() { echo "usage: $0 [--identity <git url>|none] | --sync" >&2; exit 2; }

MODE=install
IDENTITY=""   # empty: keep the current identity
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) [ $# -ge 2 ] && [ -n "$2" ] || usage; IDENTITY="$2"; shift 2 ;;
    --sync | --sync-run | --sync-pulled) MODE="$1"; shift ;;
    *) usage ;;
  esac
done

case "$MODE" in
  install | --sync-run | --sync-pulled) ;;
  --sync)
    # Login must never fail because of the dotfiles: run the real sync in a
    # child process, log its failure, return 0.
    rc=0
    "$REPO/install.sh" --sync-run || rc=$?
    [ "$rc" -eq 0 ] || log "sync failed (exit $rc): the local version stays in place, see $STATE/install.log"
    exit 0
    ;;
esac

# Once per run: the --sync-run -> --sync-pulled exec keeps the same log pipe.
if [ -z "${DOTFILES_LOG_OPEN:-}" ]; then
  export DOTFILES_LOG_OPEN=1
  exec > >(tee -a "$STATE/install.log") 2>&1
fi
echo "=== install.sh $MODE $(date -u +%FT%TZ) repo=$REPO user=$(id -un)"

# --- 0. sync: pull, then restart on the pulled version ---------------------------
if [ "$MODE" = --sync-run ]; then
  # Network steps get short timeouts: on a client network without Internet the
  # login goes on with the local version.
  export MISE_HTTP_TIMEOUT=20s MISE_FETCH_REMOTE_VERSIONS_TIMEOUT=20s
  export PATH="$BIN:$PATH"
  # An application that rewrote a copied file (gh, aws) would lose its change
  # when the copy is applied again: bring those changes into the repository
  # first. They then count as local changes, like any edit through a link.
  if command -v mise >/dev/null 2>&1; then
    mise dot add --changed --yes || log "could not capture rewritten copies"
  fi
  # No credential prompt at login: a private identity repository without
  # stored credentials is skipped like an unreachable one.
  export GIT_TERMINAL_PROMPT=0
  pull() {
    if [ -n "$(git -C "$1" status --porcelain)" ]; then
      log "local changes in $1: pull skipped (publish them with: mise run push)"
    elif timeout 20 git -C "$1" pull --ff-only -q; then
      log "pulled $1: $(git -C "$1" log -1 --format='%h %s')"
    else
      log "pull of $1 failed or not a fast-forward: keeping the local version"
    fi
  }
  pull "$REPO"
  if [ -d "$IDENTITY_DIR/.git" ]; then pull "$IDENTITY_DIR"; fi
  # install.sh itself may have changed: bash reads a script while running it,
  # so continue in a fresh process on the pulled file.
  exec "$REPO/install.sh" --sync-pulled
fi

# A real file or directory where a link must go is moved aside, never deleted.
backup() {
  local path="$1" dest
  dest="$STATE/backup/$(date -u +%Y%m%dT%H%M%SZ)${path#"$HOME"}"
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
  log "moved existing $path to $dest"
}

link() {
  local target="$1" source="$2"
  if [ -L "$target" ]; then
    [ "$(readlink "$target")" = "$source" ] && return 0
    rm "$target"
  elif [ -e "$target" ]; then
    backup "$target"
  fi
  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
  log "linked $target -> $source"
}

# --- 1. mise ---------------------------------------------------------------------
install_mise() {
  local arch tarball tmp
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  tarball="mise-v${MISE_VERSION}-linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  log "installing mise $MISE_VERSION ($arch)"
  curl -fsSL --retry 3 --max-time 120 -o "$tmp/$tarball" \
    "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/${tarball}"
  echo "${MISE_SHA256[$arch]}  $tmp/$tarball" | sha256sum -c --quiet -
  tar -xzf "$tmp/$tarball" -C "$tmp"
  install -m 0755 "$tmp/mise/bin/mise" "$BIN/mise"
  rm -r "$tmp"
}

export PATH="$BIN:$PATH"
if ! command -v mise >/dev/null 2>&1 || [ "$(mise --version | cut -d' ' -f1)" != "$MISE_VERSION" ]; then
  install_mise
fi

# --- 2. links to the repository --------------------------------------------------
# ~/.dotfiles gives the config a fixed path to its sources wherever the repository
# was cloned (~/dotfiles for VS Code, ~/.local/share/dotfiles for Sarasvati).
link "$HOME/.dotfiles" "$REPO"
link "${XDG_CONFIG_HOME:-$HOME/.config}/mise" "$REPO/config/mise"

# --- 3. identity layer -------------------------------------------------------------
identity_url() { git -C "$IDENTITY_DIR" remote get-url origin 2>/dev/null || true; }

# Remove the current identity: its files, its clone, its links. Refused while
# it holds work that exists nowhere else: an application's rewrite of a copied
# file (captured first), a commit not pushed.
drop_identity() {
  [ -d "$IDENTITY_DIR" ] || { rm -f "$IDENTITY_LINK" "$IDENTITY_CONF"; return 0; }
  mise dot add --changed --yes >/dev/null || true
  local dirty ahead
  dirty="$(git -C "$IDENTITY_DIR" status --porcelain)"
  ahead="$(git -C "$IDENTITY_DIR" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  if [ -n "$dirty" ] || [ "$ahead" != 0 ]; then
    echo "The identity $(identity_url) holds changes not published:" >&2
    git -C "$IDENTITY_DIR" status --short >&2
    echo "Publish them (mise run push) or discard them in $IDENTITY_DIR, then run again." >&2
    exit 1
  fi
  log "removing the identity $(identity_url)"
  mise dot unapply --group identity --force --yes
  # Its user, written to ~/.gitconfig by this script.
  git config -f "$HOME/.gitconfig" --remove-section user 2>/dev/null || true
  if [ -f "$HOME/.gitconfig" ] && ! grep -q '[^[:space:]]' "$HOME/.gitconfig"; then rm -f "$HOME/.gitconfig"; fi
  rm -f "$IDENTITY_LINK" "$IDENTITY_CONF"
  rm -rf "$IDENTITY_DIR"
}

if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "$(identity_url)" ]; then
  drop_identity
  if [ "$IDENTITY" != none ]; then
    log "cloning the identity $IDENTITY"
    git clone -q "$IDENTITY" "$IDENTITY_DIR"
    if [ ! -f "$IDENTITY_DIR/mise.toml" ]; then
      rm -rf "$IDENTITY_DIR"
      echo "$IDENTITY has no mise.toml at its root: not an identity repository." >&2
      exit 1
    fi
  fi
fi
if [ -d "$IDENTITY_DIR" ]; then
  link "$IDENTITY_LINK" "$IDENTITY_DIR"
  mkdir -p "$(dirname "$IDENTITY_CONF")"
  link "$IDENTITY_CONF" "$IDENTITY_LINK/mise.toml"
fi

# Git: the common settings are ~/.config/git/config (mise template);
# ~/.gitconfig holds [user] only. It used to be the rendered template: set that
# copy aside (it holds this machine's paths), keeping its [user].
gitconfig="$HOME/.gitconfig"
if [ -f "$gitconfig" ] && [ ! -L "$gitconfig" ] && grep -q 'auth git-credential' "$gitconfig"; then
  old_name="$(git config -f "$gitconfig" --get user.name || true)"
  old_email="$(git config -f "$gitconfig" --get user.email || true)"
  backup "$gitconfig"
  if [ -n "$old_name" ]; then git config -f "$gitconfig" user.name "$old_name"; fi
  if [ -n "$old_email" ]; then git config -f "$gitconfig" user.email "$old_email"; fi
fi
# With an identity, its user goes to ~/.gitconfig: VS Code copies that file into
# devcontainers. Without one (a devcontainer), ~/.gitconfig is never touched:
# it is VS Code's copy of the host's, made before or after this script.
if [ -d "$IDENTITY_DIR" ]; then
  for key in user.name user.email; do
    value="$(git config -f "$IDENTITY_LINK/home/dot-gitconfig.identity" --get "$key" || true)"
    if [ -n "$value" ] && [ "$(git config -f "$gitconfig" --get "$key" || true)" != "$value" ]; then
      git config -f "$gitconfig" "$key" "$value"
      log "Git $key from the identity in ~/.gitconfig"
    fi
  done
fi

# --- 4. bootstrap ---------------------------------------------------------------
args=(--yes --force-dotfiles)
if [ "$MODE" = --sync-pulled ]; then
  # Applying the units from inside dotfiles-sync would stop dotfiles-sync.
  args+=(--skip linux-systemd-units)
fi
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
  log "passwordless sudo: system packages included"
elif [ -t 0 ]; then
  log "sudo needs a password: system packages included, asking for it now"
  # Ask here: this script's output goes through tee (the log), so mise sees
  # no terminal and its sudo cannot prompt. sudo -v reads the password from
  # the terminal and caches it; mise's sudo then runs without asking.
  sudo -v
else
  args+=(--skip packages --skip files)
  log "no passwordless sudo: system packages skipped."
  log "  install them with: mise bootstrap packages apply   (asks for your password)"
fi


# Real files where mise puts links (a fresh ~/.bashrc from /etc/skel, a chezmoi
# copy) stop the run; --force-dotfiles replaces them, so keep a copy first.
# The pretty-printed JSON is read with awk: jq may not be installed yet.
conflicts() {
  mise dot status --json 2>/dev/null | awk -F'"' '
    $2 == "target" { t = $4 }
    $2 == "reason" && $4 ~ /not a symlink/ { print t }'
}
while IFS= read -r target; do
  target="${target/#\~/$HOME}"
  if [ -n "$target" ] && [ -e "$target" ] && [ ! -L "$target" ]; then
    backup "$target"
  fi
done < <(conflicts)

mise bootstrap "${args[@]}"

# --- 5. verify ------------------------------------------------------------------
mise dot status --missing
log "done"
