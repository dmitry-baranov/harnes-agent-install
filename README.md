# Harnes Agent — install on a new computer

Public installer for the device agent from the private [Harnes Remote](https://github.com/dmitry-baranov/harnes-remote) control-plane repository. Supports macOS and Linux (x64/arm64). Requires `curl`, `tar`, a SHA-256 utility and internet access. No Git checkout, Docker, admin privileges or pnpm required.

**One command** in fish or a POSIX shell:

```fish
curl -fsSL https://raw.githubusercontent.com/dmitry-baranov/harnes-agent-install/main/install.sh | sh
```

The script installs Node.js 22 locally if Node 22+ is absent, OpenCode V2.3.2 side-by-side if needed, and a checksum-pinned standalone Harnes Agent 0.1.7. It upgrades an existing 0.1.0–0.1.6 installation while keeping a local backup and restarting its primary user service if already running. It locally authorizes the current user's home directory and everything beneath it; after enrollment, a ready-to-use **Home** workspace appears on the site without entering paths. Browse into a project from the site to start a session there; the agent stores project paths locally and the server stores only opaque identifiers. If the computer is already paired with a different server, the same `harnes-agent enroll --server https://new-server` command creates a separate local identity and user service. Other directories still require explicit local approval. The installer does not sign in or change OpenCode permissions. Rerunning it for an already paired server preserves the existing identity and local execution setting. Inspect [install.sh](install.sh) before running it.

Version 0.1.6 enables the chat's `/compact`, `/model` and locally defined OpenCode slash commands. The web UI also offers `/session` to switch or start sessions. Commands run only through the device's local OpenCode V2 service and require the usual owner authorization.

## Install and pair in one command (zsh, bash or fish)

Generate a pairing code on the VPN-only Harnes Devices page, then run on the new computer:

```fish
env HARNES_SERVER=https://harnes.185.164.173.65.sslip.io:8444 sh -c 'installer=$(curl -fsSL https://raw.githubusercontent.com/dmitry-baranov/harnes-agent-install/main/install.sh) && [ -n "$installer" ] && exec sh -c "$installer"'
```

Enter the code and type `ENROLL` locally to allow remote prompts. Verify the fingerprint and choose **Approve and enable chat** using a passkey, or approve with execution paused. Follow the new chat link; **Home** is selected when the agent connects. For optional credential transfer, first run `harnes-agent auth share enable --server https://harnes.185.164.173.65.sslip.io:8444` on the source computer to authorize exactly one export, then select it in the approval form. The source encrypts the current `personal` and `world` auth profiles to the new computer; the server briefly relays ciphertext in memory, and the new device activates `personal` only if no existing auth files are present. If you opt out, sign in to OpenCode locally instead.

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

## Optional private harness configuration

The configuration repository (`dmitry-baranov/harness-config`) remains private. If the operator has enabled the optional GitHub App integration, agent 0.1.7+ can sync the pinned capabilities after enrollment and an authenticated HTTPS device connection. It preserves existing OpenCode settings and does not require a GitHub login or personal token on the new device. If the integration is disabled, ordinary chat setup still works.
