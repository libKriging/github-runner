#!/usr/bin/env bash
# Arrête et supprime le service, puis désenregistre le runner de GitHub.
source "$(dirname "$0")/common.sh"

[ -d "$RUNNER_DIR" ] || die "$RUNNER_DIR introuvable"
cd "$RUNNER_DIR"

if [ -f .service ]; then
  log "Arrêt et suppression du service"
  if [ "$RUNNER_OS" = linux ]; then
    sudo ./svc.sh stop || true
    sudo ./svc.sh uninstall
  else
    mac_service_uninstall
  fi
fi

if [ -f .runner ]; then
  log "Désenregistrement auprès de $GITHUB_URL"
  ./config.sh remove --token "$(remove_token)"
fi

log "Runner retiré. Supprimer les fichiers : rm -rf '$RUNNER_DIR'"
