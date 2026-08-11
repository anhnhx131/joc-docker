# Quick start (`ROLE=validator`)

Fastest path to a running Validator Client (guide Option 2). Any Linux
box you can SSH into works — EC2, VPS, on-prem, doesn't matter. For
`el-cl`/`all` or anything not covered here, see [README.md](README.md).

> Before you start: have your **receiver withdrawal address** (guide Step
> 1-1) ready, and a private, offline way to write down a mnemonic phrase.

### 1. Get the code

```bash
git clone git@github.com:anhnhx131/joc-docker.git
cd joc-docker
```

### 2. Install Docker

```bash
./jocv install
```

No-ops if Docker's already there. If you were just added to the `docker`
group, log out/in (or `newgrp docker`) before continuing.

### 3. Add the network config

Get `config.yaml` + `deposit_contract_block.txt` for your network (from
the [JOC page](https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/)
or your team) and place them here:

```bash
networks/mainnet/cl/config.yaml
networks/mainnet/cl/deposit_contract_block.txt
```

(swap `mainnet` for `testnet`/`sandbox` as needed — see [networks/README.md](networks/README.md))

### 4. Initialize

```bash
./jocv init
```

Prompts for network, role (pick `validator`), and your withdrawal
address, then generates your mnemonic/keys. **The mnemonic is shown once
— write it down on paper before typing `yes` to continue.** Never share
it, the keystore, or `password.txt` with anyone.

### 5. On BCCloud (manual — not automated by this CLI)

- Create a Transaction Cluster
- Create a Validator Cluster → add an **External Validator** node, using
  the `pubkey` from `deposit_data-xxx.json` (path printed by `jocv init`)
- Open the Consensus HTTP API on that node, restricted to this machine's IP

Full detail: [README.md](README.md#what-this-is-not).

### 6. Connect to BCCloud

```bash
./jocv beacon set http://<bccloud-node-ip>:3500
```

### 7. Verify

```bash
./jocv status
```

Then submit `data/validator_keys/deposit_data-xxx.json` to Launchpad
(guide Step 3-1).

## Next

- `./jocv config` — change withdrawal address / beacon URL later
- `./jocv update-config <phase>` — apply a hard fork phase config
- `./jocv update` — pull the latest CLI/config from git
- `./jocv logs` / `./jocv down` — day-to-day operation
- `./jocv reset --data` — wipe keys/deposit data/`.env` to start over (irreversible)

Troubleshooting, the full command reference, and the multi-network/role
model: [README.md](README.md).
