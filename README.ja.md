# joc-docker (`jocv`)

English: [README.md](README.md)

**JOC (Japan Open Chain) PoSA Validator Client** を自分で管理するインフラ上で
動かすための、bash 製の小さな CLI です（ガイドの Option 2 に対応）。
アーキテクチャ、ガイドとの対応関係、セキュリティモデル、ガイドから逸脱・推測した
点の詳細な自己レビューは [CLAUDE.md](CLAUDE.md) を参照してください。

## 前提条件

- 自分で管理できる Linux/macOS マシン（EC2、VPS、オンプレなど、常時起動できる
  もの）。
- [Docker](https://docs.docker.com/engine/install/) — 未インストールの場合は
  `jocv install` で導入できます。
- ガイドの Step 1-1（受取用 withdrawal address の取得）・Step 1-2（JOC PoSA
  ネットワークへの参加）が完了していること。
- ニーモニックフレーズをオフラインで安全に書き留める手段。

## クイックスタート

```bash
git clone git@github.com:anhnhx131/joc-docker.git
cd joc-docker
./jocv install       # Docker が未インストールならインストール
```

ご自身のネットワーク用の `config.yaml` と `deposit_contract_block.txt` を
（[JOC のページ](https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/)
またはチームから取得し）`networks/mainnet/cl/` に配置してください
（`mainnet` は必要に応じて `testnet`/`sandbox` に置き換え — 詳細は
[networks/README.md](networks/README.md)）。

```bash
./jocv init
```

ネットワークと withdrawal address の入力を求められた後、ニーモニック/キーを
生成し、Validator Client を起動します。**ニーモニックは一度だけ表示されます —
`yes` と入力して続行する前に、必ず紙に書き留めてください。** ニーモニック、
keystore、`password.txt` は誰にも共有しないでください。

BCCloud 側の作業（手動 — Transaction Cluster の作成、`deposit_data-xxx.json`
の `pubkey` を使った External Validator ノードの追加、このマシンへの
Consensus HTTP API の公開）を行った後、接続します:

```bash
./jocv validator config beacon http://<bccloud-node-ip>:3500
./jocv status
```

`data/validator_keys/deposit_data-xxx.json` を Launchpad に提出してください
（`./jocv validator deposit-data` でいつでも再表示できます）。

## コマンド一覧

| コマンド | 内容 |
| --- | --- |
| `jocv install` | Docker が未インストールならインストール |
| `jocv init` | 初回セットアップ：キー生成、deposit data 作成、validator 起動 |
| `jocv validator config [key] [value]` | `address` / `beacon` の確認・変更 |
| `jocv validator deposit-data` | deposit data の再表示 |
| `jocv status` | 稼働状況の確認 |
| `jocv up` / `down` / `logs` | 日常運用のライフサイクル操作 |
| `jocv restart` | ハードフォーク等で `config.yaml` を更新した際の反映 |
| `jocv upgrade` | `git pull` によるこの CLI 自体の更新 |
| `jocv destroy` | キー・deposit data・`.env` の完全削除（元に戻せません） |

各コマンドの内部動作とその理由は [CLAUDE.md](CLAUDE.md) を参照してください。
