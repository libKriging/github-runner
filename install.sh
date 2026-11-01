#!/usr/bin/env bash
# Télécharge, enregistre et installe le runner GitHub Actions comme service
# (systemd sous Linux, launchd sous macOS).
source "$(dirname "$0")/common.sh"

if [ -f "$RUNNER_DIR/.runner" ]; then
  die "runner déjà configuré dans $RUNNER_DIR (./uninstall.sh d'abord)"
fi

ARCH="$(runner_arch)"
if [ "$RUNNER_VERSION" = latest ]; then
  RUNNER_VERSION="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name)"
  RUNNER_VERSION="${RUNNER_VERSION#v}"
fi
TARBALL="actions-runner-${RUNNER_OS}-${ARCH}-${RUNNER_VERSION}.tar.gz"
URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${TARBALL}"

log "Installation du runner v$RUNNER_VERSION ($RUNNER_OS-$ARCH) dans $RUNNER_DIR"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
if [ ! -x ./config.sh ]; then
  curl -fsSL -o "$TARBALL" "$URL"
  tar xzf "$TARBALL"
  rm -f "$TARBALL"
fi

# installdependencies.sh échoue sur les distributions récentes (paquets renommés,
# ex. Ubuntu 24.04) : on ne l'appelle que si le runner ne démarre pas.
if [ "$RUNNER_OS" = linux ] && ! ./config.sh --version >/dev/null 2>&1; then
  log "Installation des dépendances système (sudo)"
  sudo ./bin/installdependencies.sh \
    || echo "ATTENTION: installdependencies.sh a échoué ; installer à la main libicu, libssl, libkrb5, zlib" >&2
  ./config.sh --version >/dev/null 2>&1 || die "le runner ne démarre pas : dépendances .NET manquantes"
fi

log "Enregistrement auprès de $GITHUB_URL"
TOKEN="$(registration_token)"
[ -n "$TOKEN" ] && [ "$TOKEN" != null ] || die "impossible d'obtenir un jeton d'enregistrement"

ARGS=(--unattended --replace
      --url "$GITHUB_URL" --token "$TOKEN"
      --name "$RUNNER_NAME" --work _work)
[ -n "$RUNNER_LABELS" ] && ARGS+=(--labels "$RUNNER_LABELS")
[[ "$(api_scope)" == orgs/* ]] && ARGS+=(--runnergroup "$RUNNER_GROUP")
./config.sh "${ARGS[@]}"

log "Création et démarrage du service"
if [ "$RUNNER_OS" = linux ]; then
  sudo ./svc.sh install "$(id -un)"
  sudo ./svc.sh start
  sudo ./svc.sh status || true
else
  mac_service_install
  mac_service_start
  mac_service_status
fi

log "OK. Dans les workflows : runs-on: [self-hosted${RUNNER_LABELS:+, $RUNNER_LABELS}]"
