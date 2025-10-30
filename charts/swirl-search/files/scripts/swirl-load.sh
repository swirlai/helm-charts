# Fail on 1st error
set -e

echo "Setting up swirl";
python manage.py collectstatic --noinput
es_version=${SWIRL_ES_VERSION:-8}
if [ "$es_version" -eq 7 ]; then
  echo "Installing ES version 7"
  echo "Install elasticsearch downgrade to 7.17.12"
  pip install elasticsearch==7.17.12
fi
echo "msal and oauth config loading";
mkdir -p /app/static/api/config;
python swirl.py config_default_api_settings

echo "msal and oauth config loading completed";
echo '*** Holding for 30s';
sleep 30;


if [ "$USE_SEPARATE_CELERY_WORKER" == "true" ]; then
    echo "Separate Celery Worker Pods";
    COMPONENTS=celery-beats
else
    COMPONENTS="celery-worker celery-beats celery-healthcheck-worker"
fi
python swirl.py start $COMPONENTS
daphne -b 0.0.0.0 -p 8000 swirl_server.asgi:application