# Getting started with `jocv` — step by step

This is a hands-on, copy-pasteable walkthrough for running `jocv` on
**any Linux machine you control** (EC2, a VPS, on-prem, your own server —
it doesn't matter). Nothing below is tied to a specific cloud provider;
you just need a Linux box you can SSH into.

For the architecture / guide-fidelity reference, see [README.md](README.md).
For the `networks/` layout, see [networks/README.md](networks/README.md).

This walkthrough focuses on **`ROLE=validator`** (guide Option 2 — the
path fully verified against the official guide). If you want to try
`ROLE=el-cl`/`all`, read the
["Option 3 caveat"](README.md#option-3-caveat-el-cl-roles) section in the
README first — that part is not yet confirmed with JOC/JBF.

## 0. Before you start

- [ ] A Linux machine (Ubuntu/Debian is best supported; Amazon Linux/
      RHEL-family also works but is less battle-tested — see
      `jocv install` below) that you can SSH into with `sudo` access.
- [ ] Your **receiver withdrawal address** (guide Step 1-1 — the address
      JBF/admin issued you).
- [ ] You've joined the JOC PoSA network on BCCloud (Step 1-2).
- [ ] A private, offline way to record a mnemonic phrase (pen and paper,
      or similar). **Never** paste the mnemonic anywhere else.
- [ ] The machine only needs SSH (22) open in its firewall/security
      group — `ROLE=validator` accepts no inbound connections at all, it
      only calls out to the Consensus HTTP API on BCCloud.
- [ ] Note this machine's **public IP** — you'll need it for the
      "Source" field when opening the Consensus HTTP API on BCCloud
      (guide Step 2-5).

## 1. Get the code

```bash
git clone git@github.com:anhnhx131/joc-docker.git
cd joc-docker
```

(If this machine doesn't have an SSH key registered with GitHub, use the
HTTPS URL instead: `git clone https://github.com/anhnhx131/joc-docker.git`.)

## 2. Install Docker

```bash
./jocv install
```

This command:
- Checks whether Docker is already installed — if so, it says so and
  exits, doing nothing else (safe to run repeatedly).
- If not: prints **every** `sudo` command it's about to run, asks for
  confirmation once, then executes them — following Docker's official
  documented steps ([docs.docker.com](https://docs.docker.com/engine/install/)),
  not an opaque `curl | sh` script.
- Adds your current user to the `docker` group so you don't need `sudo`
  for every docker command.

If you were just added to the `docker` group, **log out of SSH and back
in** (or run `newgrp docker`) before continuing — group membership only
applies to new login sessions.

Verify:

```bash
docker --version
docker compose version
```

> `jocv install` only installs Docker — it doesn't tune the OS
> (swappiness, NTP, etc.) and doesn't install anything else. If your
> distro isn't supported, it says so clearly and points you to Docker's
> official install guide instead.

## 3. Place the network config files (guide Step 2-1)

`jocv` can't auto-download `config.yaml`/`deposit_contract_block.txt` —
the JOC page is an HTML docs page, not a raw file URL. Get them manually:

1. Open https://www.japanopenchain.org/vi/docs/developer/connect-joc/mainnet/
2. Download `config.yaml` and `deposit_contract_block.txt`.
3. Place both in `networks/mainnet/cl/` on the machine running `jocv`:

```bash
# example: scp from the machine you downloaded them on
scp config.yaml deposit_contract_block.txt \
  your-user@<jocv-machine-ip>:~/joc-docker/networks/mainnet/cl/
```

A cleaner long-term option: commit these two files into your team's
`joc-docker` repo (see the README's "Updating config via git" section),
so this step becomes just `git pull`.

## 4. Run `jocv init`

```bash
./jocv init
```

You'll be prompted through the following, in order:

1. **`Which network? [mainnet]:`** — press Enter for mainnet (default).
2. **`Which role? [validator]:`** — press Enter for `validator` (default,
   guide Option 2).
3. The script checks that `config.yaml`/`deposit_contract_block.txt` from
   step 3 above are in place — if missing, it errors out with instructions.
4. **`Enter the receiver withdrawal address obtained in Step 1-1 (0x...):`**
   — paste the address JBF/admin gave you (Step 1-1). Wrong format is
   rejected immediately, so a typo won't slip through silently.
5. A random `password.txt` is generated, `chmod 600`.
6. The mnemonic-generation command runs (a few seconds, no network needed).
7. **The mnemonic is printed to the screen exactly once**, like this:
   ```
   ================================================================
    MNEMONIC — write this down OFFLINE now. It will only be shown once:

    comic oven rent shock ... (12-24 words)

   ================================================================
   ```
   **Stop here and write it down on paper right now.** Don't screenshot
   it, don't copy it into any file/note/chat.
8. **`Have you securely written down this mnemonic OFFLINE? Type 'yes' to continue:`**
   — only type `yes` once you've actually written it down. Anything else
   aborts safely — no keys are generated, nothing is lost.
9. The tool creates `keystore-xxx.json` and `deposit_data-xxx.json`,
   clears the mnemonic from memory, and clears the screen.
10. The tool imports the key into Lighthouse, writes `.env`, and runs
    `docker compose up -d`.
11. Finally it prints the path to `deposit_data-xxx.json` (needed for
    Step 3-1 — Launchpad) and a security reminder.

If something goes wrong partway through, `jocv init` is **safe to
re-run** — it detects what's already done (existing keys, existing
`.env`, ...) and asks before overwriting anything; it never deletes on
its own.

## 5. Manual work on BCCloud (not covered by `jocv`)

At this point, switch over to [BCCloud](https://app.bccloud.net/) (see
the original guide, or the table near the top of README.md, for details):

1. **Step 2-3**: Create a Transaction Cluster (2 relay nodes, Tokyo region).
2. **Step 2-4**: Create a Validator Cluster, add an **External Validator**
   node, entering the `pubkey` from `deposit_data-xxx.json` (the path
   `jocv init` printed in step 4.11 above).
3. **Step 2-5**: Open the Consensus HTTP API on that node, restricted to
   the **public IP of the machine running `jocv`** (noted in step 0).
   Note the BCCloud node's IP — you'll need it next.

## 6. Point the Validator Client at BCCloud

```bash
./jocv beacon set http://<bccloud-node-ip>:3500
```

This updates `.env` and re-runs `docker compose up -d` automatically.

## 7. Check status

```bash
./jocv status
```

Expect the `validator` container to be `Up`, with no connection errors in
recent logs. If `Not attesting` keeps appearing for more than 15-20
minutes (after the first 5-10 minutes of startup), something's wrong —
check the detailed logs:

```bash
./jocv logs validator
```

## 8. Submit deposit data (Step 3-1)

Open Launchpad at the URL JBF shared with you, and upload
`data/validator_keys/deposit_data-xxx.json` (path printed in step 4).
Then track activation status per the guide's Step 3-2 with `./jocv status`.

## Common issues

| Symptom | Cause / fix |
| --- | --- |
| `docker: permission denied` after `jocv install` | The new `docker` group membership hasn't taken effect yet — log out/in of SSH, or run `newgrp docker`. |
| `jocv install` says "Unsupported/unrecognized distro" | Your distro isn't covered — install Docker via the [official guide](https://docs.docker.com/engine/install/) yourself, then re-run `jocv install` (it will detect Docker is present and skip). |
| `jocv init` complains `config.yaml` is missing | You haven't placed the files in `networks/mainnet/cl/` yet (step 3) — double-check filenames and directory. |
| `Invalid address` when entering the withdrawal address | Must be `0x` + exactly 40 hex characters (42 total). A missing/extra character from a copy-paste is the usual culprit. |
| `docker compose up` complains about a missing `execution` image while using `ROLE=validator` | Shouldn't happen — if it does, please report it; `ROLE=validator` should never touch the `execution`/`beacon` services. |
| Want to start completely over | Stop the container (`./jocv down`), delete `data/` and `.env`, re-run `./jocv init`. **Only do this if you haven't submitted deposit data yet** — deleting keys after submission means you lose the ability to operate that validator. |

## After testing one network/role combination

Changing `NETWORK` or `ROLE` after `init` is **not supported** — keys and
deposit data are tied to a specific network. To try a different
network/role, use a fresh checkout (`git clone` into another directory);
don't edit the `.env` of a checkout you're actually running.
