# joc-docker (`jocv`)

A small bash-only CLI for running a **JOC (Japan Open Chain) PoSA
Validator Client** on infrastructure you control, as opposed to the parts
done through the BCCloud web UI.

> **Just want to try it on a real EC2 box?** See
> [GETTING-STARTED.md](GETTING-STARTED.md) for a hands-on, copy-pasteable
> walkthrough (launch instance → install Docker → `jocv init` → what each
> prompt looks like → BCCloud steps → verify). This README is the
> reference doc (architecture, guide fidelity, security model).

This is a thin wrapper around the official *"JOC Tokyo Hard Fork
Validator Step-by-Step Guide"*, Option 2 (Recommended Configuration):
every command it runs is either taken **verbatim** from the guide, or a
direct, literal translation of a guide command into `docker compose` —
see [Verify this yourself](#verify-this-yourself) and
[Self-review](#self-review--what-i-added-beyond-the-guide).

**Validator-only right now.** This project used to also support
self-hosting your own Execution + Consensus Client (the guide's Option
3, which the guide itself never documents — *"Organizations selecting
Option 3 should contact us directly"*). That support was removed rather
than carried forward half-finished — it was this project's own
best-effort convention, never guide-verified, and not something to trust
in production. See [Self-review](#self-review--what-i-added-beyond-the-guide)
if/when that gets properly rebuilt.

## Configuration

`jocv` is built around a couple of independent choices, set once in
`.env` (`jocv init` walks you through them):

| Setting | Values | What it controls |
| --- | --- | --- |
| `NETWORK` | `mainnet` \| `testnet` \| `sandbox` | Which JOC network's config/genesis to use — see `networks/<NETWORK>/cl/` and [networks/README.md](networks/README.md). |
| `CL_CLIENT` | `lighthouse` (only option today) | Which Validator Client software runs. Structured so `prysm` etc. can be added later without changing this shape — but only `lighthouse` is implemented right now; any other value is rejected with a clear "not supported yet" error (`jocv`: `SUPPORTED_CL_CLIENTS`). |
| `ROLE` | `validator` (only option) | Kept as a variable/allow-list (`SUPPORTED_ROLES`) rather than hardcoded, so a future `el-cl`/`all` role (see above) is additive to add back, not a rewrite. Not something you choose today. |

`COMPOSE_FILE` in `.env` is set automatically (`compose_files_for_role()`)
to `lighthouse-vc-only.yml` — docker compose reads `COMPOSE_FILE`
natively, no `-f` flags needed.

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

If your organization uses the guide's **Option 1 (Internal Validator)** —
Execution, Consensus, *and* Validator Client all run on BCCloud — this CLI
does not apply to you at all. Follow "Option 1: Setup for Internal
Validators" in the guide directly; there is nothing to run on your own
machine.

### Compared to eth-docker's `ethd`

If you've used [eth-docker](https://github.com/ethstaker/eth-docker)'s
`ethd install|config|up|update`, `jocv` follows the same rough shape but
much smaller — no OS provisioning, no `.env` schema migration engine, and
exactly one client:

| `ethd` | `jocv` equivalent | Why it's smaller here |
| --- | --- | --- |
| `install` (installs Docker, OS packages, tunes the OS, adds user to `docker` group) | `jocv install` | Installs Docker Engine + compose plugin only (official apt repo on Ubuntu/Debian, best-effort dnf repo elsewhere), and adds your user to the `docker` group. Deliberately does **not** tune the OS (swappiness, noatime, chrony/NTP) or install unrelated packages — a tool that's about to handle your mnemonic shouldn't also be doing broad root-level OS provisioning. Shows every `sudo` command before running it and asks for confirmation once. Idempotent: no-ops if Docker is already installed and working. |
| One `.yml` file per client, merged via `COMPOSE_FILE` | Same idea — just one file, `lighthouse-vc-only.yml`, right now | eth-docker has ~5 EL × ~6 CL × addons; `jocv` has exactly the one file `SUPPORTED_CL_CLIENTS` needs today. |
| `config` (interactive `.env` wizard + schema migration across versions) | `jocv init` prompts (network) + `jocv validator config` | A handful of variables, not dozens — no schema to migrate. |
| `up` | `jocv up` | Same idea: `docker compose up -d`, respecting `COMPOSE_FILE`. |
| `down` / `stop` | `jocv down` | Same idea, with a guide-specific reminder not to stop while awaiting activation (Step 3-2). |
| `logs` | `jocv logs` | Same idea: `docker compose logs -f`. |
| `update` (`git pull`, `.env` migration, image rebuild, restart, all in one) | `jocv upgrade` | Only does the `git pull` part, and only if the working tree is clean and the pull is a fast-forward. Never migrates `.env`, never restarts anything, never applies a new config by itself — it just tells you what changed and which command to run next (e.g. `jocv restart` after a `config.yaml` update). |

## Prerequisites

- A Linux/macOS machine you control (any infra — EC2, on-prem, a VPS,
  whatever you have) that can run stably and stay online.
- [Docker](https://docs.docker.com/engine/install/) installed, daemon
  running, with the `docker compose` v2 plugin available — run
  `jocv install` if you don't have it yet (Ubuntu/Debian and, best-effort,
  Amazon Linux/RHEL-family).
- `bash`, `sed` (all standard on any Linux/macOS box — no `yq`/Python/Node
  dependency, by design).
- You've completed guide Step 1-1 (receiver withdrawal address) and Step
  1-2 (joined the JOC PoSA network on BCCloud), plus a private,
  offline-capable way to record a mnemonic phrase — see
  [Security](#security).

## Quick start

```bash
./jocv install       # if Docker isn't installed yet (safe to skip if it is)
./jocv init          # prompts: NETWORK=mainnet, then guide
                      # Step 2-1, 2-2, 2-6, 2-7, 2-8

# --- meanwhile, on BCCloud (manual, see table above): -----------------
#   Step 2-3: create the Transaction Cluster
#   Step 2-4: create the Validator Cluster + External Validator node,
#             registering the pubkey from deposit_data-xxx.json
#   Step 2-5: open the Consensus HTTP API to your Validator Server's IP,
#             and note the BCCloud node's IP address
# ------------------------------------------------------------------------

./jocv validator config beacon http://<bccloud-validator-node-ip>:3500
./jocv status         # guide Step 3-2
```

After that, submit `data/validator_keys/deposit_data-xxx.json` to
Launchpad (guide Step 3-1) — `jocv init` prints its exact path at the
end, and `jocv validator deposit-data` reprints it anytime after.

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

Prompts for `NETWORK` (or reads it from the environment / existing
`.env`), then:

1. Checks Docker is installed and running.
2. Creates `data/validator_keys/`.
3. Checks `networks/<NETWORK>/cl/{config.yaml,deposit_contract_block.txt}`
   exist (see [networks/README.md](networks/README.md) — manual download
   or git-committed by your team), prints their SHA-256.
4. Prompts for your withdrawal address, validated as `0x` + 40 hex chars
   (guide Step 2-2, 2-6). Delegates to
   [`staking-deposit-cli.yml`](#staking-deposit-cliyml) — a separate,
   standalone compose file — to actually generate and import the key via
   `docker compose -f staking-deposit-cli.yml run --rm <service>`. `jocv
   init` never runs an `ethstaker-deposit-cli`/`lighthouse` docker command
   itself, and never touches the mnemonic; see
   `staking-deposit-cli/*-entrypoint.sh` for what happens step by step
   (password, mnemonic, the guide's two verbatim commands, the mandatory
   typed `yes` confirmation, then the Step 2-6 Lighthouse import).
5. Writes/updates `.env` (`NETWORK`, `ROLE`, `COMPOSE_FILE`, `CL_CLIENT`,
   `WITHDRAWAL_ADDRESS`).
6. Runs `docker compose up -d`.
7. Prints the `deposit_data-xxx.json` path (needed for Step 3-1) and a
   loud confidentiality reminder.

Idempotent throughout: existing keys/config/`.env` are reused rather than
silently overwritten; you're asked before anything that isn't purely
additive.

**Changing `NETWORK` after `init`:** not supported by this CLI. Deposit
data is submitted against a specific network's deposit contract, and the
withdrawal address you provide is issued per-network by JBF/admin —
reusing the same keys across networks isn't meaningful. Start a fresh
checkout for a different network.

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

`jocv init` calls both services for you automatically — most people
never invoke this directly. It's kept as its own compose file +
entrypoint scripts, deliberately outside `jocv`, for two reasons:

- It's the part of this project most likely to need independent tweaking
  (image version/tag, extra flags, a future non-Lighthouse import command)
  — changing it never requires touching `jocv`'s larger lifecycle logic
  (`install`/`up`/`down`/`logs`/`upgrade`), and vice versa.
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

### `jocv validator config [<key> [<value>]]`

Single, extensible entry point for validator-scoped settings, for an
already-initialized node. Doesn't touch keys, `NETWORK`, or `ROLE` —
those are fixed at `jocv init` time (see above).

- `jocv validator config` — prints every known key's current value.
- `jocv validator config <key>` — prints just that one.
- `jocv validator config <key> <value>` — validates, writes it to `.env`,
  then offers to apply via `docker compose up -d`.

Known keys today:

| Key | Env var | Notes |
| --- | --- | --- |
| `address` | `WITHDRAWAL_ADDRESS` | Guide Step 2-7's `--suggested-fee-recipient`. |
| `beacon` | `BEACON_URL` | The Consensus Client the Validator Client connects to — BCCloud in guide Step 2-7, or a new endpoint for a Step 4 hard fork change. |

Adding a future key (e.g. graffiti) is meant to be a small, additive
change: one more entry in `jocv`'s `VALIDATOR_CONFIG_KEYS` array plus one
case arm each in `_validator_config_show()`/`_validator_config_set()` —
the view-all/view-one/confirm-and-apply flow above stays exactly the
same, so `jocv validator config` never grows a new top-level command per
setting.

### `jocv validator deposit-data`

Reprints the `deposit_data-*.json` path and contents generated by `jocv
init` (guide Step 3-1) — for whenever you need it again after the
one-time printout at init time (lost terminal scrollback, submitting from
a different session, etc.). Public data only (pubkey/signature/withdrawal
credentials) — never touches the mnemonic, keystore, or password file.

### `jocv status`

Checks the `validator` container is running, prints its recent logs, and
scans them for `Not attesting` per the guide's Step 3-2 criteria
(persisting 15-20+ minutes after the first 5-10 minutes is a sign
something's wrong).

### `jocv restart`

`docker compose restart validator`. This is how you apply a new hard
fork phase's `config.yaml` (guide Step 4-1's "sudo docker restart
validator") — since `validator` has `networks/<NETWORK>/cl/` bind-mounted
directly as `--testnet-dir`, restarting the container is enough for it to
pick up a `config.yaml` that changed on disk, no copy/rebuild step needed.

**Does not recreate the container** — it will not pick up a changed compose
file or `.env` value (image, `command:`, `environment:`); that needs
`jocv up` instead. See [Updating config via git](#updating-config-via-git)
for the full hard-fork-phase flow.

### Updating config via git

If your team commits the official `config.yaml` into this repo (instead
of every validator server downloading it manually each time from the JOC
page), the update flow for a new hard fork phase is exactly the same as
any other CLI update:

1. **Team/maintainer:** get the official config for the new phase from
   JBF/admin, verify it, overwrite `networks/<NETWORK>/cl/config.yaml` in
   place with it, commit, push.
2. **On each node:**
   ```bash
   git pull        # or: ./jocv upgrade
   ./jocv restart
   ```
`jocv upgrade` will show you the incoming commits (including that
`config.yaml` changed) before pulling, so you still see what's about to
land before it does — but applying it is a deliberate, separate `jocv
restart` afterward, not automatic. There's no per-phase file or directory
anymore, no checksum ceremony baked into a command: this is a normal
git-reviewed change like any other file in this repo, verified the same
way your team verifies any other commit before merging/pushing it.

### `jocv upgrade`

Updates this CLI checkout itself via `git pull` — the code, and any
`networks/` files your team commits (see above), including a
hard-fork-phase `config.yaml` update. Named `upgrade` rather than
`update` to avoid this project's old, confusingly similar
`update`/`update-config` pair. Refuses to run if:
- this directory isn't a git checkout,
- the working tree has uncommitted changes, or
- the pull wouldn't be a fast-forward (i.e. your local branch diverged).

Shows the incoming commits and asks for confirmation before pulling.
Afterward it tells you — but does not act on — whether any root-level
`*.yml` compose file or `networks/*/cl/config.yaml` changed, so you follow
up deliberately with `jocv up` / `jocv restart` / a fresh `jocv init`
respectively.

### `jocv up` / `jocv down` / `jocv logs`

Thin wrappers around `docker compose up -d` / `down` / `logs -f` for the
`validator` service. `down` reminds you not to stop while awaiting
activation (Step 3-2). See [`jocv restart`](#jocv-restart) above for the
difference between `up` (recreates the container, picks up compose/`.env`
changes) and a plain restart (doesn't).

### `jocv destroy`

For starting over from nothing. Stops this node's containers, then
**permanently deletes** `data/` (keys, deposit data, the Validator
Client's own datadir) and `.env`. Prints exactly what will be removed,
asks you to confirm the deposit is decommissioned or was never submitted,
then requires typing `delete` verbatim (a plain `y` isn't enough) before
touching anything. No backup is made — `networks/` (public config) is
untouched, but everything under `data/` is gone for good. Only run this
if you're certain you don't need this validator's keys anymore.

Deliberately its own command rather than a `jocv down --data`/`--all`
flag — no accidentally-omitted flag can turn a routine stop into an
irreversible wipe. For just stopping containers (reversible, data/`.env`
untouched), use `jocv down` instead — this is what `jocv init` points you
to when it refuses to overwrite an existing, non-empty
`data/validator_keys/`.

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
- Every file under `validator_keys/` is `chmod 600`.
- `data/` and `.env` are git-ignored — never commit them.
- `networks/**` (`config.yaml`, `deposit_contract_block.txt`) is **not**
  git-ignored on purpose — these are public network parameters, not
  secrets, and this repo supports committing them so nodes can pick up
  updates with `git pull` (see
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
  guide's own text and trust that nothing "extra" is happening.
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

- **Multi-network (`networks/<NETWORK>/cl/`).** The guide is written
  entirely in terms of one network (mainnet). Extended so `NETWORK=testnet`
  /`sandbox` select their own config/genesis directory, on the
  assumption (not stated in the guide) that these networks follow the same
  file layout as mainnet.
- **`lighthouse-vc-only.yml` command as a YAML list, not a shell string**,
  for the `validator` service. The guide's Step 2-7 `docker run` block is
  missing a trailing `\` line-continuation on one line; expressing it as a
  YAML list sidesteps that ambiguity entirely while keeping the same flags.
- **One compose file per client (`lighthouse-vc-only.yml`), merged via
  `COMPOSE_FILE`, instead of one `docker-compose.yml` filtered by
  `profiles:`.** Not from the guide — adopted from
  [eth-docker](https://github.com/ethstaker/eth-docker/blob/main/lighthouse-vc-only.yml)'s
  convention. Only one file exists today, but the pattern (a
  `compose_files_for_role()` single source of truth) scales to more
  clients later without a rewrite.
- **Client allow-list (`CL_CLIENT`)** with only `lighthouse` implemented
  today. Structured so `prysm` etc. can be added later; any other value
  is rejected rather than silently accepted.
- **`BEACON_URL` default placeholder (`http://127.0.0.1:5052`).** Not from
  the guide — a deliberately inert default so `docker compose up -d` can
  succeed without pointing at anything real.
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
  `deposit-cli.yml`/`docker-entrypoint.sh` convention, so `jocv` never
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
- **`docker compose restart validator` instead of the guide's `sudo docker
  restart validator`** (Step 4-1). Same effect, works with how this CLI
  manages containers via compose.
- **`.gitignore` excluding `data/` and `.env`.** A necessary consequence
  of the guide's own confidentiality requirement for the mnemonic/keystore/
  password.
- **Random password generation** (`openssl rand -base64 24`, run inside
  the `deposit-generate` container). The guide specifies the password
  must be >12 characters but not a method; `openssl rand` is a standard
  way to satisfy that.
- **Git-backed config distribution** — a hard fork's new `config.yaml`
  travels the same way as any other file in this repo: your team commits
  it, `jocv upgrade` pulls it (showing the incoming commits first), you
  `jocv restart` to apply. Entirely outside the guide, which only
  describes manual downloads. `jocv` still never runs `git pull` or
  fetches configs over the network on its own — pulling and applying are
  both explicit, separate, human-run steps. There used to be a dedicated
  `jocv network apply <phase>` command with its own checksum/confirm
  ceremony and a per-phase `networks/*/cl/phases/<phase>/` file — removed
  in favor of this simpler flow, matching how eth-docker-style projects
  normally handle config updates (git review, not an in-CLI ceremony).
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
- **`jocv validator config [<key> [<value>]]` + `jocv validator
  deposit-data`**, replacing the earlier flat `jocv config` + `jocv
  beacon set <url>`. Not from the guide — a UX cleanup: those two
  commands overlapped (both could set `BEACON_URL`), and `jocv validator
  deposit-data` is new (previously the deposit data was only ever printed
  once, at `jocv init` time). `validator config` is a key/value dispatch
  (`VALIDATOR_CONFIG_KEYS` array + a case arm per key) rather than one
  subcommand per setting, specifically so a future setting doesn't need a
  new top-level command. Also renamed `jocv update-config <phase>` →
  `jocv network apply <phase>` and
  `jocv update` → `jocv upgrade`, since the old `update`/`update-config`
  pair read as two variants of the same command when they do unrelated
  things (this CLI's own code vs. the network's consensus config).
- **`jocv network apply <phase>` removed entirely**, along with the
  per-phase `networks/*/cl/phases/<phase>/config.yaml` convention. Not
  from the guide. A hard fork's `config.yaml` now travels exactly like
  any other file your team commits: `jocv upgrade` (git pull) + `jocv
  restart` (new — a plain `docker compose restart`, see above). No
  in-CLI checksum/confirm ceremony, no separate phase directory — the
  human verification this project cares about is expected to happen
  through normal git review before the commit lands, not through a
  command prompt. Matches how eth-docker-style projects normally handle
  config updates.
- **`jocv reset [--data]` → `jocv down` + `jocv destroy`.** Not from the
  guide — a naming/safety cleanup. `jocv reset` (no flag) and `jocv down`
  used to do almost the same thing (`docker compose down`, one with
  `--remove-orphans`); folded the orphan-removal into `jocv down` and
  dropped that redundant no-flag case entirely. The irreversible,
  data-wiping case is now its own command, `jocv destroy`, instead of a
  `--data` flag on `down` — so no accidentally-omitted flag can turn a
  routine stop into a permanent wipe, and the name itself signals
  "irreversible" instead of the more neutral-sounding "reset".
- **`ROLE=el-cl`/`all` (self-hosted Execution + Consensus Client, the
  guide's undocumented Option 3) removed entirely** — `geth.yml`,
  `lighthouse-cl-only.yml`, `networks/*/el/`, `networks/*/cl/bootnodes.txt`,
  `EL_CLIENT`/`EL_CLIENT_IMAGE`/`EL_NETWORK_ID`/bootnode-reading logic in
  `jocv`, all deleted. This was never guide-verified (the guide explicitly
  says it doesn't document Option 3) and was this project's own
  best-effort Geth/Lighthouse convention — kept only as long as it stayed
  purely additive to the guide-verified `ROLE=validator` path. Removed
  rather than left half-finished/undocumented; `SUPPORTED_ROLES` and
  `compose_files_for_role()` stay structured as allow-lists so re-adding a
  role later is additive, not a rewrite. See git history for the removed
  code if/when this gets properly rebuilt.

No multi-validator support, no notifications, no client beyond
`lighthouse` — nothing was added beyond what was asked for.

## Repository layout

```
joc-docker/
├── jocv                        # the whole CLI — one file:
│                                #   1. paths + SUPPORTED_* allow-lists
│                                #   2. helpers (logging, confirm(), validators,
│                                #      env/network utilities)
│                                #   3. one cmd_<name>() function per subcommand
│                                #      (install, init, validator, status, upgrade,
│                                #       up, down, restart, destroy, logs)
│                                #   4. usage() + dispatch (case "$1") at the bottom
├── staking-deposit-cli.yml     # standalone key ceremony compose file (Step 2-2, 2-6)
│                                #   deposit-generate: mnemonic + keystore + deposit data
│                                #   validator-import: hands keystore to a local Lighthouse
│                                # called by 'jocv init', but runnable on its own
├── staking-deposit-cli/
│   ├── generate-entrypoint.sh  # overrides gu-ethstaker-deposit-cli's entrypoint
│   └── import-entrypoint.sh    # overrides sigp/lighthouse's entrypoint
├── lighthouse-vc-only.yml      # 'validator' service — guide-verbatim (Step 2-7)
├── .env.example                # sets COMPOSE_FILE — see compose_files_for_role()
└── networks/
    ├── README.md
    └── {mainnet,testnet,sandbox}/
        └── cl/
            └── config.yaml / deposit_contract_block.txt / genesis.ssz
```

Why one file instead of `scripts/*.sh`: bash `source` doesn't create real
scoping — a sourced file's functions/variables land in the same global
namespace as the caller, so the previous split never bought any actual
isolation, only extra indirection. One file (same pattern as eth-docker's
`ethd`) is easier to read top-to-bottom and easier to audit before
trusting it with a mnemonic.
