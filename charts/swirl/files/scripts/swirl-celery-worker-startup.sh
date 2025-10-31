cpu_count=$(nproc)
CELERY_ALL_WORKERS_PROCESSES_CONCURRENCY=$((cpu_count > 1 ? cpu_count - 1 : 1))

python swirl.py start pgbouncer
LOGLEVEL=${CELERY_LOGLEVEL:-info}

if [ "$LOGLEVEL" == "debug" ]; then
  ENABLE_EVENTS="-E"
else
  ENABLE_EVENTS=""
fi

SWIRL_CELERY_AUTOSCALE=${SWIRL_CELERY_AUTOSCALE:-false}
SWIRL_CELERY_AUTOSCALE_MAX=${SWIRL_CELERY_AUTOSCALE_MAX:-10}
SWIRL_CELERY_AUTOSCALE_MIN=${SWIRL_CELERY_AUTOSCALE_MIN:-3}
SWIRL_CELERY_MAX_MEMORY_PER_CHILD=${SWIRL_CELERY_MAX_MEMORY_PER_CHILD:-""}

get_autoscale_config() {
  if [ "$SWIRL_CELERY_AUTOSCALE" == "true" ]; then
    echo "--autoscale=$SWIRL_CELERY_AUTOSCALE_MAX,$SWIRL_CELERY_AUTOSCALE_MIN"
  else
    echo ""
  fi
}

get_max_memory_per_child_config() {
  if [ ! -z "$SWIRL_CELERY_MAX_MEMORY_PER_CHILD" ]; then
    echo "--max-memory-per-child=$SWIRL_CELERY_MAX_MEMORY_PER_CHILD"
  else
    echo ""
  fi
}

get_default_workers_concurrency_config() {
  if [ ! -z "$CELERY_DEFAULT_WORKERS_PROCESSES_CONCURRENCY" ] && [ "$CELERY_DEFAULT_WORKERS_PROCESSES_CONCURRENCY" -ge 1 ]; then
    echo "--concurrency=$CELERY_DEFAULT_WORKERS_PROCESSES_CONCURRENCY"
  else
    echo "--concurrency=$CELERY_ALL_WORKERS_PROCESSES_CONCURRENCY"
  fi
}

celery -A swirl_server worker \
  -Q default,health_check \
  --loglevel=$LOGLEVEL \
  --without-heartbeat \
  --without-gossip \
  --without-mingle $(get_autoscale_config) $(get_max_memory_per_child_config) $(get_default_workers_concurrency_config) $ENABLE_EVENTS
