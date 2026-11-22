#!/usr/bin/env bash
# Single, idempotent entry point for every machine: VS Code devcontainers
# (dotfiles.installCommand), WSL by hand, the Sarasvati VM. Re-running it only
# changes what differs from the config.
#
#   ./install.sh          install or update; any error is fatal
#   ./install.sh --sync   at login (dotfiles-sync unit): pull the repository first
#                         when nothing is modified locally; never fails the login,
#                         a network error is logged and the local version is kept
#
# What it does:
#   1. install mise (pinned version, checksum verified) into ~/.local/bin
#   2. link ~/.dotfiles -> this repository, ~/.config/mise -> config/mise
#   3. mise bootstrap: apt packages (only with passwordless sudo), Oh My Zsh,
#      files, tools, then the checks of [tasks.bootstrap]
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
MODE="${1:-install}"
mkdir -p "$STATE" "$BIN"

log() { echo "[dotfiles] $*"; }

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
  *) echo "usage: $0 [--sync]" >&2; exit 2 ;;
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
  if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
    log "local changes in $REPO: pull skipped (publish them with: mise run push)"
  elif timeout 20 git -C "$REPO" pull --ff-only -q; then
    log "pulled $(git -C "$REPO" log -1 --format='%h %s')"
  else
    log "pull failed or not a fast-forward: keeping the local version"
  fi
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

# --- 3. bootstrap ---------------------------------------------------------------
args=(--yes --force-dotfiles)
if [ "$MODE" = --sync-pulled ]; then
  # Applying the units from inside dotfiles-sync would stop dotfiles-sync.
  args+=(--skip linux-systemd-units)
fi
if [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null; then
  log "passwordless sudo: system packages included"
elif [ -t 0 ]; then
  log "sudo needs a password: system packages included, sudo will ask for it"
else
  args+=(--skip packages)
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

# --- 4. verify ------------------------------------------------------------------
mise dot status --missing
log "done"
