#!/bin/bash

# ヘルプ表示
usage() {
    echo "Usage: $0"
    echo "This script updates the package list on a Debian-based system."
    echo "Please run it with superuser privileges."
    exit 1
}

# パッケージのインストール確認
check_installed() {
    local name=$1
    if dpkg -l | grep -qw "$name"; then
        echo "Package '$name' is already installed."
        return 0
    else
        echo "Package '$name' is not installed."
        return 1
    fi
}

# -h または --help が指定された場合にヘルプを表示
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
fi

# Superuser権限の確認
if [[ $EUID -ne 0 ]]; then
    echo "[ERR] This script must be run as root. Please use 'sudo'."
    echo ""
    exit 1
fi

# 開始メッセージ
echo "[INF] Starting Docker setup script..."

# パッケージリストの更新
apt update

# パッケージのインストール確認とインストール
echo ""
echo "[INF] Checking and installing required packages..."
if ! check_installed "ca-certificates"; then
    apt install -y ca-certificates
fi
if ! check_installed "curl"; then
    apt install -y curl
fi

# Dockerの公式GPGキーを追加
echo ""
echo "[INF] Adding Docker's official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# 'apt'コマンドのソースにDockerリポジトリを追加
echo ""
echo "[INF] Adding Docker repository to APT sources..."
tee /etc/apt/sources.list.d/docker.sources << EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# パッケージリストの再更新
echo ""
echo "[INF] Updating package list..."
apt update

# Docker Engine、CLI、Containerdのインストール
echo ""
echo "[INF] Installing Docker Engine, CLI, and Containerd..."
VERSION_STRING=5:29.1.3-1~ubuntu.24.04~noble
apt install -y docker-ce=$VERSION_STRING docker-ce-cli=$VERSION_STRING containerd.io docker-buildx-plugin docker-compose-plugin

# 不要なパッケージの削除
echo ""
echo "[INF] Cleaning up unnecessary packages..."
apt autoremove -y

# カレントユーザーをdockerグループに追加
echo ""
echo "[INF] Adding current user to 'docker' group..."
groupadd docker 2>/dev/null
CURRENT_USER=${SUDO_USER:-$(whoami)}        # SUDO_USERが設定されていない場合はwhoamiで取得
echo "[INF] Current user: $CURRENT_USER"
usermod -aG docker "$CURRENT_USER"

# グループ追加を確認
echo "[INF] Verifying docker group membership..."
if id -nG "$CURRENT_USER" | grep -qw docker; then
    echo "[INF] User '$CURRENT_USER' successfully added to docker group."
else
    echo "[WRN] User '$CURRENT_USER' could not be added to docker group."
fi

# 完了メッセージ
echo ""
echo "[INF] Docker setup script completed successfully."
echo ""
echo "[INF] #################### ATTENTION #####################"
echo "[INF] You must restart WSL2 to apply the group changes."
echo "[INF] Exit WSL2 terminal and restart it."
echo "[INF] ###################################################"
echo ""
