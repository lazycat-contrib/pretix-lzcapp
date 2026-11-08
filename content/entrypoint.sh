#!/bin/bash
# 懒猫微服适配 wrapper：
# 1. 等 postgres 就绪
# 2. 首启自动创建管理员（凭据来自部署参数，幂等）
# 3. 交给原生 entrypoint 逻辑（pretix all = migrate + supervisord[nginx+gunicorn+periodic]）
set -e
cd /pretix/src
export DJANGO_SETTINGS_MODULE=production_settings
export DATA_DIR=/data/
export HOME=/pretix

echo "waiting for postgres..."
for i in $(seq 1 120); do
  if (echo > /dev/tcp/pretix-db/5432) 2>/dev/null; then
    echo "postgres is up"
    break
  fi
  sleep 1
done

python3 -m pretix migrate --noinput || true

if [ ! -f /data/.admin_created ]; then
  python3 -m pretix createsuperuser --noinput --email "{{ .U.admin_email }}" || true
  if python3 -c "
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'production_settings')
django.setup()
from django.contrib.auth import get_user_model
import sys
sys.exit(0 if get_user_model().objects.filter(is_superuser=True).exists() else 1)
  "; then
    touch /data/.admin_created
    echo "admin user ready"
  else
    echo "admin creation pending, will retry on next start"
  fi
fi

exec pretix all
