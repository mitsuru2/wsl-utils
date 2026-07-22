# wsl-utils

WSL2 (Ubuntu/Debian) 環境のセットアップや設定を効率化するためのユーティリティスクリプト集です。

## 収録スクリプト一覧

### 1. setup-docker.sh
WSL2上のUbuntu/Debian系システムにDocker Engineを自動インストールし、`sudo` なしでDockerコマンドを実行できるように現在のユーザーを `docker` グループに追加します。

#### 使い方

```bash
chmod +x setup-docker.sh
sudo ./setup-docker.sh
```

#### 注意点
スクリプト実行後、グループ設定を反映させるために必ずWSL2を再起動（PowerShell等から `wsl --shutdown` を実行）してください。

### 2. setup-other-tools.sh
WSL2上のUbuntu/Debian系システムに `git` と VS Code (Linux版) をインストールし、VS Codeに Remote Development 拡張パック (`ms-vscode-remote.vscode-remote-extensionpack`) を導入したうえで、`/etc/wsl.conf` に `appendWindowsPath = false` を設定します。

#### 使い方

```bash
chmod +x setup-other-tools.sh
sudo ./setup-other-tools.sh
```

#### 注意点
スクリプト実行後、`wsl.conf` の設定を反映させるために必ずWSL2を再起動（PowerShell等から `wsl --shutdown` を実行）してください。

## 動作要件
- WSL2 (Ubuntu または Debian)
- root 権限 (sudo)

