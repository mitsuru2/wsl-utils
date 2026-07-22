#!/bin/bash

# ==============================================================================
# Other Tools Setup Script for WSL2 (Ubuntu/Debian)
#
# このスクリプトは、WSL2上のUbuntu/Debian系システムにDocker以外の
# 開発ツールをインストールし、WSL2の設定を変更します。
# 主な処理内容は以下の通りです：
#   1. git のインストール
#   2. VS Code (Linux版) のインストール
#   3. VS Code Remote Development 拡張パックのインストール
#   4. /etc/wsl.conf に appendWindowsPath = false を設定
#
# 使用方法: sudo ./setup-other-tools.sh
# ==============================================================================

# ヘルプ表示
usage() {
    echo "Usage: $0"
    echo "This script installs git and VS Code, and updates /etc/wsl.conf on a Debian-based system."
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

# VS Code拡張機能のインストール確認（実行ユーザー権限で確認）
check_extension_installed() {
    local extension_id=$1
    local user=$2
    if sudo -H -u "$user" code --list-extensions 2>/dev/null | grep -qiw "$extension_id"; then
        echo "Extension '$extension_id' is already installed."
        return 0
    else
        echo "Extension '$extension_id' is not installed."
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
echo "[INF] Starting other tools setup script..."

# パッケージリストの更新
apt update

# --- git のインストール ---
echo ""
echo "[INF] Checking and installing git..."
if ! check_installed "git"; then
    apt install -y git
fi

# --- VS Code のインストール ---
echo ""
echo "[INF] Checking and installing required packages for VS Code repository..."
if ! check_installed "wget"; then
    apt install -y wget
fi
if ! check_installed "gpg"; then
    apt install -y gpg
fi
if ! check_installed "apt-transport-https"; then
    apt install -y apt-transport-https
fi

# Microsoftの公式GPGキーを追加
echo ""
echo "[INF] Adding Microsoft's official GPG key..."
install -m 0755 -d /etc/apt/keyrings
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/keyrings/packages.microsoft.gpg
chmod a+r /etc/apt/keyrings/packages.microsoft.gpg

# 'apt'コマンドのソースにVS Codeリポジトリを追加
echo ""
echo "[INF] Adding VS Code repository to APT sources..."
tee /etc/apt/sources.list.d/vscode.sources << EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /etc/apt/keyrings/packages.microsoft.gpg
EOF

# パッケージリストの再更新
echo ""
echo "[INF] Updating package list..."
apt update

# VS Codeのインストール
echo ""
echo "[INF] Installing VS Code..."
if ! check_installed "code"; then
    apt install -y code
fi

# 不要なパッケージの削除
echo ""
echo "[INF] Cleaning up unnecessary packages..."
apt autoremove -y

# --- VS Code Remote Development 拡張パックのインストール ---
echo ""
echo "[INF] Installing VS Code Remote Development Extension Pack..."
EXTENSION_ID="ms-vscode-remote.vscode-remote-extensionpack"
CURRENT_USER=${SUDO_USER:-$(whoami)}        # SUDO_USERが設定されていない場合はwhoamiで取得
echo "[INF] Current user: $CURRENT_USER"
if ! check_extension_installed "$EXTENSION_ID" "$CURRENT_USER"; then
    sudo -H -u "$CURRENT_USER" code --install-extension "$EXTENSION_ID" --force
fi

# --- /etc/wsl.conf の設定変更 ---
echo ""
echo "[INF] Configuring /etc/wsl.conf (appendWindowsPath = false)..."

WSL_CONF="/etc/wsl.conf"

# ファイルが存在しない場合は作成
if [[ ! -f "$WSL_CONF" ]]; then
    touch "$WSL_CONF"
fi

if grep -q "^\[interop\]" "$WSL_CONF"; then
    if grep -q "^\s*appendWindowsPath\s*=" "$WSL_CONF"; then
        # appendWindowsPathキーが既に存在する場合は値を上書き
        sed -i "s/^\s*appendWindowsPath\s*=.*/appendWindowsPath = false/" "$WSL_CONF"
    else
        # [interop]セクションが存在する場合はその直後にキーを追加
        sed -i "/^\[interop\]/a appendWindowsPath = false" "$WSL_CONF"
    fi
else
    # [interop]セクションが存在しない場合は新規追加
    {
        echo ""
        echo "[interop]"
        echo "appendWindowsPath = false"
    } >> "$WSL_CONF"
fi

echo "[INF] Current /etc/wsl.conf contents:"
cat "$WSL_CONF"

# 完了メッセージ
echo ""
echo "[INF] Other tools setup script completed successfully."
echo ""
echo "[INF] #################### ATTENTION #####################"
echo "[INF] You must restart WSL2 to apply the wsl.conf changes."
echo "[INF] Exit WSL2 terminal and run 'wsl --shutdown' from PowerShell."
echo "[INF] ###################################################"
echo ""
