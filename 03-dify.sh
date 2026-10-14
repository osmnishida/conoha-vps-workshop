#!/usr/bin/env bash
# Dify をホストの Nginx の後ろに置いて起動する（02-web-front.sh の実行後に使う）。
#   - Dify は ~/dify に git clone し、docker/ で Docker Compose 起動（既存の Dify サーバーと同じ）
#   - Dify の nginx コンテナは 127.0.0.1:8080 だけで待ち受ける（外からはホストの Nginx 経由）
#   - HTTPS と証明書はホストの Nginx + certbot が担当（Dify 側では SSL を無効）
#   - .env の秘密値（SECRET_KEY 等）は初期値のままにせずランダム生成する
#
# 使い方（docker グループに入った sudo ユーザーで実行）:
#   bash 03-dify.sh
set -euo pipefail

DIFY_VERSION="1.13.3"
DIFY_DIR="$HOME/dify/docker"
SITE=/etc/nginx/sites-available/workshop.conf

mem_mb=$(free -m | awk '/^Mem:/{print $2}')
[ "$mem_mb" -ge 3500 ] || { echo "メモリ ${mem_mb}MB：Dify には 4GB 以上が必要です"; exit 1; }
DOMAIN=$(awk '/server_name/{gsub(";","",$2); print $2; exit}' "$SITE" 2>/dev/null)
[ -n "$DOMAIN" ] || { echo "先に 02-web-front.sh を実行してください"; exit 1; }
BASE_URL="https://$DOMAIN"

[ -d "$HOME/dify" ] || git clone --branch "$DIFY_VERSION" --depth 1 https://github.com/langgenius/dify.git "$HOME/dify"
cd "$DIFY_DIR"

if [ ! -f .env ]; then
  cp .env.example .env
  set_env() { sed -i "s|^$1=.*|$1=$2|" .env; }
  rnd() { openssl rand -hex "${1:-24}"; }

  for k in CONSOLE_API_URL CONSOLE_WEB_URL SERVICE_API_URL APP_API_URL APP_WEB_URL FILES_URL; do
    set_env "$k" "$BASE_URL"
  done
  # ホストの Nginx からだけ届くようにする
  set_env NGINX_HTTPS_ENABLED false
  set_env EXPOSE_NGINX_PORT 127.0.0.1:8080
  set_env EXPOSE_NGINX_SSL_PORT 127.0.0.1:8443

  # 秘密値（対になる変数は同じ値にする）
  set_env SECRET_KEY "sk-$(rnd 32)"
  set_env DB_PASSWORD "$(rnd)"
  redis_pw=$(rnd)
  set_env REDIS_PASSWORD "$redis_pw"
  set_env CELERY_BROKER_URL "redis://:${redis_pw}@redis:6379/1"
  sandbox_key=$(rnd)
  set_env SANDBOX_API_KEY "$sandbox_key"
  set_env CODE_EXECUTION_API_KEY "$sandbox_key"
  weaviate_key=$(rnd)
  set_env WEAVIATE_API_KEY "$weaviate_key"
  set_env WEAVIATE_AUTHENTICATION_APIKEY_ALLOWED_KEYS "$weaviate_key"
  set_env PLUGIN_DAEMON_KEY "$(rnd 32)"
  set_env PLUGIN_DIFY_INNER_API_KEY "$(rnd 32)"
  chmod 600 .env
fi

docker compose up -d
echo "起動しました。数分後に $BASE_URL/install を開いて管理者アカウントを作成してください。"
echo "Next.js から Dify API を呼ぶときは、サーバー内の http://127.0.0.1:8080/v1 を使えます。"
