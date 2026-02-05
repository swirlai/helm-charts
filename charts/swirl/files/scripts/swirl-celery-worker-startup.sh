#!/usr/bin/env bash
set -eo pipefail

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

# Prepare log files we expect and stream them to stdout for pod logs.
mkdir -p logs
log_files=()
for w in "${workers[@]}"; do
  touch "logs/${w}.log"
  log_files+=("logs/${w}.log")
done

echo "Streaming worker logs to stdout (so they appear in pod logs)..."
tail -n0 -F "${log_files[@]}" &
TAIL_PID=$!

_term() {
  echo "Received termination signal; stopping log tail."
  kill "${TAIL_PID}" 2>/dev/null || true
  exit 0
}
trap _term INT TERM

echo "Starting workers for CELERY_QUEUES='${CELERY_QUEUES}': ${workers[*]}"
python swirl.py start "${start_args[@]}" "${workers[@]}"

wait "${TAIL_PID}"
