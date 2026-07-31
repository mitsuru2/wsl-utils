#!/bin/bash
set -euo pipefail

# ==============================================================================
# Remote Development Setup Script for WSL2 (Ubuntu/Debian)
#
# このスクリプトは、WSL2上のUbuntu/Debian系システムにリモート開発環境を
# 構築するために必要なツール一式をインストール・設定します。
# 主な処理内容は以下の通りです：
#   1. Docker Engineのインストールと、現在のユーザーのdockerグループへの追加
#   2. git のインストール
#
# 使用方法: sudo ./setup-remote-development.sh
# ==============================================================================

# プロキシ設定
# 必要な場合は以下のコメントアウトを解除してプロキシアドレスを設定してください。
# export http_proxy="http://127.0.0.1:3128"
# export https_proxy="http://127.0.0.1:3128"

# ヘルプ表示
usage() {
    echo "Usage: $0"
    echo "This script sets up a remote development environment (Docker, git) on a Debian-based system."
    echo "Please run it with superuser privileges."
    echo
    echo "NOTE: VS Code is not installed on Linux env. You must install it on Windows env with Remote."
    exit 1
}

# プロキシ環境変数の確認
check_proxy_env() {
    if [[ -z "${http_proxy:-}" || -z "${https_proxy:-}" ]]; then
        echo "[WRN] http_proxy または https_proxy が設定されていません。"
        echo "[WRN] 必要な場合は、本スクリプトの20行目付近を確認してプロキシ設定を有効化してください。"
        echo "[WRN]   http_proxy  : ${http_proxy:-(未設定)}"
        echo "[WRN]   https_proxy : ${https_proxy:-(未設定)}"
        echo ""
        read -r -p "プロキシ未設定のまま処理を続行しますか？ [y/N]: " answer
        case "$answer" in
            [yY][eE][sS]|[yY])
                echo "[INF] 続行します。"
                ;;
            *)
                echo "[ERR] スクリプトを中止します。"
                exit 1
                ;;
        esac
    fi
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

# Dockerデーモン用のプロキシ設定を行う
# http_proxy / https_proxy が設定されている場合のみ、systemd drop-inファイルを作成する
setup_docker_proxy() {
    if [[ -z "${http_proxy:-}" && -z "${https_proxy:-}" ]]; then
        echo "[INF] プロキシが設定されていないため、Dockerデーモンへのプロキシ設定はスキップします。"
        return 0
    fi
 
    echo "[INF] Dockerデーモン用のプロキシ設定を行います..."
 
    local proxy_dir="/etc/systemd/system/docker.service.d"
    local proxy_conf="${proxy_dir}/http-proxy.conf"
 
    install -d -m 0755 "$proxy_dir"
 
    {
        echo "[Service]"
        [[ -n "${http_proxy:-}" ]]  && echo "Environment=\"HTTP_PROXY=${http_proxy}\""
        [[ -n "${https_proxy:-}" ]] && echo "Environment=\"HTTPS_PROXY=${https_proxy}\""
        [[ -n "${no_proxy:-}" ]]    && echo "Environment=\"NO_PROXY=${no_proxy}\""
    } > "$proxy_conf"
 
    chmod 0644 "$proxy_conf"
 
    echo "[INF] ${proxy_conf} を作成しました。"
    echo "[INF] systemdの設定を再読み込みし、Dockerを再起動します..."
 
    systemctl daemon-reload
    systemctl restart docker
 
    if systemctl is-active --quiet docker; then
        echo "[INF] Dockerデーモンへのプロキシ設定が完了しました。"
    else
        echo "[WRN] Dockerの再起動に失敗した可能性があります。'systemctl status docker' で確認してください。"
    fi
}


################################################################################
# メイン処理: ここから
################################################################################


# -h または --help が指定された場合にヘルプを表示
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

# Superuser権限の確認
if [[ $EUID -ne 0 ]]; then
    echo "[ERR] This script must be run as root. Please use 'sudo'."
    echo ""
    exit 1
fi

# 開始メッセージ
echo "[INF] Starting remote development setup script..."

# プロキシ設定確認
check_proxy_env

CURRENT_USER=${SUDO_USER:-$(whoami)}        # SUDO_USERが設定されていない場合はwhoamiで取得
echo "[INF] Current user: $CURRENT_USER"

# パッケージリストの更新
apt update

# --- 共通依存パッケージのインストール ---
echo ""
echo "[INF] Checking and installing common dependencies..."
for pkg in ca-certificates curl wget gpg apt-transport-https; do
    if ! check_installed "$pkg"; then
        apt install -y "$pkg"
    fi
done

# --- Docker Engine のインストール ---
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
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# カレントユーザーをdockerグループに追加
echo ""
echo "[INF] Adding current user to 'docker' group..."
groupadd docker 2>/dev/null || true
usermod -aG docker "$CURRENT_USER"

# グループ追加を確認
echo "[INF] Verifying docker group membership..."
if id -nG "$CURRENT_USER" | grep -qw docker; then
    echo "[INF] User '$CURRENT_USER' successfully added to docker group."
else
    echo "[WRN] User '$CURRENT_USER' could not be added to docker group."
fi

# --- Dockerデーモン用プロキシ設定 ---
echo ""
setup_docker_proxy

# --- git のインストール ---
echo ""
echo "[INF] Checking and installing git..."
if ! check_installed "git"; then
    apt install -y git
fi

# 完了メッセージ
echo ""
echo "[INF] Remote development setup script completed successfully."
echo ""
echo "[INF] #################### ATTENTION #####################"
echo "[INF] You must restart WSL2 to apply the docker group changes."
echo "[INF] Exit WSL2 terminal and run following command from PowerShell."
echo "[INF]   > wsl --shutdown"
echo "[INF]"
echo "[INF] You can run following command to test docker:"
echo "[INF]   $ docker run hello-world"
echo "[INF] ###################################################"
echo ""
