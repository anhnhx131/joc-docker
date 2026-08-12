# joc-docker (`jocv`)

A small bash-only CLI for running a **JOC (Japan Open Chain)** node — as a
validator, a plain network-connected node, or both — on infrastructure you
control, as opposed to the parts done through the BCCloud web UI.

> **Just want to try it on a real EC2 box?** See
> [GETTING-STARTED.md](GETTING-STARTED.md) for a hands-on, copy-pasteable
> walkthrough (launch instance → install Docker → `jocv init` → what each
> prompt looks like → BCCloud steps → verify). This README is the
> reference doc (architecture, guide fidelity, security model).

Its foundation (`ROLE=validator`) is a thin wrapper around the official
*"JOC Tokyo Hard Fork Validator Step-by-Step Guide"*, Option 2 (Recommended
Configuration): every command it runs there is either taken **verbatim**
from the guide, or a direct, literal translation of a guide command into
`docker compose` — see [Verify this yourself](#verify-this-yourself) and
[Self-review](#self-review--what-i-added-beyond-the-guide).

Everything needed to also run your own Execution + Consensus client
(`ROLE=el-cl` / `all`) is **new territory the guide does not document** —
it explicitly says *"Organizations selecting Option 3 should contact us
directly."* That part is flagged loudly throughout this README and the
code; treat it as unverified until confirmed with JBF/admin.

## Three axes of configuration

`jocv` is built around three independent choices, all set once in `.env`
(`jocv init` walks you through them):

| Axis | Values | What it controls |
| --- | --- | --- |
| `ROLE` | `validator` \| `el-cl` \| `all` | Which service(s) run: only the Validator Client (connects to an external Consensus Client, e.g. BCCloud); only Execution+Consensus (a plain node, no validator duties); or all three, self-hosted. |
| `NETWORK` | `mainnet` \| `testnet` \| `sandbox` | Which JOC network's config/genesis/bootnodes to use — see `networks/<NETWORK>/{el,cl}/` and [networks/README.md](networks/README.md). |
| `EL_CLIENT` / `CL_CLIENT` | `geth` / `lighthouse` (only options today) | Which client runs each layer. Structured so `nethermind`, `besu`, `prysm`, etc. can be added later without changing this shape — but only `geth`+`lighthouse` are implemented right now; any other value is rejected with a clear "not supported yet" error (`jocv`: `SUPPORTED_EL_CLIENTS` / `SUPPORTED_CL_CLIENTS`). |

`ROLE` maps to which compose file(s) get loaded, via `COMPOSE_FILE` in
`.env` (docker compose reads this natively — one small compose file per
client/role, [eth-docker](https://github.com/ethstaker/eth-docker)'s
convention, e.g. its
[`lighthouse-vc-only.yml`](https://github.com/ethstaker/eth-docker/blob/main/lighthouse-vc-only.yml)):

| `ROLE` | `COMPOSE_FILE` | Services started | Guide option |
| --- | --- | --- | --- |
| `validator` | `lighthouse-vc-only.yml` | `validator` only | Option 2 (Recommended) — what the guide's Step 2 documents |
| `el-cl` | `geth.yml:lighthouse-cl-only.yml` | `execution` + `beacon` | Undocumented in the guide (closest to Option 3, minus the validator) |
| `all` | `geth.yml:lighthouse-cl-only.yml:lighthouse-vc-only.yml` | `execution` + `beacon` + `validator` | Option 3 — guide says "contact us directly" |

A service you're not using is never even parsed by docker compose — its
file just isn't in `COMPOSE_FILE`. This was previously done with a single
`docker-compose.yml` and [docker compose
profiles](https://docs.docker.com/compose/how-tos/profiles/) instead;
switched to match eth-docker's approach once client choice (`EL_CLIENT`/
`CL_CLIENT`) becomes real (multiple files per layer composes more cleanly
than one file with more and more profile combinations).

## What this is NOT

This CLI does **not** touch BCCloud. The following steps from the guide are
manual, UI-driven steps on [BCCloud](https://app.bccloud.net/) and are out
of scope on purpose:

| Guide step | What you do (manually, on BCCloud) |
| --- | --- |
| Step 1-1, 1-2 | Obtain your receiver withdrawal address from JBF/admin, join the JOC PoSA network |
| Step 2-3 | Create a Transaction Cluster (2 relay nodes, Tokyo region) |
| Step 2-4 | Create a Validator Cluster, add an **External Validator** node, register the `pubkey` from `deposit_data-xxx.json` |
| Step 2-5 | Open the Consensus HTTP API on that node, restricted to your Validator Server's IP |
| Step 3-1 | Upload `deposit_data-xxx.json` to Launchpad |
| Step 3-3 | Stop the old txNode (coordinate with JBF) |
| Step 5 | Shut down the old Geth/Clef environment, retrieve JOC linked to Clef |

These only apply to `ROLE=validator`/`all` (you need BCCloud's Consensus
HTTP API only when your Validator Client talks to a Consensus Client it
doesn't run itself). `ROLE=el-cl` doesn't involve BCCloud or Launchpad at
all — it's just a node joining the network.

If your organization uses the guide's **Option 1 (Internal Validator)** —
Execution, Consensus, *and* Validator Client all run on BCCloud — this CLI
does not apply to you at all. Follow "Option 1: Setup for Internal
Validators" in the guide directly; there is nothing to run on your own
machine.

### Compared to eth-docker's `ethd`

If you've used [eth-docker](https://github.com/ethstaker/eth-docker)'s
`ethd install|config|up|update`, `jocv` follows the same rough shape but
much smaller — no OS provisioning, no `.env` schema migration engine, and
(for now) exactly one client per layer:

| `ethd` | `jocv` equivalent | Why it's smaller here |
| --- | --- | --- |
| `install` (installs Docker, OS packages, tunes the OS, adds user to `docker` group) | `jocv install` | Installs Docker Engine + compose plugin only (official apt repo on Ubuntu/Debian, best-effort dnf repo elsewhere), and adds your user to the `docker` group. Deliberately does **not** tune the OS (swappiness, noatime, chrony/NTP) or install unrelated packages — a tool that's about to handle your mnemonic shouldn't also be doing broad root-level OS provisioning. Shows every `sudo` command before running it and asks for confirmation once. Idempotent: no-ops if Docker is already installed and working. |
| One `.yml` file per client (e.g. `lighthouse-vc-only.yml`), merged via `COMPOSE_FILE` | Same — `lighthouse-vc-only.yml`, `geth.yml`, `lighthouse-cl-only.yml`, merged via `COMPOSE_FILE` per `ROLE` | This one isn't simplified, just scoped down: eth-docker has ~5 EL × ~6 CL × addons; `jocv` has exactly the files today's `SUPPORTED_EL_CLIENTS`/`SUPPORTED_CL_CLIENTS` need. |
| `config` (interactive `.env` wizard + schema migration across versions) | `jocv init` prompts (network/role) + `jocv beacon set <url>` | A handful of variables, not dozens — no schema to migrate. |
| `up` | `jocv up` | Same idea: `docker compose up -d`, respecting `COMPOSE_FILE`. |
| `down` / `stop` | `jocv down` | Same idea, with a guide-specific reminder not to stop while awaiting activation (Step 3-2). |
| `logs` | `jocv logs [service]` | Same idea: `docker compose logs -f`. Asks which service if more than one is active. |
| `update` (`git pull`, `.env` migration, image rebuild, restart, all in one) | `jocv update` | Only does the `git pull` part, and only if the working tree is clean and the pull is a fast-forward. Never migrates `.env`, never restarts anything, never applies a new config by itself — it just tells you what changed and which command to run next. |

## Prerequisites

- A Linux/macOS machine you control (any infra — EC2, on-prem, a VPS,
  whatever you have) that can run stably and stay online.
- [Docker](https://docs.docker.com/engine/install/) installed, daemon
  running, with the `docker compose` v2 plugin available — run
  `jocv install` if you don't have it yet (Ubuntu/Debian and, best-effort,
  Amazon Linux/RHEL-family).
- `bash`, `openssl`, `sed`, `paste` (all standard on any Linux/macOS box —
  no `yq`/Python/Node dependency, by design).
- For `ROLE=validator`/`all`: you've completed guide Step 1-1 (receiver
  withdrawal address) and Step 1-2 (joined the JOC PoSA network on
  BCCloud), plus a private, offline-capable way to record a mnemonic
  phrase — see [Security](#security).
- For `ROLE=el-cl`/`all`: `networks/<NETWORK>/el/genesis.json` in place,
  and a confirmed Geth image + network ID + bootnodes from JBF/admin (see
  [Option 3 caveat](#option-3-caveat-el-cl-roles) below) — there is no
  guide to copy these from.

## Quick start

### Just a validator (guide Option 2 — most validator companies want this)

```bash
./jocv install       # if Docker isn't installed yet (safe to skip if it is)
./jocv init          # prompts: NETWORK=mainnet, ROLE=validator, then guide
                      # Step 2-1, 2-2, 2-6, 2-7, 2-8

# --- meanwhile, on BCCloud (manual, see table above): -----------------
#   Step 2-3: create the Transaction Cluster
#   Step 2-4: create the Validator Cluster + External Validator node,
#             registering the pubkey from deposit_data-xxx.json
#   Step 2-5: open the Consensus HTTP API to your Validator Server's IP,
#             and note the BCCloud node's IP address
# ------------------------------------------------------------------------

./jocv beacon set http://<bccloud-validator-node-ip>:3500
./jocv status         # guide Step 3-2
```

After that, submit `data/validator_keys/deposit_data-xxx.json` to
Launchpad (guide Step 3-1) — `jocv init` prints its exact path at the end.

### Just a node, no validator duties

```bash
NETWORK=mainnet ROLE=el-cl ./jocv init
./jocv logs execution   # or: ./jocv logs beacon
./jocv status
```

### Both (guide Option 3 — self-hosted end to end)

```bash
NETWORK=mainnet ROLE=all ./jocv init
./jocv status
```

## Commands

### `jocv install`

Installs Docker Engine + the compose plugin if they're not already
present (no-ops otherwise). Official apt repo steps on Ubuntu/Debian;
best-effort dnf repo steps on Amazon Linux/RHEL-family. Shows every `sudo`
command up front and asks for confirmation once before running any of
them. Also adds your user to the `docker` group (requires a new login
session, or `newgrp docker`, to take effect). Does not touch anything
under `validator_keys/`, and doesn't tune the OS or install anything
beyond Docker itself — see [Compared to eth-docker's `ethd`](#compared-to-eth-dockers-ethd).

### `jocv init`

Prompts for `NETWORK` and `ROLE` (or reads them from the environment /
existing `.env`), then runs whichever of the following apply:

**Always:**
1. Checks Docker is installed and running.
2. For `validator`/`all`: creates `data/validator_keys/`. For `el-cl`/`all`:
   creates `data/execution/`, `data/beacon/`.
3. Checks `networks/<NETWORK>/cl/{config.yaml,deposit_contract_block.txt}`
   exist (see [networks/README.md](networks/README.md) — manual download
   or git-committed by your team), prints their SHA-256.

**`el-cl` / `all` only** (see [Option 3 caveat](#option-3-caveat-el-cl-roles)):
4. Checks `networks/<NETWORK>/el/genesis.json` exists.
5. Prompts for `EL_CLIENT_IMAGE` and `EL_NETWORK_ID` if not already set.
6. Reads `networks/<NETWORK>/{el,cl}/bootnodes.txt` into `EL_BOOTNODES` /
   `CL_BOOTNODES`.
7. Generates `data/jwt.hex` (execution↔consensus shared secret), `chmod 600`.
8. Runs `geth init` against the genesis file once (skipped if already done).

**`validator` / `all` only** (guide Step 2-2, 2-6):
9. Prompts for your withdrawal address, validated as `0x` + 40 hex chars.
10. Delegates to [`staking-deposit-cli.yml`](#staking-deposit-cliyml) — a separate,
    standalone compose file — to actually generate and import the key via
    `docker compose -f staking-deposit-cli.yml run --rm <service>`. `jocv init`
    never runs an `ethstaker-deposit-cli`/`lighthouse` docker command
    itself, and never touches the mnemonic; see
    `staking-deposit-cli/*-entrypoint.sh` for what happens step by step
    (password, mnemonic, the guide's two verbatim commands, the mandatory
    typed `yes` confirmation, then the Step 2-6 Lighthouse import).

**Always, at the end:**
16. Writes/updates `.env` (`NETWORK`, `ROLE`, `COMPOSE_FILE`, client
    choices, and whatever the role above collected).
17. Runs `docker compose up -d`.
18. For `validator`/`all`: prints the `deposit_data-xxx.json` path (needed
    for Step 3-1) and a loud confidentiality reminder. For `el-cl`/`all`:
    reminds you the Execution/Consensus wiring is unverified — check sync
    status before trusting the node.

Idempotent throughout: existing keys/config/`.env` are reused rather than
silently overwritten; you're asked before anything that isn't purely
additive.

**Changing `NETWORK` or `ROLE` after `init`:** not supported by this CLI.
Deposit data is submitted against a specific network's deposit contract,
and the withdrawal address you provide is issued per-network by JBF/admin
— reusing the same keys across networks isn't meaningful. Start a fresh
checkout for a different network or role combination.

### `staking-deposit-cli.yml`

A separate, standalone compose file (not part of `COMPOSE_FILE`, never
started by a plain `docker compose up`) that does the actual guide
Step 2-2 / 2-6 work, run one-off via:

```
docker compose -f staking-deposit-cli.yml run --rm deposit-generate
docker compose -f staking-deposit-cli.yml run --rm validator-import
```

Each service's container-side logic — password, mnemonic, the mandatory
typed `yes` confirmation, the guide's verbatim commands, chown-ing the
result back to your user — lives in its own script under
[`staking-deposit-cli/`](#staking-deposit-cli), bind-mounted read-only into the stock
`gulabs/gu-ethstaker-deposit-cli` / `sigp/lighthouse` images. Neither
image is ever rebuilt: what runs is exactly what JBF/admin published.

`jocv init` calls both services for you automatically for
`ROLE=validator`/`all` — most people never invoke this directly. It's kept
as its own compose file + entrypoint scripts, deliberately outside `jocv`,
for two reasons:

- It's the part of this project most likely to need independent tweaking
  (image version/tag, extra flags, a future non-Lighthouse import command)
  — changing it never requires touching `jocv`'s larger lifecycle logic
  (`install`/`up`/`down`/`logs`/`update`), and vice versa.
- It's the single most security-sensitive part of the whole project
  (mnemonic handling). Small, single-purpose files are easier to read
  start-to-finish and diff against the guide than a block buried inside a
  1000+ line CLI. `jocv` itself never sees the mnemonic — it only invokes
  `docker compose run`, the container does everything else.

`deposit-generate` never submits anything to any network — it only prints
the resulting `deposit_data-*.json` path and contents at the end so
**you** copy/submit it yourself (guide Step 3-1). `validator-import` hands
the keystore to a local Lighthouse container; also local-only. Both
services run with `network_mode: none` — no network access is available
to either container, not just discouraged. Copy `staking-deposit-cli.yml` plus
`staking-deposit-cli/` anywhere with Docker installed to run this standalone,
e.g. to generate keys on a separate/offline machine from the one running
the Validator Client.

#### `staking-deposit-cli/`

- `generate-entrypoint.sh` — overrides `gulabs/gu-ethstaker-deposit-cli`'s
  entrypoint. Guide Step 2-2's two verbatim subcommands
  (`generate-mnemonic`, `existing-mnemonic`), invoked directly since this
  script now runs as the container's own entrypoint (see the file's
  `BEGIN/END: verbatim from guide` markers to diff against the guide
  text). Same mnemonic-handling discipline as before it was containerized:
  never written to disk, `set +o history` around it, `unset` on every
  exit path, `clear` afterward.
- `import-entrypoint.sh` — overrides `sigp/lighthouse`'s entrypoint. Guide
  Step 2-6's `lighthouse account_manager validator import`, adapted only
  for where the consensus config volume is mounted (see the file's
  `BEGIN/END: adapted from guide` marker). This is the guide's offline,
  pre-startup import — not the same mechanism as eth-docker's own
  Keymanager-API-based `validator-keys import` (see
  [Checked against eth-docker's import](#checked-against-eth-dockers-import)
  below for why).

Both scripts default `HOST_UID`/`HOST_GID` to `0:0` (root — these
containers have no unprivileged user to drop into, unlike eth-docker's
rebuilt image) and `chown` the files they produce back to whatever
`HOST_UID`/`HOST_GID` `jocv` passes in (your actual host user), so you're
not left with root-owned key material on native Linux hosts.

#### Checked against eth-docker's import

eth-docker's key import ([`vc-utils/keymanager.sh`](https://github.com/ethstaker/eth-docker/blob/main/vc-utils/keymanager.sh),
driven by `ethd keys import`) works completely differently from this project's:
it calls the validator client's Keymanager REST API on an **already
running** container to hot-load keys, works uniformly across every client
eth-docker supports, and returns slashing-protection data over that API.
That mechanism is not documented anywhere in the JOC guide, and adopting
it would mean enabling a Keymanager HTTP API on the Validator Client that
this project doesn't currently expose — outside this project's
guide-fidelity rule (see `CLAUDE.md`). `import-entrypoint.sh` stays on the
guide's own Step 2-6 command: an **offline** `lighthouse account_manager
validator import` straight into the datadir, before the Validator Client
ever starts. What *did* get adopted from eth-docker here is the
structural pattern — a dedicated "tools"-profile compose service plus its
own entrypoint script, instead of a raw `docker run` in a host script —
and the chown-back-to-host-user convention described above.

### `jocv config`

For an already-initialized node: view current `WITHDRAWAL_ADDRESS` /
`BEACON_URL`, optionally change them, then offers to apply via
`docker compose up -d`. Doesn't touch keys, `NETWORK`, or `ROLE` — those
are fixed at `jocv init` time (see above). For `ROLE=el-cl` it just prints
current values and tells you to edit `.env` directly for
execution/consensus settings (not covered by this command yet). For
`ROLE=all`, `BEACON_URL` is skipped here since it's auto-managed — use
`jocv beacon set` if you specifically need to override it.

### `jocv beacon set <url>`

Only for `ROLE=validator` (points the Validator Client at an external
Consensus Client — BCCloud in guide Step 2-7, or a new endpoint for a
Step 4 hard fork change). For `ROLE=all` it warns first (you're normally
pointed at your own local `beacon` service automatically) and asks you to
confirm before overriding. For `ROLE=el-cl` it refuses (no Validator
Client runs in that role).

### `jocv status`

Checks whichever container(s) the current `ROLE` needs are running, prints
recent logs for each. For the `validator` container specifically, scans
for `Not attesting` per the guide's Step 3-2 criteria (persisting 15-20+
minutes after the first 5-10 minutes is a sign something's wrong). The
`execution`/`beacon` checks are this project's own addition — the guide
doesn't cover self-hosting them.

### `jocv update-config <phase>`

For guide Step 4 (applying a new Tokyo Hard Fork phase), against
`networks/<NETWORK>/cl/`. Looks for a config in this order:

1. `networks/<NETWORK>/cl/phases/<phase>/config.yaml` — a phase-specific
   file (see [Updating config via git](#updating-config-via-git)).
2. `networks/<NETWORK>/cl/config.yaml` — generic fallback.

Backs up the previous config, copies the new one in place (the
`beacon`/`validator` containers have `networks/<NETWORK>/cl` bind-mounted
directly as `--testnet-dir`, so no separate copy step into `data/` is
needed), prints its SHA-256 checksum, and — after you explicitly confirm
both that JBF/admin announced this phase **and** that you've verified the
config against the official source — restarts whichever containers read
it (`validator` for `ROLE=validator`, `beacon` for `ROLE=el-cl`, both for
`ROLE=all`).

**Only run this after an official announcement from JBF/admin.** It never
runs `git pull` or downloads anything by itself.

### Updating config via git

If your team commits the official `config.yaml` into this repo (instead
of every validator server downloading it manually each time from the JOC
page), the update flow for a new hard fork phase becomes:

1. **Team/maintainer:** get the official config for the new phase, commit
   it at `networks/<NETWORK>/cl/phases/<phase>/config.yaml`, push (and
   tag, if you want an easy `git checkout` target per phase).
2. **On each node:**
   ```bash
   git pull
   ./jocv update-config <phase>
   ```
`jocv` will find the file your team committed, show its checksum, and
still requires you to confirm it's correct before applying — see
[networks/README.md](networks/README.md) for the full rationale
(`config.yaml` controls consensus rules, so this step is deliberately
never fully automated).

### `jocv update`

Updates this CLI checkout itself via `git pull` — the code, and any
`networks/` files your team commits (see above). Refuses to run if:
- this directory isn't a git checkout,
- the working tree has uncommitted changes, or
- the pull wouldn't be a fast-forward (i.e. your local branch diverged).

Shows the incoming commits and asks for confirmation before pulling.
Afterward it tells you — but does not act on — whether any root-level
`*.yml` compose file, `networks/*/cl/phases/**`, or `networks/*/el/**`
changed, so you follow up deliberately with `jocv up` /
`jocv update-config <phase>` / a fresh `jocv init` respectively.

### `jocv up` / `jocv down` / `jocv logs [service]`

Thin wrappers around `docker compose up -d` / `down` / `logs -f`, scoped
to whichever service(s) `ROLE` activates. `down` reminds you not to stop
while awaiting activation (Step 3-2) if a validator is running. `logs`
asks you to name a service if more than one is active
(`execution`/`beacon`/`validator`).

### `jocv reset [--data]`

For starting over. Two tiers:

- `jocv reset` — `docker compose down --remove-orphans`. Leaves `data/`
  and `.env` untouched; bring the node back with `jocv up` (or `jocv init`
  if `.env` is gone). This is what `jocv init` points you to when it
  refuses to overwrite an existing, non-empty `data/validator_keys/`.
- `jocv reset --data` — also **permanently deletes** `data/` (keys,
  deposit data, execution/consensus chain data) and `.env`. Prints exactly
  what will be removed, asks you to confirm the deposit is decommissioned
  or was never submitted, then requires typing `delete` verbatim (a plain
  `y` isn't enough) before touching anything. No backup is made —
  `networks/` (public config) is untouched, but everything under `data/`
  is gone for good. Only run this if you're certain you don't need this
  validator's keys anymore.

## Option 3 caveat (`el-cl`/`all` roles)

The official guide's Step 2 only documents `ROLE=validator` (Option 2).
For `el-cl`/`all`, the guide's only words on the matter are: *"Organizations
selecting Option 3 should contact us directly."* That means, unlike
everything else in this CLI, the `execution` and `beacon` services
(`geth.yml`, `lighthouse-cl-only.yml`) and the corresponding `jocv init`
steps are **this project's own best-effort convention**, based on
ordinary Geth/Lighthouse usage — not copied from any JOC/JBF source:

- The Geth image/version (`EL_CLIENT_IMAGE`) and network ID
  (`EL_NETWORK_ID`) have **no default** — you must get these from
  JBF/admin. `jocv` will refuse to start these services without them
  rather than guess.
- `networks/<NETWORK>/el/genesis.json` and the `bootnodes.txt` files must
  come from JBF/admin too; there is no guide text describing their exact
  format for JOC specifically (see [networks/README.md](networks/README.md)
  for the plain-text convention `jocv` expects).
- The execution↔consensus JWT auth, ports, and flags
  (`--authrpc.*`, `--execution-endpoint`, `--http.api`, etc.) follow
  standard Geth/Lighthouse conventions, which is a reasonable default for
  *some* Ethereum-family chain, but has not been confirmed against JOC's
  actual requirements.

**Before relying on `ROLE=el-cl`/`all` for anything real: verify every one
of these with JBF/admin.** `ROLE=validator` remains the fully
guide-verified path.

## Security

- The mnemonic is **never** written to a file, logged, or sent over the
  network — it lives only in a shell variable, inside
  `staking-deposit-cli/generate-entrypoint.sh`, running inside the
  `deposit-generate` container, for the few seconds between the two
  `ethstaker-deposit-cli` calls, and is `unset` immediately after. `jocv`
  itself never sees it — it only runs `docker compose -f staking-deposit-cli.yml
  run --rm deposit-generate`.
- `set -x` is never used anywhere near `MNEMONIC` or `password.txt`.
- Both `staking-deposit-cli.yml` services run with `network_mode: none` — network
  access is unavailable to the container, not just unused.
- Every file under `validator_keys/` is `chmod 600`; `data/jwt.hex`
  (execution↔consensus shared secret) likewise.
- `data/` and `.env` are git-ignored — never commit them.
- `networks/**` (`genesis.json`, `config.yaml`, `deposit_contract_block.txt`,
  `bootnodes.txt`) is **not** git-ignored on purpose — these are public
  network parameters, not secrets, and this repo supports committing them
  so nodes can pick up updates with `git pull` (see
  [Updating config via git](#updating-config-via-git)). Never confuse this
  directory with `data/validator_keys/` — nothing under `networks/` should
  ever contain a mnemonic, keystore, or password.
- Key generation/import (`staking-deposit-cli.yml`) calls the exact docker images
  JBF/admin published in the guide
  (`gulabs/gu-ethstaker-deposit-cli:v0.0.1-gubuild.0`,
  `sigp/lighthouse:v7.0.1`) directly, unmodified — the entrypoint scripts
  are bind-mounted in at runtime, never baked into a rebuilt image. No
  intermediate image or script touches your key material — this is
  intentional, so you can diff every command this CLI runs against the
  guide's own text and trust that nothing "extra" is happening. (This
  guarantee does **not** extend to the `execution`/`beacon` services — see
  [Option 3 caveat](#option-3-caveat-el-cl-roles).)
- Neither `deposit-generate` nor `validator-import` ever submits anything
  to any network — both only run local commands against your own disk
  (and, per `network_mode: none` above, could not reach a network even if
  they tried). Submitting `deposit_data-*.json` (guide Step 3-1) is a
  manual step you do yourself, on purpose — this repo doesn't automate it.

### Verify this yourself

Please don't run this blind. Before trusting it with a real mnemonic:

1. **Read the code.** The CLI proper is one file, `jocv`. Key
   generation/import is `staking-deposit-cli.yml` plus
   `staking-deposit-cli/generate-entrypoint.sh` / `import-entrypoint.sh` — read
   those specifically before trusting them
   with a real mnemonic. The verbatim/adapted command blocks are marked
   `# --- BEGIN/END: verbatim|adapted from guide, Step 2-2/2-6 ---` so you
   can diff them directly against the original guide.
2. **No network access needed, and none available.** The guide's own
   command already uses `--ignore_connectivity`, which tells the deposit
   CLI not to check chain connectivity. `staking-deposit-cli.yml` sets
   `network_mode: none` on both services, so this isn't just a claim you
   have to verify yourself anymore — the container has no network to send
   anything over even if it wanted to. You can still confirm it
   independently: `docker network inspect none` while a `deposit-generate`
   run is in progress will show no container attached to any bridge.
3. **Run this on a disk-encrypted machine.** Prefer local console access;
   avoid SSH sessions that log the terminal session (e.g. `script`,
   session-recording bastions, some corporate SSH proxies) while the
   mnemonic is on screen.
4. Never paste the mnemonic anywhere else — not Slack, not a ticket, not
   an AI assistant.

## Self-review — what I added beyond the guide

Everything marked "verbatim" is copy-pasted from the guide text for
`ROLE=validator` on `mainnet`. Everything else below was necessarily
inferred/adapted or added — flagging it explicitly so you can double-check:

- **Multi-role (`ROLE=validator`/`el-cl`/`all`) via docker compose
  profiles.** Not from the guide, which only documents Option 2
  (`validator`-equivalent). `el-cl`/`all` correspond to the guide's Option
  3, which is explicitly undocumented there ("contact us directly") — see
  [Option 3 caveat](#option-3-caveat-el-cl-roles) for the full list of
  what's unverified in that path.
- **Multi-network (`networks/<NETWORK>/{el,cl}/`).** The guide is written
  entirely in terms of one network (mainnet). Extended so `NETWORK=testnet`
  /`sandbox` select their own config/genesis/bootnodes directory, on the
  assumption (not stated in the guide) that these networks follow the same
  file layout as mainnet.
- **`lighthouse-vc-only.yml` command as a YAML list, not a shell string**,
  for the `validator` service. The guide's Step 2-7 `docker run` block is
  missing a trailing `\` line-continuation on one line; expressing it as a
  YAML list sidesteps that ambiguity entirely while keeping the same flags.
- **One compose file per client (`lighthouse-vc-only.yml`, `geth.yml`,
  `lighthouse-cl-only.yml`), merged via `COMPOSE_FILE`, instead of one
  `docker-compose.yml` filtered by `profiles:`.** Not from the guide —
  adopted from
  [eth-docker](https://github.com/ethstaker/eth-docker/blob/main/lighthouse-vc-only.yml)'s
  convention. Functionally similar to `profiles:` today (exactly one file
  per role gets loaded either way), but scales better once `EL_CLIENT`/
  `CL_CLIENT` support more than one option each, and means a service
  you're not using is never parsed at all (no more empty-fallback
  workarounds for required variables like `EL_CLIENT_IMAGE`).
- **`execution`/`beacon` services entirely.** See
  [Option 3 caveat](#option-3-caveat-el-cl-roles) — not from the guide at
  all, best-effort Geth/Lighthouse convention.
- **Client allow-lists (`EL_CLIENT`/`CL_CLIENT`)** with only `geth`/
  `lighthouse` implemented today. Structured so `nethermind`, `besu`,
  `prysm` etc. can be added later; any other value is rejected rather than
  silently accepted.
- **Plain-text `bootnodes.txt` instead of real YAML**, despite the `.yaml`
  naming some teams may expect. Deliberate: this project stays
  bash-only/no extra dependencies, and a real YAML parser (e.g. `yq`)
  would be a new dependency just for a list of strings.
- **`BEACON_URL` default placeholder (`http://127.0.0.1:5052`).** Not from
  the guide — a deliberately inert default so `docker compose up -d` can
  succeed without pointing at anything real. For `ROLE=all` it's instead
  auto-set to the local `beacon` service.
- **A second `-v` mount in the Step 2-6 import command** so
  `--testnet-dir=/data/config` still resolves now that consensus config
  lives under `networks/<NETWORK>/cl` instead of `data/config`. Same
  flags/values as the guide otherwise.
- **Key generation/import split into a standalone `staking-deposit-cli.yml`
  compose file + `staking-deposit-cli/*.sh`**, called by `jocv init`
  via `docker compose run` rather than inlined in `jocv` itself. Not from
  the guide — a deliberate architecture choice so the most
  security-sensitive, most likely-to-change part of this project (image
  version, extra flags, a future non-Lighthouse import command) never
  requires touching `jocv`'s larger lifecycle logic, and can be
  read/audited/run standalone. Originally a single bash script that ran
  `docker run` itself; restructured into a compose file + bind-mounted
  entrypoint scripts, modeled on eth-docker's
  `staking-deposit-cli.yml`/`docker-entrypoint.sh` convention, so `jocv` never
  runs a raw `docker run`/`docker` command and never touches the mnemonic
  at all — it only invokes `docker compose run`. See
  [`staking-deposit-cli.yml`](#staking-deposit-cliyml) above, including
  [why this doesn't reuse eth-docker's Keymanager-API import](#checked-against-eth-dockers-import).
- **`network_mode: none` on both `staking-deposit-cli.yml` services.** Not from
  the guide. The guide's own `--ignore_connectivity` flag already implies
  the tool needs no network; this makes that a hard guarantee instead of
  an assumption. README's "Verify this yourself" used to ask you to test
  this manually with `--network none` — now it's simply always true.
- **`HOST_UID`/`HOST_GID` chown-back in both entrypoint scripts**,
  defaulting to `0:0`. Adapted from eth-docker's
  `ethstaker-deposit-cli/docker-entrypoint.sh`, which does the same thing
  via `gosu` + `chown`. Not from the guide — needed because these
  containers run as root by default (no unprivileged user to drop into,
  unlike eth-docker's rebuilt image) and would otherwise leave root-owned
  key material behind on native Linux hosts.
- **Idempotency guards** (skip key generation if keys already exist; ask
  before overwriting non-empty directories or an existing `.env`). The
  guide is written as a one-time walkthrough and doesn't address re-runs.
- **`docker compose restart <service>` instead of the guide's `sudo docker
  restart validator`** (Step 4-1). Same effect, works with how this CLI
  manages containers via compose.
- **`.gitignore` excluding `data/` and `.env`.** A necessary consequence
  of the guide's own confidentiality requirement for the mnemonic/keystore/
  password.
- **Random password generation** (`openssl rand -base64 24`) and **JWT
  secret generation** (`openssl rand -hex 32`). The guide specifies the
  password must be >12 characters but not a method; `openssl rand` is a
  standard way to satisfy that. The JWT secret isn't mentioned in the
  guide at all (only relevant to the undocumented `el-cl`/`all` roles).
- **Git-backed config distribution** (`networks/*/cl/phases/<phase>/`,
  `git pull` workflow, checksum + confirm before applying). Entirely
  outside the guide, which only describes manual downloads. Deliberately
  still requires an explicit human "verify against the official source"
  confirmation before `jocv update-config` applies anything, and `jocv`
  never runs `git pull` or fetches configs over the network on its own.
- **`jocv install`.** The guide only says "ensure Docker is set up" and
  links Docker's own install guide — it doesn't specify a method. This
  command follows Docker's official documented steps (apt repo for
  Ubuntu/Debian; best-effort dnf repo elsewhere) rather than the
  `curl | sh` convenience script, so every command is visible and
  confirmed before running. Scoped to Docker only — no OS tuning, no
  unrelated packages, unlike `ethd install`.

- **Single-file `jocv`** instead of `scripts/*.sh` + `lib.sh`. Purely
  organizational — same logic, same verbatim-block markers, just one file
  with one `cmd_<name>()` function per subcommand instead of one process
  per file. Not from the guide or from eth-docker's exact layout, but
  deliberately modeled on `ethd`'s single-file shape.

No multi-validator support, no notifications, no client beyond
`geth`+`lighthouse` — nothing was added beyond what was asked for.

## Repository layout

```
joc-docker/
├── jocv                       # the whole CLI — one file, ~1100 lines:
│                              #   1. paths + SUPPORTED_* allow-lists
│                              #   2. helpers (logging, confirm(), validators,
│                              #      env/network utilities, check_el_config())
│                              #   3. one cmd_<name>() function per subcommand
│                              #      (install, init, config, beacon_set, status,
│                              #      update_config, update, up, down, reset, logs)
│                              #   4. usage() + dispatch (case "$1") at the bottom
├── staking-deposit-cli.yml             # standalone key ceremony compose file (Step 2-2, 2-6)
│                              #   deposit-generate: mnemonic + keystore + deposit data
│                              #   validator-import: hands keystore to a local Lighthouse
│                              # called by 'jocv init', but runnable on its own
├── staking-deposit-cli/
│   ├── generate-entrypoint.sh  # overrides gu-ethstaker-deposit-cli's entrypoint
│   └── import-entrypoint.sh    # overrides sigp/lighthouse's entrypoint
├── lighthouse-vc-only.yml     # 'validator' service — guide-verbatim (Step 2-7)
├── geth.yml                    # 'execution' service — el-cl/all only, unverified (Option 3 caveat)
├── lighthouse-cl-only.yml       # 'beacon' service — el-cl/all only, unverified (Option 3 caveat)
├── .env.example                 # sets COMPOSE_FILE per ROLE — see compose_files_for_role()
└── networks/
    ├── README.md
    └── {mainnet,testnet,sandbox}/
        ├── el/                        # genesis.json, bootnodes.txt (el-cl/all roles only)
        └── cl/
            ├── config.yaml / deposit_contract_block.txt / bootnodes.txt
            └── phases/<phase>/config.yaml   # per hard-fork-phase configs (Step 4)
```

Why one file instead of `scripts/*.sh`: bash `source` doesn't create real
scoping — a sourced file's functions/variables land in the same global
namespace as the caller, so the previous split never bought any actual
isolation, only extra indirection. One file (same pattern as eth-docker's
`ethd`) is easier to read top-to-bottom and easier to audit before
trusting it with a mnemonic.
