# networks/

One directory per JOC network:

```
networks/
├── mainnet/
│   ├── el/
│   │   ├── genesis.json         # Geth genesis for JOC mainnet
│   │   └── bootnodes.txt        # EL bootnodes, one enode:// per line
│   └── cl/
│       ├── config.yaml               # currently-applied consensus config
│       ├── deposit_contract_block.txt
│       ├── genesis.ssz               # optional: precomputed genesis state
│       └── bootnodes.txt             # CL bootnodes (ENRs), one per line
├── testnet/    (same layout)
└── sandbox/    (same layout)
```

`jocv` picks which of these to use based on `NETWORK` in `.env`
(`mainnet` | `testnet` | `sandbox`).

## What goes here and from where

These are **public network parameters, not secrets** (chain ID, genesis,
bootnodes, fork epochs) — safe to commit to git, unlike `data/` or `.env`.

- `cl/config.yaml`, `cl/deposit_contract_block.txt` — per the guide, Step
  2-1: download from the JOC page
  (https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/)
  or receive from JBF/admin, and place here (or commit them here so
  validators get them via `git pull` — see the root README's
  ["Updating config via git"](../README.md#updating-config-via-git)).
  A new Tokyo Hard Fork phase (guide Step 4) works the same way: your team
  overwrites this same `config.yaml` in place with the new phase's
  content and commits it — there is no separate per-phase file/directory.
  `beacon`/`validator` have this directory bind-mounted directly as
  `--testnet-dir`, so a `git pull` + `jocv restart` is enough to pick it
  up, no copy step needed.
- `cl/genesis.ssz` — optional precomputed consensus genesis state. Not
  referenced by any explicit flag: Lighthouse's `--testnet-dir` auto-loads
  `genesis.ssz` from that directory if present, and since
  `lighthouse-vc-only.yml`/`lighthouse-cl-only.yml` bind-mount the whole
  `networks/<NETWORK>/cl/` directory as the testnet-dir, dropping the file
  in here is enough — no code changes needed.
- `el/genesis.json`, `el/bootnodes.txt`, `cl/bootnodes.txt` — **only
  needed if you run your own Execution/Consensus Client** (`ROLE=el-cl` or
  `ROLE=all`, i.e. the guide's Option 3). **The official guide does not
  document Option 3** — it explicitly says "Organizations selecting
  Option 3 should contact us directly." So there is no guide text to copy
  these from; get them directly from JBF/admin, and treat anything this
  repo assumes about their format (see root README) as unverified until
  you confirm it against what JBF/admin actually provides.

## Bootnode file format

Plain text, one entry per line, blank lines and `#` comments ignored —
not real YAML. This is deliberate: `jocv` is bash-only with no YAML
parser dependency (per this project's low-dependency goal), so keeping
these as flat lists avoids needing one.

```
# networks/mainnet/el/bootnodes.txt
enode://<pubkey>@<ip>:<port>
enode://<pubkey>@<ip>:<port>
```
