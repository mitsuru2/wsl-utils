# wsl-utils

WSL2 (Ubuntu/Debian) 環境のセットアップや設定を効率化するためのユーティリティスクリプト集です。

## 収録スクリプト一覧

### 1. setup-remote-development.sh
WSL2上のUbuntu/Debian系システムにリモート開発環境を構築するために必要なツール一式をインストール・設定します。

- Docker Engine のインストールと、現在のユーザーの `docker` グループへの追加（`sudo` なしでDockerコマンドを実行できるようにする）
- `git` のインストール

#### 使い方

```bash
chmod +x setup-remote-development.sh
sudo ./setup-remote-development.sh
```

#### 注意点
スクリプト実行後、`docker` グループおよび `wsl.conf` の設定を反映させるために必ずWSL2を再起動（PowerShell等から `wsl --shutdown` を実行）してください。

## 動作要件
- WSL2 (Ubuntu または Debian)
- root 権限 (sudo)
