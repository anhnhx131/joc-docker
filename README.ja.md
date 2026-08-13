# joc-docker (`jocd`)

English: [README.md](README.md)

**JOC (Japan Open Chain) PoSA Validator Client のみ** を自分で管理するインフラ
上で動かすための、bash 製の小さな CLI です（ガイドの Option 2 に対応） —
自前の Execution/Consensus Client は動かさず、Validator Client 部分のみを
扱います。アーキテクチャ、ガイドとの対応関係、セキュリティモデル、ガイドから
逸脱・推測した点の詳細な自己レビューは [CLAUDE.md](CLAUDE.md) を参照してください。

## 前提条件

- 自分で管理できる Linux/macOS マシン（EC2、VPS、オンプレなど、常時起動できる
  もの）。
- `git` — 大抵のイメージには最初から入っています。下の `git clone` で
  "command not found" と出た場合:
  - Ubuntu（EC2 の Ubuntu、GCP のデフォルトイメージ含む）: `sudo apt-get update -y && sudo apt-get install -y git`
  - Amazon Linux / RHEL 系（EC2 の Amazon Linux 含む）: `sudo dnf install -y git`（古い Amazon Linux 2 の場合: `sudo yum install -y git`）
- [Docker](https://docs.docker.com/engine/install/) — 未インストールの場合は
  `jocd install` で導入できます。
- ガイドの Step 1-1（受取用 withdrawal address の取得）・Step 1-2（JOC PoSA
  ネットワークへの参加）が完了していること。
- ニーモニックフレーズをオフラインで安全に書き留める手段。

## クイックスタート（Validator Client のみ）

```bash
git clone git@github.com:anhnhx131/joc-docker.git
cd joc-docker
./jocd install       # Docker が未インストールならインストール
./jocd init
```

`networks/<NETWORK>/cl/` にはこのリポジトリが管理しているネットワーク設定が
既に入っています。ご利用のネットワーク分が無い/古い場合は、`jocd init` が
不足しているものと取得方法を明示してくれるので、事前に自分で取得しておく
必要はありません。

`jocd init` はネットワークと withdrawal address の入力を求めた後、
ニーモニック/キーを生成し、Validator Client を起動します。**ニーモニックは
一度だけ表示されます — `yes` と入力して続行する前に、必ず紙に書き留めて
ください。** ニーモニック、keystore、`password.txt` は誰にも共有しないで
ください。

Validator は `BEACON_URL` が無効なプレースホルダーの状態で起動します —
実際の Consensus Client のエンドポイント（例: ガイド Step 2-5 で開いた
BCCloud ノード）を設定するまで、attest は行われません:

```bash
./jocd validator config beacon http://<bccloud-node-ip>:3500
./jocd status
```

`data/validator_keys/deposit_data-xxx.json` を Launchpad に提出してください
（`./jocd validator deposit-data` でいつでも再表示できます）。

## コマンド一覧

| コマンド | 内容 |
| --- | --- |
| `jocd install` | Docker が未インストールならインストール |
| `jocd init` | 初回セットアップ：キー生成、deposit data 作成、validator 起動 |
| `jocd validator config [key] [value]` | `address` / `beacon` の確認・変更 |
| `jocd validator deposit-data` | deposit data の再表示 |
| `jocd status` | 稼働状況の確認 |
| `jocd up` / `down` / `logs` | 日常運用のライフサイクル操作 |
| `jocd restart` | ハードフォーク等で `config.yaml` を更新した際の反映 |
| `jocd upgrade` | `git pull` によるこの CLI 自体の更新 |
| `jocd destroy` | キー・deposit data・`.env` の完全削除（元に戻せません） |

各コマンドの内部動作とその理由は [CLAUDE.md](CLAUDE.md) を参照してください。
