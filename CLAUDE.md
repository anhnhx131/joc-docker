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
- **`ROLE=validator` is the only role, full stop — no `el-cl`/`all`.**
  Self-hosting your own Execution + Consensus Client (the guide's Option
  3, which the guide explicitly does NOT document — "contact us
  directly") used to exist here as `ROLE=el-cl`/`all`; it was removed
  (see README's Self-review) rather than kept half-finished/unverified.
  Don't quietly re-add it — if it comes back, it needs the same
  "everything here is this project's own best-effort convention, not
  guide-verified" caveat treatment the old Option 3 section had, not a
  silent merge back into the guide-verified path.
- **Security hygiene around the mnemonic is non-negotiable**: never write
  it to disk/log/network, `set +o history` around it, no `set -x` nearby,
  explicit typed confirmation (`yes`/`delete`, not just `y`) before any
  step that shows a secret once or deletes key material irreversibly,
  `chmod 600` on every key/secret file.
- **Two surfaces, deliberately separate — don't merge them back together:**
  - `jocv` — day-2 lifecycle CLI (install/init/validator/up/down/restart/
    logs/upgrade/destroy). Single file on purpose (bash `source` doesn't
    give real scoping anyway, see its header comment) — same pattern as
    eth-docker's `ethd`.
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
- **Compose files, one per client** — just `lighthouse-vc-only.yml` right
  now, selected via `COMPOSE_FILE` (managed by `jocv`'s
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
- Idempotency matters: re-running `jocv init` must never silently overwrite
  or delete existing keys/`.env`/data. Prefer "detect + ask" over
  "detect + skip silently" or "detect + overwrite".

## Testing safety — read this before running anything live

This CLI runs `docker compose up/down/restart` and deletes local
directories. **Do not run those live subcommands (`jocv up`, `down`,
`restart`, `destroy`, or raw `docker compose up/down/restart`) against a
real, already-deployed checkout** — this has caused real incidents twice
now: once when testing in a second checkout stopped a live validator
container (both directories shared the same basename and neither compose
file has an explicit project `name:`, so they defaulted to the same
Docker Compose project and the same `container_name:`-pinned containers),
and once when `jocv restart` was run with no arguments to "just check the
usage/dispatch," not realizing the no-argument case is the real
restart-everything path, not a no-op or a help screen. **Before running
any `jocv` subcommand you haven't fully read yet against a checkout that
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

- `README.md` — architecture, full command reference, security section,
  "Verify this yourself", and a "Self-review" list of everything that's
  inferred/added beyond the guide (keep this updated when you add anything
  non-guide-verbatim).
- `GETTING-STARTED.md` — short, eth-docker-QuickStart-style walkthrough.
- `networks/README.md` — what goes under `networks/` and where it comes
  from.
