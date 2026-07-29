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

# Windows側のVS Code (code コマンド) がWSLから利用可能か確認する
check_code_command() {
    local user=$1

    if ! sudo -H -u "$user" bash -lc 'command -v code' >/dev/null 2>&1; then
        echo "[WRN] 'code' コマンドが見つかりません。"
        echo "[WRN] WSLのPATH共有設定(interop.appendWindowsPath)が有効か確認してください。"
        echo "[WRN] また、Windows側でVS Codeがインストールされているか確認してください。"
        return 1
    fi

    local code_path
    code_path=$(sudo -H -u "$user" bash -lc 'command -v code')
    echo "[INF] 'code' コマンドが見つかりました: $code_path"

    if [[ "$code_path" != *"/mnt/"* ]]; then
        echo "[WRN] 'code' コマンドがWindows側の実体を指していない可能性があります(パス: $code_path)。"
        echo "[WRN] WSL内にLinux版VS Codeが別途インストールされていないか確認してください。"
    fi

    if sudo -H -u "$user" bash -lc 'timeout 10 code --version' >/dev/null 2>&1; then
        echo "[INF] 'code --version' が正常に応答しました。"
        return 0
    else
        echo "[WRN] 'code --version' がタイムアウトまたはエラーになりました。"
        echo "[WRN] PATH共有は有効でも、Windows側のVS Code起動自体に問題がある可能性があります。"
        return 1
    fi
}

# Windows側のVS CodeにRemote Development拡張パックをインストールする
install_vscode_extension() {
    local extension_id=$1
    local user=$2

    echo "[INF] Checking installed extensions on Windows VS Code..."
    if sudo -H -u "$user" bash -lc "timeout 30 code --list-extensions 2>/dev/null" | grep -qiw "$extension_id"; then
        echo "[INF] Extension '$extension_id' is already installed."
        return 0
    fi

    echo "[INF] Installing extension '$extension_id'..."
    if sudo -H -u "$user" bash -lc "timeout 60 code --install-extension '$extension_id' --force"; then
        echo "[INF] Extension '$extension_id' installed successfully."
        return 0
    else
        echo "[WRN] Extension '$extension_id' の インストールに失敗しました。"
        return 1
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
echo "[INF] Exit WSL2 terminal and run 'wsl --shutdown' from PowerShell."
echo "[INF] ###################################################"
echo ""
