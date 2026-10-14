#!/usr/bin/env bash
# 参加者VPSの「玄関」を作る：ホストの Nginx が 80/443 を受け、パスで振り分ける。
#
#   https://<ホスト名>/        → Dify（Docker の nginx コンテナ 127.0.0.1:8080）
#   https://<ホスト名>/site/   → Next.js アプリ（systemd 常駐 127.0.0.1:3000）
#
# 証明書は certbot の nginx プラグインで取得（更新も自動。コンテナの停止は不要）。
# Node.js 24 LTS も入れる。
#
# 使い方（docker グループに入った sudo ユーザーで実行）:
#   bash 02-web-front.sh auto <メール>      ConoHa の自動ホスト名（v1-2-3-4.xxx.static.cnode.jp）
#   bash 02-web-front.sh <ドメイン> <メール> 独自ドメイン
set -euo pipefail

DOMAIN="${1:?auto またはドメインを指定してください}"
EMAIL="${2:?LetsEncrypt 登録用メールアドレスを指定してください}"
NEXT_PATH="/site"
SITE=/etc/nginx/sites-available/workshop.conf

my_ip=$(curl -4 -s https://ifconfig.me)
if [ "$DOMAIN" = "auto" ]; then
  DOMAIN=$(getent hosts "$my_ip" | awk '{print $2}' | sed 's/\.$//')
  [ -n "$DOMAIN" ] || { echo "ConoHa のホスト名を取得できませんでした"; exit 1; }
fi
dns_ip=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')
[ "$my_ip" = "$dns_ip" ] || { echo "DNS 未反映：$DOMAIN -> ${dns_ip:-なし}（このサーバーは $my_ip）"; exit 1; }
echo "ホスト名: $DOMAIN"

# 1. Node.js 24 LTS（NodeSource）
if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 24 ]; then
  sudo install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | sudo gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
    | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
  sudo apt-get -o DPkg::Lock::Timeout=600 update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y -qq nodejs >/dev/null
fi
echo "Node.js $(node -v)"

# 2. Dify が未起動のときに出すページ
sudo install -d -m 755 /var/www/workshop
sudo tee /var/www/workshop/starting.html >/dev/null <<'EOF'
<!doctype html><html lang="ja"><head><meta charset="utf-8"><title>準備中</title></head>
<body style="font-family:sans-serif;max-width:40em;margin:4em auto;padding:0 1em">
<h1>Dify を準備中です</h1><p>起動直後は数分かかります。少し待ってから再読み込みしてください。</p></body></html>
EOF

# 3. Nginx 設定（まず HTTP だけ。certbot が HTTPS 部分を追記する）
sudo tee "$SITE" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    client_max_body_size 100M;

    # Next.js アプリ（next.config の basePath を "$NEXT_PATH" にしておく）
    location $NEXT_PATH {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Dify（Docker の nginx コンテナ）
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;              # チャットの逐次表示（ストリーミング）用
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_intercept_errors on;
        error_page 502 503 504 /starting.html;
    }
    location = /starting.html {
        root /var/www/workshop;
        internal;
    }
}
EOF
sudo ln -sf "$SITE" /etc/nginx/sites-enabled/workshop.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t -q
sudo systemctl enable --now nginx >/dev/null 2>&1
sudo systemctl reload nginx

# 4. 証明書（HTTP→HTTPS のリダイレクトも certbot が設定）
if ! sudo test -d "/etc/letsencrypt/live/$DOMAIN"; then
  sudo certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos -n --redirect
fi
sudo certbot renew --dry-run -q && echo "証明書の自動更新テスト OK"

echo "完了： https://$DOMAIN/ （Dify）  https://$DOMAIN$NEXT_PATH/ （Next.js）"
