# joc-docker (`jocv`)

日本語版: [README.ja.md](README.ja.md)

A small bash-only CLI for running a **JOC (Japan Open Chain) PoSA
Validator Client** on infrastructure you control (guide Option 2). See
[CLAUDE.md](CLAUDE.md) for architecture, guide-fidelity notes, the full
security model, and the complete self-review of what's guide-verbatim
vs. inferred.

## Prerequisites

- A Linux/macOS machine you control (EC2, VPS, on-prem — anything that
  stays online).
- [Docker](https://docs.docker.com/engine/install/) — run `jocv install`
  if you don't have it yet.
- Guide Step 1-1 (receiver withdrawal address) and Step 1-2 (joined the
  JOC PoSA network) already done.
- A private, offline way to write down a mnemonic phrase.

## Quick start

```bash
git clone git@github.com:anhnhx131/joc-docker.git
cd joc-docker
./jocv install       # installs Docker if missing
```

Get `config.yaml` + `deposit_contract_block.txt` for your network (from
the [JOC page](https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/)
or your team) and place them at `networks/mainnet/cl/` (swap `mainnet`
for `testnet`/`sandbox` as needed — see [networks/README.md](networks/README.md)).

```bash
./jocv init
```

Prompts for your network and withdrawal address, then generates your
mnemonic/keys and starts the Validator Client. **The mnemonic is shown
once — write it down on paper before typing `yes` to continue.** Never
share it, the keystore, or `password.txt` with anyone.

On BCCloud (manual — create a Transaction Cluster, add an External
Validator node with the `pubkey` from `deposit_data-xxx.json`, open the
Consensus HTTP API to this machine), then connect:

```bash
./jocv validator config beacon http://<bccloud-node-ip>:3500
./jocv status
```

Submit `data/validator_keys/deposit_data-xxx.json` to Launchpad (reprint
it anytime with `./jocv validator deposit-data`).

## Commands

| Command | What it does |
| --- | --- |
| `jocv install` | Install Docker if missing |
| `jocv init` | First-time setup: keys, deposit data, start the validator |
| `jocv validator config [key] [value]` | View/change `address` or `beacon` |
| `jocv validator deposit-data` | Reprint the deposit data |
| `jocv status` | Health check |
| `jocv up` / `down` / `logs` | Day-to-day lifecycle |
| `jocv restart` | Apply a `config.yaml` update (hard fork) |
| `jocv upgrade` | Update this CLI via `git pull` |
| `jocv destroy` | Permanently wipe keys/deposit data/`.env` (irreversible) |

See [CLAUDE.md](CLAUDE.md) for what each command does under the hood and
why.
