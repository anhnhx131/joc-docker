# CLAUDE.md — instructions for working on this repo

This repo (`jocv`) is a bash-only CLI that packages the machine-side setup
steps a JOC (Japan Open Chain) PoSA validator operator must perform, based
on the official "JOC Tokyo Hard Fork Validator Step-by-Step Guide". Read
`README.md` first for the full picture (architecture, command reference,
self-review of what's guide-verbatim vs. inferred) before making changes.

## Ground rules

- **Guide fidelity is the whole point.** Any command copied from the
  official guide must be marked `# --- BEGIN/END: verbatim from guide,
  Step X-Y ---` (or `adapted from guide` with a one-line note on what
  differs and why). Never silently change a verbatim block — if a flag or
  value needs to change, say so explicitly in a comment and in README's
  "Self-review" section.
- **`ROLE=validator` is the only guide-verified path.** `el-cl`/`all`
  correspond to the guide's Option 3, which the guide explicitly does NOT
  document ("contact us directly") — everything there is this project's
  own best-effort Geth/Lighthouse convention. Don't blur that distinction;
  keep the "Option 3 caveat" warnings intact.
- **Security hygiene around the mnemonic is non-negotiable**: never write
  it to disk/log/network, `set +o history` around it, no `set -x` nearby,
  explicit typed confirmation (`yes`/`delete`, not just `y`) before any
  step that shows a secret once or deletes key material irreversibly,
  `chmod 600` on every key/secret file.
- **Two surfaces, deliberately separate — don't merge them back together:**
  - `jocv` — day-2 lifecycle CLI (install/init/config/up/down/logs/update/
    reset). Single file on purpose (bash `source` doesn't give real scoping
    anyway, see its header comment) — same pattern as eth-docker's `ethd`.
  - `staking-deposit-cli.yml` + `staking-deposit-cli/*.sh` — standalone
    key-ceremony helper (`deposit-generate`, `validator-import`; guide
    Step 2-2/2-6), run via `docker compose -f staking-deposit-cli.yml run --rm
    <service>`. Kept out of `jocv` because it's the most
    security-sensitive, most likely-to-independently-change part of the
    project (image version, extra flags, a future non-Lighthouse import
    command). `jocv init` calls it; it also runs standalone. No `docker
    run`/`docker` command of any kind lives in `jocv` for this — `jocv`
    only invokes `docker compose run` and never touches the mnemonic.
    Neither service ever submits anything to any network (both also run
    with `network_mode: none`); `deposit-generate` prints the deposit data
    for the operator to submit themselves (guide Step 3-1). Compose file +
    entrypoint scripts instead of a bash script driving `docker run`,
    modeled on eth-docker's `staking-deposit-cli.yml`/`docker-entrypoint.sh`
    convention (`ref/eth-docker/` if present) — but keep the import command
    itself the guide's offline `lighthouse account_manager validator
    import` (Step 2-6), NOT eth-docker's Keymanager-API-based
    `validator-keys import`: that requires a Keymanager HTTP API this
    project doesn't expose and the guide doesn't document. Only the
    *structure* (tools-profile compose service + dedicated entrypoint
    script) is borrowed from eth-docker here, not the mechanism.
- **Compose files, one per client** (`lighthouse-vc-only.yml`, `geth.yml`,
  `lighthouse-cl-only.yml`), merged via `COMPOSE_FILE` (colon-joined,
  managed by `jocv`'s `compose_files_for_role()`) — not one file with
  `profiles:`. A service not in use must never even be parsed, so it can
  use compose-native required-variable syntax (`${VAR:?msg}`) safely.
- **`networks/<mainnet|testnet|sandbox>/{el,cl}/`** holds public,
  non-secret network parameters (genesis, bootnodes, consensus config) —
  meant to be git-committed so operators get updates via `git pull`. Never
  put anything secret there. `data/` and `.env` are git-ignored and must
  stay that way.
- Keep the `SUPPORTED_NETWORKS`/`SUPPORTED_EL_CLIENTS`/`SUPPORTED_CL_CLIENTS`/
  `SUPPORTED_ROLES` allow-lists as the single source of truth — adding an
  entry is a deliberate, reviewed decision, not something a command should
  infer.
- Idempotency matters: re-running `jocv init` must never silently overwrite
  or delete existing keys/`.env`/data. Prefer "detect + ask" over
  "detect + skip silently" or "detect + overwrite".

## Testing safety — read this before running anything live

This CLI runs `docker compose up/down/restart` and deletes local
directories. **Do not run those live subcommands (`jocv up`, `down`,
`reset`, or raw `docker compose up/down/restart`) against a real,
already-deployed checkout** — a past session caused a real incident where
testing in a second checkout stopped a live validator container, because
both directories shared the same basename and neither compose file has an
explicit project `name:`, so they defaulted to the same Docker Compose
project and the same `container_name:`-pinned containers.

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

- `README.md` — architecture, full command reference, security section,
  "Verify this yourself", and a "Self-review" list of everything that's
  inferred/added beyond the guide (keep this updated when you add anything
  non-guide-verbatim).
- `GETTING-STARTED.md` — short, eth-docker-QuickStart-style walkthrough,
  `ROLE=validator` only.
- `networks/README.md` — what goes under `networks/`, where it comes from,
  the plain-text `bootnodes.txt` format.
