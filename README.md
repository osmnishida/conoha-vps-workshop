# ConoHa VPS ワークショップ：Dify と Next.js を自分のVPSで公開する

ConoHa VPS（Ubuntu 24.04・メモリ4GB）に、次の2つを HTTPS で公開するためのスクリプトです。

| URL | 中身 |
|---|---|
| `https://<ホスト名>/` | Dify（AI チャットやワークフローを作るツール） |
| `https://<ホスト名>/site` | あなたの Next.js アプリ（Dify の API を呼べる） |

`<ホスト名>` は、まず ConoHa が VPS ごとに自動で付ける名前（例：`v203-0-113-10.xxxx.static.cnode.jp`）を使い、最後に独自ドメイン（例：`ai.example.com`）を追加します。独自ドメインがなくても最後まで進められます。

## 構成

```
ブラウザ ──https──▶ ConoHa セキュリティグループ（SSH / Web / ICMP のみ）
                     │
                     ▼  :443（:80 は https へ転送）
              ホストの Nginx ＋ certbot（Let's Encrypt 証明書・自動更新）
               ├─ /        ──▶ 127.0.0.1:8080  Dify（Docker Compose）
               └─ /site    ──▶ 127.0.0.1:3000  Next.js（systemd 常駐・Node.js 24）
                                    └─ サーバー内から Dify API（http://127.0.0.1:8080/v1）を呼ぶ
```

- Dify も Next.js もサーバーの中（127.0.0.1）だけで待ち受け、外からは Nginx 経由でしか届きません。
- Dify の API キーは Next.js の `.env.local` に置き、サーバー側から呼びます。ブラウザには出しません。
- Dify は画面の URL に `/app/...` を使うため、Next.js は `/site` に置きます（`basePath: "/site"` が必要）。

## スクリプト

| 順番 | スクリプト | 実行ユーザー | 内容 |
|---|---|---|---|
| 1 | `01-base.sh <ユーザー名>` | root | 日本時間・作業用ユーザー・パッケージ更新・Docker・swap・fail2ban・SSH 強化・ufw |
| 2 | `02-web-front.sh auto <メール>` | 作業用ユーザー | Nginx・Let's Encrypt 証明書・Node.js 24 |
| 3 | `03-dify.sh` | 作業用ユーザー | Dify 1.13.3（秘密値はランダム生成） |
| 4 | `04-nextjs-app.sh [GitHub の URL]` | 作業用ユーザー | Next.js をビルドして常駐（URL 省略時はサンプル） |
| 5 | `05-add-domain.sh <独自ドメイン> <メール>` | 作業用ユーザー | 独自ドメインを追加（任意） |

## 手順

### 0. 事前準備（手元のPC）

- ConoHa アカウントと支払い方法の登録
- SSH 鍵：`ssh-keygen -t ed25519 -f ~/.ssh/conoha_ws_ed25519 -C "conoha-workshop"`
- Next.js アプリの `next.config` に `basePath: "/site"`、GitHub に push（`.env*` は上げない）
- AI モデル（OpenAI など）の API キー
- （任意）独自ドメイン

### 1. VPS を作る（ConoHa コントロールパネル →「サーバー追加」）

| 項目 | 設定 |
|---|---|
| イメージ | OS → Ubuntu 24.04 (x86_64) |
| 料金タイプ | 時間課金 |
| プラン | 4GB |
| root パスワード | 9〜70文字、英数字と記号を混ぜる |
| セキュリティグループ | `IPv4v6-SSH` ＋ `IPv4v6-Web` ＋ `IPv4v6-ICMP`（default は外す） |
| SSH Key | キーを新規作成 → インポート → 公開鍵（`.pub` の中身）を貼って「追加」 |

4GB が選べないときは、アカウントの上限です。「上限追加申請」（審査あり）が必要です。

### 2. root でログインし、土台をつくる

```bash
ssh -i ~/.ssh/conoha_ws_ed25519 root@<IPアドレス>
git clone <このリポジトリのURL> vps-setup
cd vps-setup
bash 01-base.sh workshop        # 途中で sudo 用パスワードを決める
```

作成直後は Ubuntu の自動更新が終わるまで数分〜10分ほど待つことがあります（スクリプトは自動で待ちます）。

**root の画面は閉じずに、別のターミナルで**作業用ユーザーで入れることを確認します。

```bash
ssh -i ~/.ssh/conoha_ws_ed25519 workshop@<IPアドレス>
sudo whoami                     # root と出れば OK
```

締め出されたときは、コントロールパネルの「コンソール」から root でログインして直せます。

### 3〜5. 作業用ユーザーで、HTTPS・Dify・Next.js

```bash
git clone <このリポジトリのURL> vps-setup
cd vps-setup
bash 02-web-front.sh auto <メールアドレス>       # 最後に出る https://… の URL をメモ
bash 03-dify.sh                                  # 約4分。https://<ホスト名>/install で管理者を作成
bash 04-nextjs-app.sh https://github.com/<ID>/<リポジトリ>.git   # アプリがなければ URL なし
```

`<メールアドレス>` は証明書の期限切れ通知が届くアドレスです。実行すると Let's Encrypt の利用規約に同意したことになります。

### 6. Dify と Next.js をつなぐ

1. Dify の右上 → 設定 → モデルプロバイダーで AI の API キーを登録
2. 「チャットボット」を作って「公開する」
3. 「API アクセス」で `app-` から始まるキーを発行
4. VPS でキーを書いて再起動

   ```bash
   nano /srv/apps/site/.env.local     # DIFY_API_KEY=app-xxxx
   sudo systemctl restart nextapp
   ```

5. サンプルアプリなら `https://<ホスト名>/site/chat` で会話できれば完成

### 7. 独自ドメインを追加する（任意）

1. ドメインの DNS 管理画面で A レコードを追加します。

   | 種類 | 名前（ホスト） | 値 |
   |---|---|---|
   | A | `ai`（`ai.example.com` の場合。ドメインそのものなら `@`） | VPS の IPv4 アドレス |

   Cloudflare の場合はプロキシをオフ（DNS only・灰色の雲）にします。

2. 反映を確認します（手元のPCで。VPS の IP が返れば OK）。

   ```bash
   nslookup ai.example.com
   ```

3. VPS で実行します。

   ```bash
   bash 05-add-domain.sh ai.example.com <メールアドレス>
   ```

`https://ai.example.com/`（Dify）と `https://ai.example.com/site`（Next.js）で開けます。自動ホスト名の URL も引き続き使えます。

### 8. 片付け

時間課金は、**停止していても削除するまで課金**されます。使い続けないなら、コントロールパネル → サーバー → 自分の VPS →「サーバー削除」。削除すると元に戻せません。

## 困ったとき

| 症状 | 原因 | 対処 |
|---|---|---|
| `Could not get lock` | 作成直後の自動更新 | 待つ |
| `Permission denied (publickey)` | 鍵の指定ちがい | `-i` のパスと、ConoHa に登録した公開鍵を確認 |
| 「Dify を準備中です」 | Dify の起動途中 | 1〜2分待って再読み込み |
| `/site` の表示が崩れる | `basePath` がない | `next.config` と、`fetch`・画像のパスに `/site` |
| 証明書が取れない | 発行上限など | 講師に相談 |
| `DNS が未反映です` | A レコードの値・反映待ち・Cloudflare のプロキシ | 値を確認して数分待つ |

ログの見方：`journalctl -u nextapp -f`（Next.js）、`cd ~/dify/docker && docker compose logs -f api`（Dify）
