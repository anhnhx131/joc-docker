# networks/

One directory per JOC network:

```
networks/
├── mainnet/
│   └── cl/
│       ├── config.yaml               # currently-applied consensus config
│       ├── deposit_contract_block.txt
│       └── genesis.ssz               # optional: precomputed genesis state
├── testnet/    (same layout)
└── sandbox/    (same layout)
```

`jocd` picks which of these to use based on `NETWORK` in `.env`
(`mainnet` | `testnet` | `sandbox`).

## What goes here and from where

These are **public network parameters, not secrets** (chain ID, genesis,
fork epochs) — safe to commit to git, unlike `data/` or `.env`.

- `cl/config.yaml`, `cl/deposit_contract_block.txt` — per the guide, Step
  2-1: download from the JOC page
  (https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/)
  or receive from JBF/admin, and place here (or commit them here so
  validators get them via `git pull` — see `CLAUDE.md`'s
  ["Updating config via git"](../CLAUDE.md#updating-config-via-git)).
  A new Tokyo Hard Fork phase (guide Step 4) works the same way: your team
  overwrites this same `config.yaml` in place with the new phase's
  content and commits it — there is no separate per-phase file/directory.
  `validator` has this directory bind-mounted directly as `--testnet-dir`,
  so a `git pull` + `jocd restart` is enough to pick it up, no copy step
  needed.
- `cl/genesis.ssz` — optional precomputed consensus genesis state. Not
  referenced by any explicit flag: Lighthouse's `--testnet-dir` auto-loads
  `genesis.ssz` from that directory if present, and since
  `lighthouse-vc-only.yml` bind-mounts the whole `networks/<NETWORK>/cl/`
  directory as the testnet-dir, dropping the file in here is enough — no
  code changes needed.

## Not currently supported: `el/`, bootnodes

Self-hosting your own Execution + Consensus Client (guide Option 3, which
the official guide itself doesn't document — "Organizations selecting
Option 3 should contact us directly") used to have a matching `el/`
subdirectory here (`genesis.json`, `bootnodes.txt`) plus a `cl/bootnodes.txt`,
for `ROLE=el-cl`/`all`. Removed along with that role — see `CLAUDE.md`'s
Self-review. `ROLE=validator`'s Validator Client only talks HTTP to an
external Consensus Client (BCCloud), so it needs neither.
