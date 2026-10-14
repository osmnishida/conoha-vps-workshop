#!/usr/bin/env bash
# 独自ドメインを追加する（02〜04 の実行後に使う。ドメインがない人は不要）
#   - Nginx に独自ドメインを追加し、証明書を「自動ホスト名＋独自ドメイン」の両方入りに更新
#   - Dify の URL 設定を独自ドメインに切り替えて再起動
#   - 自動ホスト名の URL もそのまま使える
#
# 前提：ドメインの DNS に A レコード（このVPSの IPv4 アドレス）を登録済み。
#       Cloudflare の場合はプロキシをオフ（DNS only・灰色の雲）にする。
#
# 使い方（docker グループに入った sudo ユーザーで実行）:
#   bash 05-add-domain.sh <独自ドメイン> <メール>
set -euo pipefail

DOMAIN="${1:?独自ドメインを指定してください（例: ai.example.com）}"
EMAIL="${2:?LetsEncrypt 登録用メールアドレスを指定してください}"
SITE=/etc/nginx/sites-available/workshop.conf
DIFY_DIR="$HOME/dify/docker"

[ -f "$SITE" ] || { echo "先に 02-web-front.sh を実行してください"; exit 1; }
AUTO=$(awk '/server_name/{gsub(";","",$2); print $2; exit}' "$SITE")

# 1. DNS の確認
my_ip=$(curl -4 -s https://ifconfig.me)
dns_ip=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')
if [ "$my_ip" != "$dns_ip" ]; then
  echo "DNS が未反映です：$DOMAIN -> ${dns_ip:-なし}（このVPSは $my_ip）"
  echo "  ・A レコードの値が $my_ip になっているか"
  echo "  ・Cloudflare ならプロキシがオフ（DNS only）になっているか"
  echo "  ・登録直後は反映まで数分〜数十分かかることがあります"
  exit 1
fi
echo "DNS OK：$DOMAIN -> $my_ip"

# 2. Nginx に独自ドメインを追加
if ! grep -q "server_name .*\b$DOMAIN\b" "$SITE"; then
  sudo sed -i "s/server_name $AUTO;/server_name $AUTO $DOMAIN;/" "$SITE"
fi
sudo nginx -t -q
sudo systemctl reload nginx

# 3. 証明書を2つの名前入りに更新（更新も自動）
sudo certbot --nginx --cert-name "$AUTO" -d "$AUTO" -d "$DOMAIN" --expand \
  -m "$EMAIL" --agree-tos -n --redirect
sudo certbot renew --dry-run -q && echo "証明書の自動更新テスト OK"

# 4. Dify の URL を独自ドメインに切り替え
if [ -f "$DIFY_DIR/.env" ]; then
  cd "$DIFY_DIR"
  for k in CONSOLE_API_URL CONSOLE_WEB_URL SERVICE_API_URL APP_API_URL APP_WEB_URL FILES_URL; do
    sed -i "s|^$k=.*|$k=https://$DOMAIN|" .env
  done
  docker compose up -d
fi

echo "完了： https://$DOMAIN/ （Dify）  https://$DOMAIN/site （Next.js）"
echo "（https://$AUTO/ も引き続き使えます）"
