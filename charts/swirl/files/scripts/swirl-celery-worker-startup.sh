#!/usr/bin/env bash set -euo pipefail
raw="${CELERY_QUEUES:-}"
raw="${raw//,/ }"
workers=()
for q in $raw; do
  case "$q" in
    search)       workers+=("celery-search-worker") ;;
    page_fetch)   workers+=("celery-pagefetch-worker") ;;
    interactive)  workers+=("celery-interactive-worker") ;;
    maintenance)  workers+=("celery-maintenance-worker") ;;
    "" )          ;;
    * )
      echo "ERROR: unknown CELERY_QUEUES value '$q'"
      exit 1
      ;;
  esac
done
if [ "${#workers[@]}" -eq 0 ]; then
  echo "ERROR: CELERY_QUEUES is empty or contained no valid values."
  echo "Valid values: search, page_fetch, interactive, maintenance"
  exit 1
fi

workers+=("celery-healthcheck-worker")

start_args=()

if [[ "${SWIRL_PGBOUNCER,,}" == "true" && "${PGBOUNCER_PRODUCTION,,}" == "true" ]]; then
  echo "pgbouncer enabled (SWIRL_PGBOUNCER=true, PGBOUNCER_PRODUCTION=true)"
  start_args+=("pgbouncer")
else
  echo "pgbouncer disabled"
fi

echo "Starting workers for CELERY_QUEUES='${CELERY_QUEUES}': ${workers[*]}"
python swirl.py start "${start_args[@]}" "${workers[@]}"

_term() {
  echo "Received termination signal; exiting."
  exit 0
}

trap _term INT TERM

while true; do
  sleep 3600 &
  wait $!
done
