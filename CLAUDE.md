# CLAUDE.md — instructions for working on this repo

This repo (`jocd`) is a bash-only CLI that packages the machine-side setup
steps a JOC (Japan Open Chain) PoSA validator operator must perform, based
on the official "JOC Tokyo Hard Fork Validator Step-by-Step Guide".
`README.md`/`README.ja.md` are the short, human-facing quickstart —
**this file is where the architecture, guide-fidelity notes, security
model, and full self-review live.** Read this file before making changes.

This is a thin wrapper around the official *"JOC Tokyo Hard Fork
Validator Step-by-Step Guide"*, Option 2 (Recommended Configuration):
every command it runs is either taken **verbatim** from the guide, or a
direct, literal translation of a guide command into `docker compose` —
see [Verify this yourself](#verify-this-yourself) and
[Self-review](#self-review--what-was-added-beyond-the-guide) below.

**Validator-only right now.** This project used to also support
self-hosting your own Execution + Consensus Client (the guide's Option
3, which the guide itself never documents — *"Organizations selecting
Option 3 should contact us directly"*). That support was removed rather
than carried forward half-finished — it was this project's own
best-effort convention, never guide-verified, and not something to trust
in production. See [Self-review](#self-review--what-was-added-beyond-the-guide)
if/when that gets properly rebuilt.

## Ground rules

- **Guide fidelity is the whole point.** Any command copied from the
  official guide must be marked `# --- BEGIN/END: verbatim from guide,
  Step X-Y ---` (or `adapted from guide` with a one-line note on what
  differs and why). Never silently change a verbatim block — if a flag or
  value needs to change, say so explicitly in a comment and in this
  file's "Self-review" section.
- **`ROLE=validator` is the only role, full stop — no `el-cl`/`all`.**
  Self-hosting your own Execution + Consensus Client (the guide's Option
  3, which the guide explicitly does NOT document — "contact us
  directly") used to exist here as `ROLE=el-cl`/`all`; it was removed
  (see Self-review) rather than kept half-finished/unverified. Don't
  quietly re-add it — if it comes back, it needs the same "everything
  here is this project's own best-effort convention, not guide-verified"
  caveat treatment the old Option 3 section had, not a silent merge back
  into the guide-verified path.
- **Security hygiene around the mnemonic is non-negotiable**: never write
  it to disk/log/network, `set +o history` around it, no `set -x` nearby,
  explicit typed confirmation (`yes`/`delete`, not just `y`) before any
  step that shows a secret once or deletes key material irreversibly,
  `chmod 600` on every key/secret file. See [Security model](#security-model).
- **Two surfaces, deliberately separate — don't merge them back together:**
  - `jocd` — day-2 lifecycle CLI (install/init/validator/up/down/restart/
    logs/upgrade/destroy). Single file on purpose (bash `source` doesn't
    give real scoping anyway, see its header comment) — same pattern as
    eth-docker's `ethd`.
  - `staking-deposit-cli.yml` + `staking-deposit-cli/*.sh` — standalone
    key-ceremony helper (`deposit-generate`, `validator-import`; guide
    Step 2-2/2-6), run via `docker compose -f staking-deposit-cli.yml run --rm
    <service>`. Kept out of `jocd` because it's the most
    security-sensitive, most likely-to-independently-change part of the
    project (image version, extra flags, a future non-Lighthouse import
    command). `jocd init` calls it; it also runs standalone. No `docker
    run`/`docker` command of any kind lives in `jocd` for this — `jocd`
    only invokes `docker compose run` and never touches the mnemonic.
    Neither service ever submits anything to any network (both also run
    with `network_mode: none`); `deposit-generate` prints the deposit data
    for the operator to submit themselves (guide Step 3-1). Compose file +
    entrypoint scripts instead of a bash script driving `docker run`,
    modeled on eth-docker's `deposit-cli.yml`/`docker-entrypoint.sh`
    convention (`ref/eth-docker/` if present) — but keep the import command
    itself the guide's offline `lighthouse account_manager validator
    import` (Step 2-6), NOT eth-docker's Keymanager-API-based
    `validator-keys import`: that requires a Keymanager HTTP API this
    project doesn't expose and the guide doesn't document. Only the
    *structure* (tools-profile compose service + dedicated entrypoint
    script) is borrowed from eth-docker here, not the mechanism. See
    [Checked against eth-docker's import](#checked-against-eth-dockers-import).
- **Compose files, one per client** — just `lighthouse-vc-only.yml` right
  now, selected via `COMPOSE_FILE` (managed by `jocd`'s
  `compose_files_for_role()`) — not one file with `profiles:`. Keep this
  as a function/allow-list-driven single source of truth rather than a
  hardcoded constant, even with one entry, so adding a client later is
  additive. A service not in use must never even be parsed, so a future
  addition can use compose-native required-variable syntax (`${VAR:?msg}`)
  safely.
- **`networks/<mainnet|testnet|sandbox>/cl/`** holds public, non-secret
  network parameters (genesis, consensus config) — meant to be
  git-committed so operators get updates via `git pull`. Never put
  anything secret there. `data/` and `.env` are git-ignored and must stay
  that way.
- Keep the `SUPPORTED_NETWORKS`/`SUPPORTED_CL_CLIENTS`/`SUPPORTED_ROLES`
  allow-lists as the single source of truth — adding an entry is a
  deliberate, reviewed decision, not something a command should infer.
- Idempotency matters: re-running `jocd init` must never silently overwrite
  or delete existing keys/`.env`/data. Prefer "detect + ask" over
  "detect + skip silently" or "detect + overwrite".
- **Keep `README.md`/`README.ja.md` short.** They're the human quickstart
  only — install/init/connect-to-BCCloud/verify, plus a one-line-per-command
  table. Any new architecture rationale, guide-fidelity note, or
  self-review entry goes in *this* file, not there. If a change needs
  more than a couple of lines to explain to a user, that explanation
  belongs here.

## Testing safety — read this before running anything live

This CLI runs `docker compose up/down/restart` and deletes local
directories. **Do not run those live subcommands (`jocd up`, `down`,
`restart`, `destroy`, or raw `docker compose up/down/restart`) against a
real, already-deployed checkout** — this has caused real incidents twice
now: once when testing in a second checkout stopped a live validator
container (both directories shared the same basename and neither compose
file has an explicit project `name:`, so they defaulted to the same
Docker Compose project and the same `container_name:`-pinned containers),
and once when `jocd restart` was run with no arguments to "just check the
usage/dispatch," not realizing the no-argument case is the real
restart-everything path, not a no-op or a help screen. **Before running
any `jocd` subcommand you haven't fully read yet against a checkout that
might be live, run `docker ps` first and think about what the no-argument
/ default-path behavior actually does** — "just testing the CLI surface"
is not a safe assumption for a command whose default behavior does
something real.

- When verifying compose changes, use `docker compose config` (read-only,
  parse-only) — never `up`/`down`/`restart` — unless you are certain the
  checkout you're in is a disposable test directory, not a live
  deployment.
- If you must test lifecycle commands for real, do it in a throwaway
  directory with a unique basename, ideally with an explicit
  `COMPOSE_PROJECT_NAME` set, far from any real deployment.
- Never generate a real mnemonic/keys via `docker compose -f
  staking-deposit-cli.yml run --rm deposit-generate` outside of an explicit,
  informed request — it's irreversible key material, not a disposable
  test artifact. `docker compose -f staking-deposit-cli.yml config` (parse-only)
  is fine any time.

## Where things are documented

- `README.md` / `README.ja.md` — short quickstart only (prerequisites,
  install → init → connect to BCCloud → verify, a one-line-per-command
  table). Keep both in sync; keep both short.
- `CLAUDE.md` (this file) — architecture, guide fidelity, full command
  rationale, security model, "Verify this yourself", and the "Self-review"
  list of everything inferred/added beyond the guide (keep this updated
  when you add anything non-guide-verbatim).
- `networks/README.md` — what goes under `networks/` and where it comes
  from.

## Configuration

`jocd` is built around a couple of independent choices, set once in
`.env` (`jocd init` walks you through them):

| Setting | Values | What it controls |
| --- | --- | --- |
| `NETWORK` | `mainnet` \| `testnet` \| `sandbox` | Which JOC network's config/genesis to use — see `networks/<NETWORK>/cl/` and [networks/README.md](networks/README.md). |
| `CL_CLIENT` | `lighthouse` (only option today) | Which Validator Client software runs. Structured so `prysm` etc. can be added later without changing this shape — but only `lighthouse` is implemented right now; any other value is rejected with a clear "not supported yet" error (`jocd`: `SUPPORTED_CL_CLIENTS`). |
| `ROLE` | `validator` (only option) | Kept as a variable/allow-list (`SUPPORTED_ROLES`) rather than hardcoded, so a future `el-cl`/`all` role (see above) is additive to add back, not a rewrite. Not something you choose today. |

`COMPOSE_FILE` in `.env` is set automatically (`compose_files_for_role()`)
to `lighthouse-vc-only.yml` — docker compose reads `COMPOSE_FILE`
natively, no `-f` flags needed.

## What this CLI is NOT — manual BCCloud steps

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

## Compared to eth-docker's `ethd`

If you've used [eth-docker](https://github.com/ethstaker/eth-docker)'s
`ethd install|config|up|update`, `jocd` follows the same rough shape but
much smaller — no OS provisioning, no `.env` schema migration engine, and
exactly one client:

| `ethd` | `jocd` equivalent | Why it's smaller here |
| --- | --- | --- |
| `install` (installs Docker, OS packages, tunes the OS, adds user to `docker` group) | `jocd install` | Installs Docker Engine + compose plugin only, and adds your user to the `docker` group. Handles Ubuntu/Debian (official apt repo), RHEL-family (Docker's dnf repo, best-effort), and Amazon Linux specifically (its own Docker package + compose plugin from GitHub, since Docker's dnf repo doesn't work there at all — see [`jocd install`](#jocd-install) below) — `ethd` only supports Ubuntu/Debian and hard-errors on everything else. Deliberately does **not** tune the OS (swappiness, noatime, chrony/NTP) or install unrelated packages — a tool that's about to handle your mnemonic shouldn't also be doing broad root-level OS provisioning. Shows every `sudo` command before running it and asks for confirmation once. Idempotent: no-ops if Docker is already installed and working. |
| One `.yml` file per client, merged via `COMPOSE_FILE` | Same idea — just one file, `lighthouse-vc-only.yml`, right now | eth-docker has ~5 EL × ~6 CL × addons; `jocd` has exactly the one file `SUPPORTED_CL_CLIENTS` needs today. |
| `config` (interactive `.env` wizard + schema migration across versions) | `jocd init` prompts (network) + `jocd validator config` | A handful of variables, not dozens — no schema to migrate. |
| `up` | `jocd up` | Same idea: `docker compose up -d`, respecting `COMPOSE_FILE`. |
| `down` / `stop` | `jocd down` | Same idea, with a guide-specific reminder not to stop while awaiting activation (Step 3-2). |
| `logs` | `jocd logs` | Same idea: `docker compose logs -f`. |
| `update` (`git pull`, `.env` migration, image rebuild, restart, all in one) | `jocd upgrade` | Only does the `git pull` part, and only if the working tree is clean and the pull is a fast-forward. Never migrates `.env`, never restarts anything, never applies a new config by itself — it just tells you what changed and which command to run next (e.g. `jocd restart` after a `config.yaml` update). |

## Command reference (detailed rationale)

`jocd --help` (or any subcommand with no args) prints the short usage
text — this section is the "why", not a repeat of that.

### `jocd install`

Official apt repo steps on Ubuntu/Debian. On RHEL/CentOS/Fedora/Rocky/
AlmaLinux, Docker's own `docker-ce` dnf repo (best-effort). On Amazon
Linux specifically, a different path: Docker's `docker-ce` repo doesn't
work there at all — it's keyed off `$releasever`, and Amazon Linux's
`$releasever` (e.g. `2023.12.20260803` on AL2023) doesn't match any path
Docker actually publishes, so `dnf config-manager --add-repo` silently
adds a repo that 404s on the real install step (confirmed: this broke in
practice on a real AL2023 EC2 instance). Amazon Linux ships its own
Docker Engine build instead (`dnf install docker`, or
`amazon-linux-extras install docker` on the older Amazon Linux 2), but
neither has a `docker-compose-plugin` package, so the compose v2 plugin
binary is pulled directly from Docker's GitHub releases into
`/usr/libexec/docker/cli-plugins/docker-compose` — one of the system-wide
plugin directories the Docker CLI already searches, so it works for
every user, not just whoever ran `jocd install`.

Shows every `sudo` command up front and asks for confirmation once
before running any of them — see [Compared to eth-docker's
`ethd`](#compared-to-eth-dockers-ethd) (which, unlike `jocd install`,
doesn't attempt Amazon Linux/RHEL support at all — Ubuntu/Debian only,
hard error otherwise). Does not touch anything under `validator_keys/`,
doesn't tune the OS, doesn't install anything beyond Docker itself.

### `jocd init`

Prompts for `NETWORK` (or reads it from the environment / existing
`.env`), then: checks Docker; creates `data/validator_keys/`; checks
`networks/<NETWORK>/cl/{config.yaml,deposit_contract_block.txt}` exist
(prints SHA-256); prompts for the withdrawal address and delegates key
generation/import to [`staking-deposit-cli.yml`](#staking-deposit-cliyml)
(guide Step 2-2, 2-6 — `jocd` itself never touches the mnemonic); writes
`.env`; runs `docker compose up -d`; prints the `deposit_data-xxx.json`
path + confidentiality reminder.

Idempotent throughout: existing keys/config/`.env` are reused rather than
silently overwritten; you're asked before anything that isn't purely
additive.

**Changing `NETWORK` after `init`:** not supported. Deposit data is
submitted against a specific network's deposit contract, and the
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
`staking-deposit-cli/`, bind-mounted read-only into the stock
`gulabs/gu-ethstaker-deposit-cli` / `sigp/lighthouse` images. Neither
image is ever rebuilt: what runs is exactly what JBF/admin published.

`jocd init` calls both services for you automatically — most people
never invoke this directly. It's kept as its own compose file +
entrypoint scripts, deliberately outside `jocd` (see Ground rules above
for the two reasons why).

`deposit-generate` never submits anything to any network — it only prints
the resulting `deposit_data-*.json` path and contents at the end so
**you** copy/submit it yourself (guide Step 3-1). `validator-import` hands
the keystore to a local Lighthouse container; also local-only. Both
services run with `network_mode: none` — no network access is available
to either container, not just discouraged. Copy `staking-deposit-cli.yml`
plus `staking-deposit-cli/` anywhere with Docker installed to run this
standalone, e.g. to generate keys on a separate/offline machine from the
one running the Validator Client.

`staking-deposit-cli/generate-entrypoint.sh` overrides
`gulabs/gu-ethstaker-deposit-cli`'s entrypoint — guide Step 2-2's two
verbatim subcommands (`generate-mnemonic`, `existing-mnemonic`), invoked
directly since this script now runs as the container's own entrypoint
(see the file's `BEGIN/END: verbatim from guide` markers to diff against
the guide text). Same mnemonic-handling discipline as before it was
containerized: never written to disk, `set +o history` around it,
`unset` on every exit path, `clear` afterward.

`staking-deposit-cli/import-entrypoint.sh` overrides `sigp/lighthouse`'s
entrypoint — guide Step 2-6's `lighthouse account_manager validator
import`, adapted only for where the consensus config volume is mounted
(see the file's `BEGIN/END: adapted from guide` marker). This is the
guide's offline, pre-startup import — see [Checked against eth-docker's
import](#checked-against-eth-dockers-import) for why it's not the
Keymanager-API mechanism.

Both scripts default `HOST_UID`/`HOST_GID` to `0:0` (root — these
containers have no unprivileged user to drop into, unlike eth-docker's
rebuilt image) and `chown` the files they produce back to whatever
`HOST_UID`/`HOST_GID` `jocd` passes in (your actual host user), so you're
not left with root-owned key material on native Linux hosts.

#### Checked against eth-docker's import

eth-docker's key import ([`vc-utils/keymanager.sh`](https://github.com/ethstaker/eth-docker/blob/main/vc-utils/keymanager.sh),
driven by `ethd keys import`) works completely differently from this
project's: it calls the validator client's Keymanager REST API on an
**already running** container to hot-load keys, works uniformly across
every client eth-docker supports, and returns slashing-protection data
over that API. That mechanism is not documented anywhere in the JOC
guide, and adopting it would mean enabling a Keymanager HTTP API on the
Validator Client that this project doesn't currently expose — outside
this project's guide-fidelity rule. `import-entrypoint.sh` stays on the
guide's own Step 2-6 command: an **offline** `lighthouse account_manager
validator import` straight into the datadir, before the Validator Client
ever starts. What *did* get adopted from eth-docker here is the
structural pattern — a dedicated "tools"-profile compose service plus its
own entrypoint script, instead of a raw `docker run` in a host script —
and the chown-back-to-host-user convention described above.

### `jocd validator config [<key> [<value>]]`

Single, extensible entry point for validator-scoped settings. No
argument: prints every known key's current value. One key, no value:
prints just that one. Key + value: validates, writes to `.env`, offers to
apply via `docker compose up -d`. Doesn't touch keys, `NETWORK`, or
`ROLE`.

Known keys: `address` (`WITHDRAWAL_ADDRESS`, guide Step 2-7's
`--suggested-fee-recipient`) and `beacon` (`BEACON_URL`, the Consensus
Client the Validator Client connects to — BCCloud in guide Step 2-7, or a
new endpoint for a Step 4 hard fork change).

Adding a future key (e.g. graffiti) is meant to be a small, additive
change: one more entry in `jocd`'s `VALIDATOR_CONFIG_KEYS` array plus one
case arm each in `_validator_config_show()`/`_validator_config_set()` —
the view-all/view-one/confirm-and-apply flow never changes, so this
command never grows a new top-level command per setting.

### `jocd validator deposit-data`

Reprints the `deposit_data-*.json` path and contents generated by `jocd
init` (guide Step 3-1) — for whenever you need it again after the
one-time printout at init time. Public data only
(pubkey/signature/withdrawal credentials) — never touches the mnemonic,
keystore, or password file.

### `jocd status`

Checks the `validator` container is running, prints its recent logs, and
scans them for `Not attesting` per the guide's Step 3-2 criteria
(persisting 15-20+ minutes after the first 5-10 minutes is a sign
something's wrong).

### `jocd restart`

`docker compose restart validator`. This is how you apply a new hard
fork phase's `config.yaml` (guide Step 4-1's "sudo docker restart
validator") — since `validator` has `networks/<NETWORK>/cl/` bind-mounted
directly as `--testnet-dir`, restarting the container is enough for it to
pick up a `config.yaml` that changed on disk, no copy/rebuild step
needed. **Does not recreate the container** — a changed compose file or
`.env` value needs `jocd up` instead. See [Updating config via
git](#updating-config-via-git) for the full hard-fork-phase flow.

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
   git pull        # or: ./jocd upgrade
   ./jocd restart
   ```
`jocd upgrade` will show you the incoming commits (including that
`config.yaml` changed) before pulling — but applying it is a deliberate,
separate `jocd restart` afterward, not automatic. No per-phase file or
directory, no checksum ceremony baked into a command: this is a normal
git-reviewed change like any other file in this repo.

### `jocd upgrade`

Updates this CLI checkout itself via `git pull` — the code, and any
`networks/` files your team commits, including a hard-fork-phase
`config.yaml` update. Named `upgrade` rather than `update` to avoid this
project's old, confusingly similar `update`/`update-config` pair.
Refuses to run if: this directory isn't a git checkout; the working tree
has uncommitted changes; or the pull wouldn't be a fast-forward. Shows
the incoming commits and asks for confirmation before pulling.
Afterward it tells you — but does not act on — whether any root-level
`*.yml` compose file or `networks/*/cl/config.yaml` changed, so you follow
up deliberately with `jocd up` / `jocd restart` / a fresh `jocd init`
respectively.

### `jocd up` / `jocd down` / `jocd logs`

Thin wrappers around `docker compose up -d` / `down` / `logs -f` for the
`validator` service. `down` reminds you not to stop while awaiting
activation (Step 3-2). See `jocd restart` above for the difference
between `up` (recreates the container, picks up compose/`.env` changes)
and a plain restart (doesn't).

### `jocd destroy`

Stops this node's containers, then **permanently deletes** `data/` (keys,
deposit data, the Validator Client's own datadir) and `.env`. Prints
exactly what will be removed, asks you to confirm the deposit is
decommissioned or was never submitted, then requires typing `delete`
verbatim (a plain `y` isn't enough) before touching anything. No backup
is made — `networks/` (public config) is untouched.

Deliberately its own command rather than a `jocd down --data`/`--all`
flag — no accidentally-omitted flag can turn a routine stop into an
irreversible wipe. For just stopping containers (reversible), use `jocd
down` instead — this is what `jocd init` points you to when it refuses
to overwrite an existing, non-empty `data/validator_keys/`.

## Security model

- The mnemonic is **never** written to a file, logged, or sent over the
  network — it lives only in a shell variable, inside
  `staking-deposit-cli/generate-entrypoint.sh`, running inside the
  `deposit-generate` container, for the few seconds between the two
  `ethstaker-deposit-cli` calls, and is `unset` immediately after. `jocd`
  itself never sees it — it only runs `docker compose -f
  staking-deposit-cli.yml run --rm deposit-generate`.
- `set -x` is never used anywhere near `MNEMONIC` or `password.txt`.
- Both `staking-deposit-cli.yml` services run with `network_mode: none` —
  network access is unavailable to the container, not just unused.
- Every file under `validator_keys/` is `chmod 600`.
- `data/` and `.env` are git-ignored — never commit them.
- `networks/**` (`config.yaml`, `deposit_contract_block.txt`) is **not**
  git-ignored on purpose — these are public network parameters, not
  secrets, and this repo supports committing them so nodes can pick up
  updates with `git pull` (see [Updating config via
  git](#updating-config-via-git)). Never confuse this directory with
  `data/validator_keys/` — nothing under `networks/` should ever contain
  a mnemonic, keystore, or password.
- Key generation/import (`staking-deposit-cli.yml`) calls the exact
  docker images JBF/admin published in the guide
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

Before trusting this with a real mnemonic:

1. **Read the code.** The CLI proper is one file, `jocd`. Key
   generation/import is `staking-deposit-cli.yml` plus
   `staking-deposit-cli/generate-entrypoint.sh` / `import-entrypoint.sh` —
   read those specifically. The verbatim/adapted command blocks are
   marked `# --- BEGIN/END: verbatim|adapted from guide, Step 2-2/2-6 ---`
   so you can diff them directly against the original guide.
2. **No network access needed, and none available.** The guide's own
   command already uses `--ignore_connectivity`. `staking-deposit-cli.yml`
   sets `network_mode: none` on both services, so this isn't just a claim
   — the container has no network to send anything over even if it
   wanted to. Confirm independently: `docker network inspect none` while
   a `deposit-generate` run is in progress will show no container
   attached to any bridge.
3. **Run this on a disk-encrypted machine.** Prefer local console access;
   avoid SSH sessions that log the terminal session (e.g. `script`,
   session-recording bastions, some corporate SSH proxies) while the
   mnemonic is on screen.
4. Never paste the mnemonic anywhere else — not Slack, not a ticket, not
   an AI assistant.

## Self-review — what was added beyond the guide

Everything marked "verbatim" is copy-pasted from the guide text for
`ROLE=validator` on `mainnet`. Everything else below was necessarily
inferred/adapted or added — flagging it explicitly for anyone
double-checking against the guide:

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
  compose file + `staking-deposit-cli/*.sh`**, called by `jocd init`
  via `docker compose run` rather than inlined in `jocd` itself. Not from
  the guide — a deliberate architecture choice so the most
  security-sensitive, most likely-to-change part of this project (image
  version, extra flags, a future non-Lighthouse import command) never
  requires touching `jocd`'s larger lifecycle logic, and can be
  read/audited/run standalone. Originally a single bash script that ran
  `docker run` itself; restructured into a compose file + bind-mounted
  entrypoint scripts, modeled on eth-docker's
  `deposit-cli.yml`/`docker-entrypoint.sh` convention, so `jocd` never
  runs a raw `docker run`/`docker` command and never touches the mnemonic
  at all — it only invokes `docker compose run`. See
  [`staking-deposit-cli.yml`](#staking-deposit-cliyml) above, including
  [why this doesn't reuse eth-docker's Keymanager-API import](#checked-against-eth-dockers-import).
- **`network_mode: none` on both `staking-deposit-cli.yml` services.** Not
  from the guide. The guide's own `--ignore_connectivity` flag already
  implies the tool needs no network; this makes that a hard guarantee
  instead of an assumption.
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
  it, `jocd upgrade` pulls it (showing the incoming commits first), you
  `jocd restart` to apply. Entirely outside the guide, which only
  describes manual downloads. `jocd` still never runs `git pull` or
  fetches configs over the network on its own — pulling and applying are
  both explicit, separate, human-run steps. There used to be a dedicated
  `jocd network apply <phase>` command with its own checksum/confirm
  ceremony and a per-phase `networks/*/cl/phases/<phase>/` file — removed
  in favor of this simpler flow, matching how eth-docker-style projects
  normally handle config updates (git review, not an in-CLI ceremony).
- **`jocd install`.** The guide only says "ensure Docker is set up" and
  links Docker's own install guide — it doesn't specify a method. This
  command follows Docker's official documented steps (apt repo for
  Ubuntu/Debian; dnf repo for RHEL-family) rather than the `curl | sh`
  convenience script, so every command is visible and confirmed before
  running. Scoped to Docker only — no OS tuning, no unrelated packages,
  unlike `ethd install`.
- **Amazon Linux-specific Docker install path**, separate from the
  RHEL-family one. Found via a real failure on an actual AL2023 EC2
  instance: Docker's `docker-ce` dnf repo add succeeds but every install
  after it 404s, because the repo URL is keyed off `$releasever` and
  Amazon Linux's `$releasever` string doesn't match any path Docker
  publishes. Not something `ethd` has to deal with — it doesn't support
  Amazon Linux/RHEL at all, Ubuntu/Debian only. Fixed by installing
  Amazon Linux's own `docker` package (or `amazon-linux-extras install
  docker` on Amazon Linux 2) and pulling the compose v2 plugin binary
  from Docker's GitHub releases into a system-wide CLI plugin directory,
  since neither Amazon Linux path ships a `docker-compose-plugin`
  package.
- **Single-file `jocd`** instead of `scripts/*.sh` + `lib.sh`. Purely
  organizational — same logic, same verbatim-block markers, just one file
  with one `cmd_<name>()` function per subcommand instead of one process
  per file. Not from the guide or from eth-docker's exact layout, but
  deliberately modeled on `ethd`'s single-file shape.
- **`jocd validator config [<key> [<value>]]` + `jocd validator
  deposit-data`**, replacing the earlier flat `jocd config` + `jocd
  beacon set <url>`. Not from the guide — a UX cleanup: those two
  commands overlapped (both could set `BEACON_URL`), and `jocd validator
  deposit-data` is new (previously the deposit data was only ever printed
  once, at `jocd init` time). `validator config` is a key/value dispatch
  (`VALIDATOR_CONFIG_KEYS` array + a case arm per key) rather than one
  subcommand per setting, specifically so a future setting doesn't need a
  new top-level command. Also renamed `jocd update-config <phase>` →
  `jocd network apply <phase>` and
  `jocd update` → `jocd upgrade`, since the old `update`/`update-config`
  pair read as two variants of the same command when they do unrelated
  things (this CLI's own code vs. the network's consensus config).
- **`jocd network apply <phase>` removed entirely**, along with the
  per-phase `networks/*/cl/phases/<phase>/config.yaml` convention. Not
  from the guide. A hard fork's `config.yaml` now travels exactly like
  any other file your team commits: `jocd upgrade` (git pull) + `jocd
  restart` (a plain `docker compose restart`). No in-CLI checksum/confirm
  ceremony, no separate phase directory — the human verification this
  project cares about is expected to happen through normal git review
  before the commit lands, not through a command prompt. Matches how
  eth-docker-style projects normally handle config updates.
- **`jocd reset [--data]` → `jocd down` + `jocd destroy`.** Not from the
  guide — a naming/safety cleanup. `jocd reset` (no flag) and `jocd down`
  used to do almost the same thing (`docker compose down`, one with
  `--remove-orphans`); folded the orphan-removal into `jocd down` and
  dropped that redundant no-flag case entirely. The irreversible,
  data-wiping case is now its own command, `jocd destroy`, instead of a
  `--data` flag on `down` — so no accidentally-omitted flag can turn a
  routine stop into a permanent wipe, and the name itself signals
  "irreversible" instead of the more neutral-sounding "reset".
- **`ROLE=el-cl`/`all` (self-hosted Execution + Consensus Client, the
  guide's undocumented Option 3) removed entirely** — `geth.yml`,
  `lighthouse-cl-only.yml`, `networks/*/el/`, `networks/*/cl/bootnodes.txt`,
  `EL_CLIENT`/`EL_CLIENT_IMAGE`/`EL_NETWORK_ID`/bootnode-reading logic in
  `jocd`, all deleted. This was never guide-verified (the guide explicitly
  says it doesn't document Option 3) and was this project's own
  best-effort Geth/Lighthouse convention — kept only as long as it stayed
  purely additive to the guide-verified `ROLE=validator` path. Removed
  rather than left half-finished/undocumented; `SUPPORTED_ROLES` and
  `compose_files_for_role()` stay structured as allow-lists so re-adding a
  role later is additive, not a rewrite. See git history for the removed
  code if/when this gets properly rebuilt.
- **`README.md`/`README.ja.md` cut down to a short quickstart, all
  architecture/security/self-review moved into this file** (plus a
  Japanese translation added). Not from the guide — a documentation
  restructure: the previous single long README mixed a 2-minute
  quickstart with a full architecture reference, making it too long for
  someone just trying to get a validator running. `GETTING-STARTED.md`
  (the old short walkthrough) was folded into the new short `README.md`
  and removed as a separate file, since there was no longer a reason for
  two docs.

No multi-validator support, no notifications, no client beyond
`lighthouse` — nothing was added beyond what was asked for.

## Repository layout

```
joc-docker/
├── jocd                        # the whole CLI — one file:
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
│                                # called by 'jocd init', but runnable on its own
├── staking-deposit-cli/
│   ├── generate-entrypoint.sh  # overrides gu-ethstaker-deposit-cli's entrypoint
│   └── import-entrypoint.sh    # overrides sigp/lighthouse's entrypoint
├── lighthouse-vc-only.yml      # 'validator' service — guide-verbatim (Step 2-7)
├── .env.example                # sets COMPOSE_FILE — see compose_files_for_role()
├── README.md / README.ja.md    # short quickstart (EN / 日本語)
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
