# Runner GitHub Actions auto-hébergé (service)

Scripts pour installer le runner officiel (`actions/runner`) comme service démarré au boot :

| Système | Scripts | Service |
|---|---|---|
| Linux   | `install.sh`, `uninstall.sh`, `runnerctl.sh` | systemd (`sudo`), sous l'utilisateur courant |
| macOS   | `install.sh`, `uninstall.sh`, `runnerctl.sh` | LaunchDaemon système (`sudo`), sous l'utilisateur courant |
| Windows | `install.ps1`, `uninstall.ps1`, `runnerctl.ps1` | service Windows (PowerShell administrateur) |

La configuration est commune : `runner.env` (modèle : `runner.env.example`).

Prérequis : `curl`, `jq` (Linux/macOS), et soit le CLI `gh` connecté, soit `GITHUB_PAT`.
Le compte doit être admin du dépôt (ou de l'organisation) pour enregistrer un runner.

## Linux / macOS

```bash
cp runner.env.example runner.env   # puis éditer GITHUB_URL, RUNNER_NAME, RUNNER_LABELS…
./install.sh
./runnerctl.sh status | start | stop | restart | logs
./uninstall.sh                     # arrête le service et désenregistre le runner
```

Sur les trois systèmes, le runner est un service système : il démarre au boot,
sans session utilisateur ouverte.

Sous macOS, le service est un LaunchDaemon (`/Library/LaunchDaemons/actions.runner.*.plist`)
écrit par `install.sh` (le `svc.sh` de GitHub ne crée qu'un LaunchAgent, actif seulement
pendant une session). Il tourne sous l'utilisateur courant, sans accès à son trousseau
(Keychain) : les jobs ne peuvent pas utiliser de certificats ou mots de passe qui y sont rangés.
Journaux : `/Library/Logs/actions.runner.*/`.

## Windows

Dans un PowerShell **administrateur** :

```powershell
copy runner.env.example runner.env    # puis éditer
powershell -ExecutionPolicy Bypass -File .\install.ps1
.\runnerctl.ps1 status                # start | stop | restart | status | logs
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

- Répertoire par défaut : `C:\actions-runner\<nom>` (modifiable via `RUNNER_DIR_WIN`) ;
  un chemin court évite les problèmes de longueur de chemin (260 caractères).
- Le service tourne sous `NT AUTHORITY\NETWORK SERVICE` : les outils utilisés par les jobs
  (git, compilateurs, R, Python…) doivent être installés pour tous les utilisateurs.

## Utilisation dans un workflow

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, libkriging]   # ou macOS / windows
```

## Notes

- Le runner Linux/macOS est installé dans `RUNNER_DIR` (par défaut `~/actions-runner/<nom>`), hors du dossier Sync.
- Plusieurs runners : un fichier env par runner, `ENV_FILE=autre.env ./install.sh`
  (Windows : `$env:ENV_FILE='autre.env'`).
- Sécurité : sur un dépôt **public**, exiger une approbation des workflows lancés depuis des forks,
  sinon n'importe quelle PR peut exécuter du code sur la machine.
