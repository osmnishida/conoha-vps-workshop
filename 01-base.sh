#!/usr/bin/env bash
# VPS の土台づくり（作成直後に root で1回実行）
#   作業用ユーザー作成・SSH 強化・ufw・パッケージ更新・Docker・fail2ban・swap など
#
# 使い方（root でログインして）:
#   bash 01-base.sh <作業用ユーザー名>
# 実行後は「別のターミナルで」作業用ユーザーでログインできることを確認してから root の画面を閉じる。
set -euo pipefail

USER_NAME="${1:?作業用ユーザー名を指定してください（例: workshop）}"
[ "$(id -u)" -eq 0 ] || { echo "root（または sudo）で実行してください"; exit 1; }
export DEBIAN_FRONTEND=noninteractive
APT="apt-get -o DPkg::Lock::Timeout=900 -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
say() { printf "\n\033[1;32m==> %s\033[0m\n" "$*"; }

say "1/8 タイムゾーン"
timedatectl set-timezone Asia/Tokyo

say "2/8 作業用ユーザー $USER_NAME"
if ! id "$USER_NAME" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$USER_NAME"
  echo "sudo で使うパスワードを決めてください"
  passwd "$USER_NAME"
fi
usermod -aG sudo "$USER_NAME"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "/home/$USER_NAME/.ssh"
[ -f "/home/$USER_NAME/.ssh/authorized_keys" ] || \
  install -m 600 -o "$USER_NAME" -g "$USER_NAME" /root/.ssh/authorized_keys "/home/$USER_NAME/.ssh/authorized_keys"

say "3/8 パッケージ更新（作成直後は自動更新が終わるまで待つことがあります）"
apt-get -o DPkg::Lock::Timeout=900 update -q >/dev/null
$APT upgrade >/dev/null

say "4/8 Docker（公式リポジトリ）と基本ツール"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get -o DPkg::Lock::Timeout=900 update -q >/dev/null
$APT install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  nginx certbot python3-certbot-nginx fail2ban git jq curl bc ntpsec ntpsec-ntpdate sysstat >/dev/null
usermod -aG docker "$USER_NAME"

say "5/8 swap 2GB と sysctl"
if ! swapon --show | grep -q /var/spool/swap/swapfile; then
  install -d /var/spool/swap
  fallocate -l 2G /var/spool/swap/swapfile
  chmod 600 /var/spool/swap/swapfile
  mkswap /var/spool/swap/swapfile >/dev/null
  swapon /var/spool/swap/swapfile
fi
grep -q swapfile /etc/fstab || echo "/var/spool/swap/swapfile    none    swap    defaults    0 0" >> /etc/fstab
echo "vm.overcommit_memory = 1" > /etc/sysctl.d/99-dify.conf
sysctl -q --system

say "6/8 fail2ban（SSH の総当たり対策）"
cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
bantime  = 86400
findtime  = 600
maxretry = 5
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

say "7/8 SSH 強化（root ログイン・パスワードログインを禁止）"
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sshd -t
systemctl restart ssh

say "8/8 ufw（22/80/443 のみ許可）"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw default deny routed >/dev/null
ufw --force enable >/dev/null
ufw status | head -1

echo
echo "完了。別のターミナルで： ssh -i <秘密鍵> $USER_NAME@$(curl -4 -s https://ifconfig.me)"
[ -f /var/run/reboot-required ] && echo "※ 再起動が必要です：確認後に sudo reboot" || true
