# Harnes Agent — install on a new computer

Public installer for the device agent from the private [Harnes Remote](https://github.com/dmitry-baranov/harnes-remote) control-plane repository. Supports macOS and Linux (x64/arm64). Requires `curl`, `tar`, a SHA-256 utility and internet access. No Git checkout, Docker, admin privileges or pnpm required.

**One command** in fish or a POSIX shell:

```fish
curl -fsSL https://raw.githubusercontent.com/dmitry-baranov/harnes-agent-install/main/install.sh | sh
```

The script installs Node.js 22 locally if Node 22+ is absent, OpenCode V2.3.2 side-by-side if needed, and a checksum-pinned standalone Harnes Agent 0.1.6. It upgrades an existing 0.1.0–0.1.5 installation while keeping a local backup and restarting its primary user service if already running. It locally authorizes the current user's home directory and everything beneath it; after enrollment, a ready-to-use **Home** workspace appears on the site without entering paths. Browse into a project from the site to start a session there; the agent stores project paths locally and the server stores only opaque identifiers. If the computer is already paired with a different server, the same `harnes-agent enroll --server https://new-server` command creates a separate local identity and user service. Other directories still require explicit local approval. It does not sign in, change OpenCode permissions or connect to a server automatically unless `HARNES_SERVER` is set. It never sends local credentials or an absolute home path to the server. Inspect [install.sh](install.sh) before running it. Running the command again with the same version is supported.

Version 0.1.6 enables the chat's `/compact`, `/model` and locally defined OpenCode slash commands. The web UI also offers `/session` to switch or start sessions. Commands run only through the device's local OpenCode V2 service and require the usual owner authorization.

## Install and pair in one command (fish)

Generate a pairing code on the VPN-only Harnes Devices page, then run on the new computer:

```fish
env HARNES_SERVER=https://harnes.185.164.173.65.sslip.io:8444 sh -c (curl -fsSL https://raw.githubusercontent.com/dmitry-baranov/harnes-agent-install/main/install.sh)
```

Enter the code and type `ENROLL` locally. Verify the fingerprint and approve on the website using a passkey. On the source Mac, first run `harnes-agent auth share enable --server https://harnes.185.164.173.65.sslip.io:8444` to authorize exactly one export, then select that Mac in the approval form. The source agent encrypts the current `personal` and `world` auth profiles to the new computer; the server briefly relays ciphertext in memory, and the new device activates `personal` only if no existing auth files are present. No provider keys are in this repository or on the server's disk. If you opt out, sign in to OpenCode locally instead.

## Finish setup locally

```fish
if test -x "$HOME/.local/opt/harnes-node22/bin/node"; fish_add_path -U "$HOME/.local/opt/harnes-node22/bin"; end
fish_add_path -U "$HOME/.local/bin"
$HOME/.local/opt/harnes-opencode-v2/bin/opencode2 --version
# Only if you chose not to copy auth during device approval:
$HOME/.local/opt/harnes-opencode-v2/bin/opencode2 auth login openai
harnes-agent doctor
# Home and projects inside it are already allowed. For paths outside home only:
# harnes-agent workspace add /absolute/path/to/your/project
```

If you already have a separate V2 executable, set `OPENCODE_V2_BIN` to its absolute path before installing and in your fish config for future shells. The first command above adds locally installed Node.js to the fish path when applicable.

On the Harnes site, generate a device code at `/devices`. Then on **this computer**:

```fish
harnes-agent enroll --server https://your-harnes-domain
# Confirm ENROLL locally and approve the fingerprint on the site.
harnes-agent resume
```

Start the installed user service only after enrollment: macOS: `launchctl bootstrap gui/(id -u) "$HOME/Library/LaunchAgents/com.harnes.agent.plist"`; Linux: `systemctl --user daemon-reload; and systemctl --user enable --now harnes-agent`. Enable remote execution on the site separately. `harnes-agent profile apply` is optional: it grants OpenCode broad read/write/shell permissions for your OS user, backs up existing configuration and may require a local OpenCode restart. The agent still validates every requested workspace against locally authorized roots.
The Home workspace works without adding a directory in the site. For other folders under home, type their absolute path into Workspaces; for folders outside home, run `harnes-agent workspace add` locally first.

The control plane needs a reachable HTTPS deployment; its development Compose binds only to localhost. For server setup and architecture see [Harnes Remote](https://github.com/dmitry-baranov/harnes-remote) (repository access required).

## Optional personal harness configuration (macOS and Linux)

The installer now attempts to provision the private `agents` repository (harness-config) at `~/projects/harness-config` using existing authenticated Git access. Git is optional: if Git or private-repository access is missing, or local configuration conflicts, the agent still installs and pairing continues. No GitHub token is requested, embedded, relayed through the VPS or copied into configuration. Do not place credentials in clone URLs.

Default profile: `personal`. Set `HARNES_CONFIG_PROFILE=backend`, `ml-research` or `devops` before running the installer to select a different profile. Set `HARNES_CONFIG=off` to skip this step. The checkout is pinned to a reviewed candidate commit in `refactor/harness-config`; existing checkouts are not reset or switched. The installer uses the pinned revision, not local edits. The temporary archive is removed on exit.

Only global AGENTS.md and selected skills are installed into OpenCode's standard user config paths. The native OpenCode JSON/JSONC, provider login, permission settings, remote enrollment and existing full-access profile are not changed by this optional step. Existing unmanaged files and symlinks are not overwritten. Restart the V2 service when safe to load updated capabilities; the installer does not restart an unrelated existing OpenCode service.

If the private repo is unavailable, authenticate GitHub locally (e.g. `gh auth login` if installed), then rerun the installer. If there is a conflict, inspect local configuration and use the harness-config migration guide; never blindly use --replace. The existing remote pairing process is unchanged.

This integration is a candidate for testing before merging to main; the pinned revision is in a development branch. Real macOS/Linux installation and V2 skill discovery must be verified.
