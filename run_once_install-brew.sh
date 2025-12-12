#!/usr/bin/env bash
set -euo pipefail

echo "==> Installation de Homebrew…"

# Détermine si Homebrew est déjà installé
if ! command -v brew >/dev/null 2>&1; then
  # Linux
  else
    echo "→ Installation Linuxbrew"
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Ajoute Linuxbrew automatiquement au PATH
    if ! grep -q "brew shellenv" ~/.zprofile 2>/dev/null ; then
      echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
  fi

else
  echo "Homebrew déjà installé ✔"
fi

# Charge brew dans le PATH pour l’install des packages
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null || true)"
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
eval "$(/usr/local/bin/brew shellenv 2>/dev/null || true)"

#echo "==> Installation de Chezmoi via Homebrew…"
#brew install chezmoi

#echo "==> Application de la configuration Chezmoi…"
#chezmoi apply -v

#echo "✔ Installation terminée !"
