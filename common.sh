# Fonctions partagées (Linux / macOS) — à sourcer, pas à exécuter.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/runner.env}"

die() { echo "ERREUR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[ -f "$ENV_FILE" ] || die "$ENV_FILE introuvable (cp runner.env.example runner.env)"
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${GITHUB_URL:?GITHUB_URL manquant}"
: "${RUNNER_NAME:?RUNNER_NAME manquant}"
: "${RUNNER_DIR:?RUNNER_DIR manquant}"
RUNNER_LABELS="${RUNNER_LABELS:-}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
RUNNER_VERSION="${RUNNER_VERSION:-latest}"

# Linux : service systemd (via svc.sh). macOS : LaunchDaemon système (géré ici, car
# svc.sh n'installe qu'un LaunchAgent, actif seulement avec une session ouverte).
case "$(uname -s)" in
  Linux)  RUNNER_OS=linux ;;
  Darwin) RUNNER_OS=osx ;;
  *) die "système non supporté: $(uname -s) (Windows : utiliser install.ps1)" ;;
esac

command -v jq >/dev/null || die "jq requis (apt install jq / brew install jq)"

# Chemin d'API : repos/OWNER/REPO ou orgs/ORG
api_scope() {
  local path="${GITHUB_URL#https://github.com/}"
  path="${path%/}"
  if [[ "$path" == */* ]]; then echo "repos/$path"; else echo "orgs/$path"; fi
}

# Appel POST à l'API GitHub (gh CLI ou PAT)
gh_post() {
  local endpoint="$1"
  if [ -n "${GITHUB_PAT:-}" ]; then
    curl -fsSL -X POST \
      -H "Authorization: Bearer $GITHUB_PAT" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/$endpoint"
  elif command -v gh >/dev/null; then
    gh api -X POST "$endpoint"
  else
    die "ni GITHUB_PAT ni gh CLI disponibles"
  fi
}

registration_token() { gh_post "$(api_scope)/actions/runners/registration-token" | jq -r .token; }
remove_token()       { gh_post "$(api_scope)/actions/runners/remove-token"       | jq -r .token; }

runner_arch() {
  case "$(uname -m)" in
    x86_64)  echo x64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l)  echo arm ;;
    *) die "architecture non supportée: $(uname -m)" ;;
  esac
}

# Nom du service enregistré dans .service
# (Linux : nom de l'unité systemd ; macOS : chemin du .plist)
service_name() {
  [ -f "$RUNNER_DIR/.service" ] || die "service non installé (./install.sh)"
  basename "$(cat "$RUNNER_DIR/.service")" .plist
}

# --- macOS : LaunchDaemon -----------------------------------------------------

# Même convention de nom que svc.sh : actions.runner.<owner>-<repo>.<name>
mac_label() {
  local path="${GITHUB_URL#https://github.com/}"
  path="${path%/}"
  echo "actions.runner.${path//\//-}.${RUNNER_NAME}"
}
mac_plist()  { echo "/Library/LaunchDaemons/$(mac_label).plist"; }
mac_logdir() { echo "/Library/Logs/$(mac_label)"; }

mac_service_install() {
  local label plist logdir user
  label="$(mac_label)"; plist="$(mac_plist)"; logdir="$(mac_logdir)"; user="$(id -un)"
  cp ./bin/runsvc.sh ./runsvc.sh
  chmod u+x ./runsvc.sh
  sudo mkdir -p "$logdir"
  sudo chown "$user" "$logdir"
  sudo tee "$plist" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>$label</string>
  <key>UserName</key>          <string>$user</string>
  <key>ProgramArguments</key>  <array><string>$RUNNER_DIR/runsvc.sh</string></array>
  <key>WorkingDirectory</key>  <string>$RUNNER_DIR</string>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
  <key>StandardOutPath</key>   <string>$logdir/stdout.log</string>
  <key>StandardErrorPath</key> <string>$logdir/stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>                <string>$HOME</string>
    <key>ACTIONS_RUNNER_SVC</key>  <string>1</string>
  </dict>
  <key>ProcessType</key>       <string>Interactive</string>
  <key>SessionCreate</key>     <true/>
</dict>
</plist>
PLIST
  sudo chown root:wheel "$plist"
  sudo chmod 644 "$plist"
  echo "$plist" > .service
}

mac_service_start()  { sudo launchctl bootstrap system "$(mac_plist)" 2>/dev/null || sudo launchctl kickstart "system/$(mac_label)"; }
mac_service_stop()   { sudo launchctl bootout "system/$(mac_label)" 2>/dev/null || true; }
mac_service_status() { sudo launchctl print "system/$(mac_label)" | grep -E '^\s*(state|pid|last exit code) ' || echo "non chargé"; }
mac_service_uninstall() {
  mac_service_stop
  sudo rm -f "$(mac_plist)"
  rm -f .service ./runsvc.sh
}
