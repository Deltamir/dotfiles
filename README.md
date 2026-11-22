# dotfiles

Mon environnement de travail, le même partout : WSL, mes devcontainers, la VM
Sarasvati (Kali). Un seul outil, [mise](https://mise.jdx.dev), installe les
paquets système de base, les outils (gh, glab, terraform, kubectl…) et dépose
les fichiers de config. Un seul point d'entrée : `install.sh`.

```
install.sh              point d'entrée unique, idempotent
config/mise/config.toml LA config : paquets, Oh My Zsh, fichiers, outils, vérifications
home/                   sources des fichiers déployés (zshrc, zsh/, gitconfig.tmpl, gh, aws)
tests/container.sh      install.sh deux fois dans un conteneur (utilisé par la CI)
```

`install.sh` installe mise (version épinglée, somme de contrôle vérifiée) dans
`~/.local/bin`. Il crée ensuite deux liens, `~/.dotfiles` vers le repo et
`~/.config/mise` vers `config/mise`, puis lance `mise bootstrap`. Cette config
devient la config **globale** de mise : les outils sont actifs dans tous les
dossiers, pas seulement dans le repo. Log : `~/.local/state/dotfiles/install.log`.

## Installer

| Machine | Comment |
|---|---|
| WSL | `git clone https://github.com/Deltamir/dotfiles ~/dotfiles && ~/dotfiles/install.sh` |
| Devcontainers | réglages VS Code (utilisateur) ci-dessous : clone et lancement à chaque création de conteneur |
| VM Sarasvati | le rôle `dotfiles` de Sarasvati clone le repo et lance `install.sh` |

```json
{
  "dotfiles.repository": "Deltamir/dotfiles",
  "dotfiles.targetPath": "~/dotfiles",
  "dotfiles.installCommand": "install.sh"
}
```

**Paquets système (apt)** : installés si sudo marche sans mot de passe
(Sarasvati, devcontainers), ou si `install.sh` est lancé dans un terminal (sudo
demande alors le mot de passe). Sans terminal ni sudo sans mot de passe, ils
sont sautés avec un message ; `mise bootstrap packages apply` les installe
plus tard. Fichiers et outils s'installent dans tous les cas, mais `node` a
besoin de `libatomic1`, un des paquets de base.

Un vrai fichier là où mise pose un lien (le `~/.bashrc` d'origine, une copie
laissée par chezmoi) est déplacé dans `~/.local/state/dotfiles/backup/<date>/`,
jamais supprimé.

### Migrer un WSL qui utilisait chezmoi et Linuxbrew

1. `git -C ~/.local/share/chezmoi status` : rien de non poussé à garder ?
2. Lancer `install.sh` (ci-dessus). Les fichiers posés par chezmoi partent en sauvegarde.
3. Désinstaller Linuxbrew ([script officiel `uninstall.sh`](https://github.com/Homebrew/install#uninstall-homebrew)),
   puis supprimer `~/.local/share/chezmoi` et `~/.config/chezmoi`.
4. Ouvrir un nouveau shell : `mise dot status` ne doit rien signaler, et
   `gh --version`, `glab --version` et `terraform -version` doivent répondre.

## Au quotidien

| Situation | Quoi faire |
|---|---|
| Modifier `~/.zshrc`, un alias de `~/.zsh-custom/` | c'est un lien : tu modifies le fichier du repo, il reste à commiter |
| Une appli réécrit sa config (`~/.config/gh/config.yml`, `~/.aws/config`) | fichiers en `copy` : `mise dot add --changed` rapatrie les modifs dans `home/` |
| Suivre un nouveau fichier | l'ajouter dans `home/` et une ligne dans `[dotfiles]` de `config/mise/config.toml` |
| Ajouter un outil | une ligne dans `[tools]`, une vérification dans `[tasks.bootstrap]` |
| Voir ce qui diverge | `mise dot status`, `mise bootstrap status` |
| Mettre à jour les outils | `mise upgrade` (les outils sont en `latest`) |

Ce qui ne vaut que pour une machine va dans `config/mise/config.local.toml`
(ignoré par Git), lu par mise en plus de `config.toml`.

## Choix et limites

- **Pas de Python dans `[tools]`** : un `python3` de mise passerait devant
  celui du système, et casserait sur Kali les outils qui comptent sur les
  modules installés par apt. `uv` gère ses propres Pythons, et `pipx` vient d'apt.
- **Pas de `mise.lock`** : les outils en `latest` prennent la dernière version
  à l'installation, comme Homebrew. La CI tourne chaque semaine pour voir passer
  une version cassée avant toi. Épingler un outil (`terraform = "1.9"`) quand la
  version compte.
- **`~/.config/gh/hosts.yml` n'est plus versionné** : gh y écrit le token
  quand aucun trousseau n'est disponible, ce qui est le cas sur WSL et dans les
  conteneurs. `gh auth login` le recrée.
- **`~/.aws/config` est versionné** (choix assumé) : profils SSO et IDs de
  comptes publics, pas de secret. `~/.aws/credentials` reste ignoré.
- **Pas de changement du shell de connexion** : `~/.bashrc` lance zsh dans les
  shells interactifs. Pour changer le shell de connexion : `chsh -s "$(command -v zsh)"`.

## CI

`ci.yml` lance `install.sh` deux fois dans quatre conteneurs : `debian:stable`,
`kalilinux/kali-rolling`, `mcr.microsoft.com/devcontainers/base:debian` (compte
`vscode`) et Debian sans sudo. Le second passage ne doit rien changer. Le
test vérifie aussi les liens, le rendu du template, les droits de
`~/.aws/config`, la sauvegarde du `~/.bashrc` d'origine, l'absence de chemin de
home en dur et, dans zsh, que les outils de mise sont dans le PATH. `secrets.yml`
lance gitleaks sur tout l'historique.

En local (Docker) : `tests/container.sh debian:stable sudo`.
