# dotfiles

Mon environnement de travail, le même partout : WSL, mes devcontainers, la VM
Sarasvati (Kali). Un seul outil, [mise](https://mise.jdx.dev), installe les
paquets système de base, les outils (gh, glab, terraform, kubectl…) et dépose
les fichiers de config. Un seul point d'entrée : `install.sh`.

```
install.sh              point d'entrée unique, idempotent
config/mise/config.toml LA config : paquets, Oh My Zsh, fichiers, outils, vérifications
home/                   sources des fichiers déployés (zshrc, zsh/, gitconfig.tmpl, gh)
examples/identity/      modèle d'un repo d'identité (voir « Identité »)
tests/container.sh      install.sh deux fois dans un conteneur (utilisé par la CI)
```

`install.sh` installe mise (version épinglée, somme de contrôle vérifiée) dans
`~/.local/bin`. Il crée ensuite deux liens, `~/.dotfiles` vers le repo et
`~/.config/mise` vers `config/mise`, puis lance `mise bootstrap`. Cette config
devient la config **globale** de mise : les outils sont actifs dans tous les
dossiers, pas seulement dans le repo. Log : `~/.local/state/dotfiles/install.log`.

## Identité

Ce repo est public et ne dit pas qui tu es. Nom et mail Git, profils AWS,
réglages propres à un employeur viennent d'un **repo d'identité**, privé, choisi
par machine :

| Identité | Repo | Machines |
|---|---|---|
| perso | `github.com/Deltamir/dotfiles-perso` | WSL perso, Sarasvati perso |
| pro | un repo sur le GitLab de l'entreprise | WSL pro, Sarasvati en mission |

```bash
~/dotfiles/install.sh --identity <url>    # pose cette identité (remplace l'actuelle)
~/dotfiles/install.sh --identity none     # plus d'identité
```

`install.sh` clone le repo dans `~/.local/share/dotfiles-identity`, le relie en
`~/.dotfiles-identity` et relie son `mise.toml` dans `config/mise/conf.d/`, où
mise le fusionne avec `config.toml`. Ses fichiers forment le groupe de dotfiles
`identity` : changer d'identité retire d'abord tous les fichiers de la
précédente (`mise dot unapply --group identity`), puis supprime son clone. Rien
de l'identité perso ne reste sur une machine passée en pro. Le changement est
refusé tant que l'identité actuelle a des modifications non publiées (une copie
réécrite par `aws configure sso`, un commit non poussé) : `mise run push` d'abord.

Créer une identité : copier `examples/identity/` dans un nouveau repo privé, y
mettre ses fichiers sous `home/` (`dot-` pour un point initial). Un repo privé
demande que `git clone` y ait accès : `gh auth login` pour GitHub, `glab auth
login --hostname <gitlab de l'entreprise>` ou une URL SSH avec une clé pour un
GitLab d'entreprise. La synchronisation à l'ouverture de session ne demande
jamais de mot de passe : sans accès, elle garde la version locale.

`config.toml` ne doit définir aucune `[vars]` qu'une identité fixe : le fichier
de base l'emporte sur `conf.d/`.

## Installer

| Machine | Comment |
|---|---|
| WSL | `git clone https://github.com/Deltamir/dotfiles ~/dotfiles && ~/dotfiles/install.sh --identity <url>` |
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

Rien ne part jamais tout seul : une modification faite sur une machine reste
dans sa copie du repo jusqu'à `mise run push`.

| Situation | Quoi faire |
|---|---|
| Modifier `~/.zshrc`, un alias de `~/.zsh-custom/` | c'est un lien : tu modifies le fichier du repo ; `mise run push` pour le publier |
| Une appli réécrit sa config (`~/.config/gh/config.yml`, `~/.aws/config` de l'identité) | fichiers en `copy` : rapatriés dans leur repo (celui-ci ou celui de l'identité) par `mise run push` (ou `mise dot add --changed`) et à chaque synchronisation |
| Publier les changements de cette machine | `mise run push` : pour ce repo puis celui de l'identité, diff complet, scan gitleaks (le moindre résultat arrête tout), confirmation, commit au nom de la machine (auteur : l'identité), `pull --rebase`, push |
| Récupérer les changements faits ailleurs | automatique à l'ouverture de session (les deux repos) si rien n'est modifié localement ; sinon `mise run push` d'abord |
| Suivre un nouveau fichier | l'ajouter dans `home/` et une ligne dans `[dotfiles]` de `config/mise/config.toml` |
| Ajouter un outil | une ligne dans `[tools]`, une vérification dans `[tasks.bootstrap]` |
| Voir ce qui diverge | `mise dot status`, `mise bootstrap status` |
| Mettre à jour les outils | `mise upgrade` (les outils sont en `latest`) |

Ce qui ne vaut que pour une machine va dans `config/mise/config.local.toml`
(ignoré par Git), lu par mise en plus de `config.toml`.

## En arrière-plan (systemd utilisateur)

Déclarées dans `config.toml` (`[bootstrap.linux.systemd.units]`) et posées par
`install.sh` :

| Unité | Quand | Quoi |
|---|---|---|
| `dev.mise.dotfiles-sync.service` | ouverture de session | `install.sh --sync` : `git pull --ff-only` de ce repo et du repo d'identité, chacun seulement si sa copie locale n'a aucune modification, puis applique la config. Délai de 20 s sur le réseau ; une erreur est journalisée et la session continue avec la version locale |
| `dev.mise.mise-upgrade-weekly.timer` | chaque semaine (rattrapé au démarrage si la machine était éteinte) | `mise upgrade` des outils de `[tools]` |

Journal : `~/.local/state/dotfiles/install.log`, et
`journalctl --user -u dev.mise.dotfiles-sync`. Sans gestionnaire systemd
utilisateur (conteneurs, WSL sans systemd), ces unités sont sautées : sur WSL,
mettre `[boot]` puis `systemd=true` dans `/etc/wsl.conf` et redémarrer WSL
(`wsl --shutdown`). Dans un devcontainer, VS Code relance `install.sh` à chaque
création, ce qui suffit.

### Pousser depuis une VM d'audit

Ne jamais y mettre ton token GitHub complet. Une clé de déploiement par VM,
limitée à ce repo :

```bash
ssh-keygen -t ed25519 -f ~/.ssh/dotfiles_deploy -N "" -C "dotfiles $(hostname)"
# GitHub > Deltamir/dotfiles > Settings > Deploy keys > Add, "Allow write access"
git -C ~/.dotfiles remote set-url origin git@github.com:Deltamir/dotfiles.git
git -C ~/.dotfiles config core.sshCommand "ssh -i ~/.ssh/dotfiles_deploy -o IdentitiesOnly=yes"
```

Supprimer la clé (sur GitHub et sur la VM) en fin de mission. Sans clé :
`git -C ~/.dotfiles format-patch origin/main` puis appliquer le patch depuis
ton poste.

## Outils communs

Paquets apt (avec sudo) : git, curl, wget, gnupg, lsb-release, bind9-dnsutils
(dig), expect, xz-utils, unzip, jq, nano, screen, tmux, pipx, python3-pip,
python-is-python3, zsh et ses plugins, et `google-cloud-cli` depuis le dépôt
apt de Google (absent de Debian et de Kali ; suite fixe `cloud-sdk`).

Outils mise (avec ou sans sudo) : gh, glab, terraform, vault, kubectl, yq,
aws-cli, **azure-cli** (depuis PyPI : le dépôt apt de Microsoft n'a pas de suite
Debian 13), docker-cli (le client seul ; le moteur Docker n'est installé que sur
la VM Sarasvati), uv, node, yarn, gitleaks et **Claude Code** (`claude`, binaire
publié par Anthropic, mis à jour par le `mise upgrade` hebdomadaire).

## Mises à jour automatiques du système

`unattended-upgrades` tourne chaque jour partout où apt a ses minuteurs systemd
(pas dans les devcontainers, ni sur WSL sans `systemd=true`). Sur Debian et
Ubuntu : les mises à jour de sécurité (réglages du paquet). Sur Kali, qui n'a
pas de dépôt de sécurité séparé : **toutes** les mises à jour de kali-rolling
(`/etc/apt/apt.conf.d/52dotfiles-unattended-upgrades`, origine `Kali`).
Contrepartie assumée : un outil peut changer de version d'un jour à l'autre.

Sans sudo, les fichiers système (`[bootstrap.files]`) sont sautés comme les
paquets.

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
- **`~/.aws/config` est dans le repo d'identité**, privé : profils SSO et IDs
  de comptes. Il a été public ici jusqu'à l'arrivée des identités et reste dans
  l'historique Git de ce repo. `~/.aws/credentials` reste ignoré partout.
- **Pas de changement du shell de connexion** : `~/.bashrc` lance zsh dans les
  shells interactifs. Pour changer le shell de connexion : `chsh -s "$(command -v zsh)"`.

## CI

`ci.yml` lance `install.sh` deux fois dans quatre conteneurs : `debian:stable`,
`kalilinux/kali-rolling`, `mcr.microsoft.com/devcontainers/base:debian` (compte
`vscode`) et Debian sans sudo. Le second passage ne doit rien changer. Le
test vérifie aussi les liens, le rendu du template, l'identité (fichiers,
droits de `~/.aws/config`, auteur Git ; changement refusé tant qu'une réécriture
n'est pas publiée, publication dans le repo d'identité, passage de perso à pro
sans aucun reste, `--identity none`), la sauvegarde du `~/.bashrc` d'origine, l'absence de chemin de
home en dur et, dans zsh, que les outils de mise sont dans le PATH, le prompt et
les comportements de Kali. Sur Debian, Kali et le devcontainer, il joue aussi la
synchronisation et la publication contre un dépôt local qui tient lieu de
GitHub : un changement fait ailleurs arrive, une modification locale survit,
une copie réécrite par une appli est conservée, un faux token GitHub bloque
`mise run push`, une publication passe après rebase, et un dépôt injoignable
laisse `--sync` sortir en 0. Les unités systemd ne sont pas testées en CI (pas
de systemd dans ces conteneurs). `secrets.yml` lance gitleaks sur tout
l'historique.

En local (Docker) : `tests/container.sh debian:stable sudo`.
