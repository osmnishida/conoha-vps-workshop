#!/usr/bin/env bash
# Next.js アプリを VPS に配置し、systemd で常駐させる（127.0.0.1:3000、/site で公開）。
#
# 使い方:
#   bash 04-nextjs-app.sh                 サンプルアプリを作って公開（動作確認用）
#   bash 04-nextjs-app.sh <git リポジトリURL> 自分のアプリを公開
#
# 自分のアプリは next.config に basePath: "/site" を入れておくこと。
# Dify の API キー等は /srv/apps/site/.env.local に書く（ブラウザに出さずサーバー側で使う）。
set -euo pipefail

REPO="${1:-}"
APP_DIR=/srv/apps/site
NEXT_PATH="/site"
SERVICE=nextapp

sudo install -d -o "$(id -un)" -g "$(id -gn)" -m 755 /srv/apps

if [ -z "$REPO" ]; then
  if [ ! -d "$APP_DIR" ]; then
    npx --yes create-next-app@latest "$APP_DIR" --ts --app --use-npm --yes --disable-git
    cat > "$APP_DIR/app/page.tsx" <<'EOF'
export default function Home() {
  return (
    <main style={{ fontFamily: "sans-serif", maxWidth: 640, margin: "4rem auto", padding: "0 1rem" }}>
      <h1>Next.js on ConoHa VPS</h1>
      <p>このページは VPS 上の Next.js（systemd 常駐）から配信されています。</p>
      <p><a href="/site/chat">Dify チャット（API 連携のサンプル）</a></p>
      <p><a href="/">Dify を開く</a></p>
    </main>
  );
}
EOF
    # Dify API 連携のサンプル（スクリプトと同じフォルダの sample-site/ からコピー）
    SRC="$(cd "$(dirname "$0")" && pwd)/sample-site"
    [ -d "$SRC" ] && cp -r "$SRC/." "$APP_DIR/"
    printf 'DIFY_API_URL=http://127.0.0.1:8080/v1\nDIFY_API_KEY=\n' > "$APP_DIR/.env.local"
    chmod 600 "$APP_DIR/.env.local"
  fi
else
  if [ -d "$APP_DIR/.git" ]; then git -C "$APP_DIR" pull --ff-only; else git clone "$REPO" "$APP_DIR"; fi
fi

cd "$APP_DIR"
# basePath が未設定のサンプルには入れる（自分のアプリは自分で設定する）
for f in next.config.ts next.config.mjs next.config.js; do
  if [ -f "$f" ] && ! grep -q basePath "$f"; then
    if [ -z "$REPO" ]; then
      sed -i "s|const nextConfig: NextConfig = {|const nextConfig: NextConfig = {\n  basePath: \"$NEXT_PATH\",|" "$f"
    else
      echo "注意：$f に basePath: \"$NEXT_PATH\" がありません。/site で表示が崩れます"
    fi
  fi
done

npm ci --no-audit --no-fund || npm install --no-audit --no-fund
NODE_OPTIONS=--max-old-space-size=1536 npm run build

sudo tee /etc/systemd/system/$SERVICE.service >/dev/null <<EOF
[Unit]
Description=Next.js アプリ（$NEXT_PATH）
After=network.target

[Service]
User=$(id -un)
WorkingDirectory=$APP_DIR
Environment=NODE_ENV=production
ExecStart=$(command -v npx) next start -H 127.0.0.1 -p 3000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE >/dev/null 2>&1
sudo systemctl restart $SERVICE
sleep 3
curl -s -o /dev/null -w "Next.js 応答: HTTP %{http_code}\n" "http://127.0.0.1:3000$NEXT_PATH"
