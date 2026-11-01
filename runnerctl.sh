#!/usr/bin/env bash
# Pilotage du service : start | stop | restart | status | logs
source "$(dirname "$0")/common.sh"

SERVICE="$(service_name)"
cd "$RUNNER_DIR"

if [ "$RUNNER_OS" = linux ]; then
  case "${1:-status}" in
    start|stop|status) sudo ./svc.sh "$1" ;;
    restart)           sudo systemctl restart "$SERVICE" ;;
    logs)              journalctl -u "$SERVICE" -f ;;
    *) echo "usage: $0 {start|stop|restart|status|logs}" >&2; exit 2 ;;
  esac
else
  case "${1:-status}" in
    start)   mac_service_start ;;
    stop)    mac_service_stop ;;
    restart) mac_service_stop; mac_service_start ;;
    status)  mac_service_status ;;
    logs)    tail -f "$(mac_logdir)"/*.log ;;
    *) echo "usage: $0 {start|stop|restart|status|logs}" >&2; exit 2 ;;
  esac
fi
