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

# Dockerコンテナ → docker0ゲートウェイ経由でプロキシへ中継するためのリレーポート
# WSL2 mirrored networkingモードでは、docker0のような仮想ブリッジ経由のアドレスから
# Windows側のプロキシへ直接到達できない既知の制限があるため、
# WSL2内部でリレー(socat)を立て、127.0.0.1へ転送する
RELAY_PORT="3129"

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
# 戻り値 / グローバル変数 USE_PROXY で判定結果を呼び出し元に伝える。
# このスクリプト自体を終了させる判断は行わず、呼び出し元(メイン処理)に委ねる。
#   - プロキシ設定あり            -> USE_PROXY=true,  return 0
#   - プロキシ設定なし、続行を選択 -> USE_PROXY=false, return 0
#   - プロキシ設定なし、中止を選択 -> return 1 (呼び出し元でexitを判断させる)
check_proxy_env() {
    if [[ -n "${http_proxy:-}" && -n "${https_proxy:-}" ]]; then
        USE_PROXY=true
        return 0
    fi

    echo "[WRN] 'http_proxy' or 'https_proxy' are not found."
    echo "[WRN] IF THE PROXY SETTINGS ARE NEEDED, PLEASE DEFINE PROXY ADDRESS IN THIS SCRIPT."
    echo "[WRN]   http_proxy  : ${http_proxy:-(未設定)}"
    echo "[WRN]   https_proxy : ${https_proxy:-(未設定)}"
    echo ""
    read -r -p "Do you want to set up Docker w/o proxy settings? [y/N]: " answer
    case "$answer" in
        [yY][eE][sS]|[yY])
            echo "[INF] It continues process w/o proxy settings."
            USE_PROXY=false
            return 0
            ;;
        *)
            return 1
            ;;
    esac
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

# docker0 ブリッジのgatewayアドレスを取得する
# 見つからない場合は空文字を返す（呼び出し側でハンドリングする）
get_docker_gateway() {
    ip -4 addr show docker0 2>/dev/null | grep -oP 'inet \K[\d.]+' || true
}

# Dockerデーモン用のプロキシ設定を行う
# 呼び出し元で USE_PROXY=true の場合のみ呼び出すこと
setup_dockerd_proxy() {
    echo "[INF] Now making proxy configuration for Docker daemon..."
 
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
 
    echo "[INF] Generated done: ${proxy_conf}"
    echo "[INF] Restarging systemd and Docker daemon..."
 
    systemctl daemon-reload
    systemctl restart docker
 
    if systemctl is-active --quiet docker; then
        echo "[INF] It finished proxy setting for Docker daemon."
    else
        echo "[WRN] It may failed to restart Docker. Run 'systemctl status docker' and check status."
    fi
}

# docker0ゲートウェイ → 127.0.0.1(WSL2ループバック) への socat リレーを設定する
# WSL2 mirrored networkingモードでは、docker0経由の実IPからWindows側プロキシへ
# 直接到達できない既知の制限があるため、この中継が必要になる
# 呼び出し元で USE_PROXY=true の場合のみ呼び出すこと
setup_socat_relay() {
    echo "[INF] Now setting up socat relay for container proxy access..."

    if ! command -v socat >/dev/null 2>&1; then
        echo "[ERR] socat is not installed. Skipping relay setup."
        return 1
    fi

    local docker_gateway
    docker_gateway=$(get_docker_gateway)

    if [[ -z "$docker_gateway" ]]; then
        echo "[WRN] docker0 interface was not found. Skipping socat relay setup."
        echo "[WRN] Please configure the relay manually after Docker starts (see setup_socat_relay in this script)."
        return 1
    fi

    # http_proxy からリレー先(WSL2ループバック側)のホスト:ポートを取り出す
    # 例: http://127.0.0.1:3128 -> 127.0.0.1:3128
    local upstream_proxy="${http_proxy#http://}"
    upstream_proxy="${upstream_proxy%/}"

    local relay_conf="/etc/systemd/system/docker-proxy-relay.service"

    cat > "$relay_conf" << EOF
[Unit]
Description=Relay docker0 gateway proxy requests to WSL2 loopback (mirrored networking workaround)
After=network.target docker.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:${RELAY_PORT},bind=${docker_gateway},fork,reuseaddr TCP:${upstream_proxy}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    chmod 0644 "$relay_conf"

    echo "[INF] Generated done: ${relay_conf}"
    echo "[INF]   Relay: ${docker_gateway}:${RELAY_PORT} -> ${upstream_proxy}"

    systemctl daemon-reload
    systemctl enable --now docker-proxy-relay.service

    if systemctl is-active --quiet docker-proxy-relay.service; then
        echo "[INF] docker-proxy-relay.service is running."
    else
        echo "[WRN] Failed to start docker-proxy-relay.service. Run 'systemctl status docker-proxy-relay.service' to check."
    fi
}

# Docker用のプロキシ設定を行う（コンテナへ注入される ~/.docker/config.json）
# 宛先は socat リレー（docker0ゲートウェイ:RELAY_PORT）を指す
# 呼び出し元で USE_PROXY=true の場合のみ呼び出すこと
setup_docker_proxy() {
    echo "[INF] Now making configuration for Docker..."

    local target_home
    target_home="/home/${CURRENT_USER}"

    if [[ -z "$target_home" ]]; then
        echo "[ERR] Home directory of ${CURRENT_USER} is not found."
        return 1
    fi

    local docker_gateway
    docker_gateway=$(get_docker_gateway)

    if [[ -z "$docker_gateway" ]]; then
        echo "[WRN] docker0 interface was not found. Falling back to default gateway 172.17.0.1."
        echo "[WRN] Please verify this matches your environment after setup."
        docker_gateway="172.17.0.1"
    fi

    local proxy_dir="${target_home}/.docker"
    local proxy_conf="${proxy_dir}/config.json"
    echo "[INF] Docker local config: ${proxy_conf}"
    echo "[INF]   Proxy target for containers: ${docker_gateway}:${RELAY_PORT}"

    install -d -m 0755 -o "$CURRENT_USER" -g "$CURRENT_USER" "$proxy_dir"

    if [ -f "${proxy_conf}" ]; then
        echo "[WRN] ${proxy_conf} is already existing. Please configure proxy setting manually if needed."
    else
        cat > "${proxy_conf}" << EOF
{
  "proxies": {
    "default": {
      "httpProxy": "http://${docker_gateway}:${RELAY_PORT}",
      "httpsProxy": "http://${docker_gateway}:${RELAY_PORT}",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
EOF
        chown "$CURRENT_USER":"$CURRENT_USER" "${proxy_conf}"
        echo "[INF] Generate done: ${proxy_conf}"
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
# USE_PROXY はこの後の各種プロキシ設定処理の呼び出し要否判定に使う
USE_PROXY=false
if ! check_proxy_env; then
    echo "[ERR] Exit process."
    exit 1
fi

CURRENT_USER=${SUDO_USER:-$(whoami)}        # SUDO_USERが設定されていない場合はwhoamiで取得
echo "[INF] Current user: $CURRENT_USER"

# パッケージリストの更新
apt update

# --- 共通依存パッケージのインストール ---
echo ""
echo "[INF] Checking and installing common dependencies..."
for pkg in ca-certificates curl wget gpg apt-transport-https socat git git-lfs; do
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
if $USE_PROXY; then
    setup_dockerd_proxy
else
    echo "[INF] Skip proxy configuration for Docker daemon as there is no proxy settings."
fi

# --- docker0ゲートウェイ→WSL2ループバックへの中継設定 ---
# (docker0 ブリッジは dockerd 起動時に作成されるため、上記の setup_dockerd_proxy
#  によるサービス再起動より後、かつコンテナ向け設定より前に実行する)
echo ""
if $USE_PROXY; then
    setup_socat_relay
else
    echo "[INF] Skip socat relay setup as there is no proxy settings."
fi

# --- Docker用プロキシ設定(コンテナへの注入用) ---
echo ""
if $USE_PROXY; then
    setup_docker_proxy
else
    echo "[INF] Skip proxy configuration for Docker client as there is no proxy settings."
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
echo "[INF]"
echo "[INF] If proxy is configured, you can verify the relay with:"
echo "[INF]   $ systemctl status docker-proxy-relay.service"
echo "[INF]   $ docker run --rm alpine sh -c \"apk add curl -q && curl -v -x http://\$(ip -4 addr show docker0 | grep -oP 'inet \\K[\\d.]+'):${RELAY_PORT} https://example.com\""
echo "[INF] ###################################################"
echo ""
