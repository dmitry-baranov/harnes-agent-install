# Harnes Agent — install on a new computer

Public installer for the device agent from the private [Harnes Remote](https://github.com/dmitry-baranov/harnes-remote) control-plane repository. Supports macOS and Linux (x64/arm64). Requires `curl`, `tar`, a SHA-256 utility and internet access. No Git checkout, Docker, admin privileges or pnpm required.

**One command** in fish or a POSIX shell:

```fish
curl -fsSL https://raw.githubusercontent.com/dmitry-baranov/harnes-agent-install/v0.1.2/install.sh | sh
```

The script installs Node.js 22 locally if Node 22+ is absent, OpenCode V2.3.2 side-by-side if needed, and a checksum-pinned standalone Harnes Agent. It upgrades an existing 0.1.0/0.1.1 installation while keeping a local backup and restarting its user service if already running. It locally authorizes the current user's home directory and everything beneath it; after enrollment, a ready-to-use **Home** workspace appears on the site without entering paths. Browse into a project from the site to start a session there; other directories still require explicit local approval. It does not sign in, change OpenCode permissions or connect to a server automatically. It never sends local credentials or an absolute home path to the server. Inspect [install.sh](install.sh) before running it. Running the command again with the same version is supported.

## Finish setup locally

```fish
if test -x "$HOME/.local/opt/harnes-node22/bin/node"; fish_add_path -U "$HOME/.local/opt/harnes-node22/bin"; end
fish_add_path -U "$HOME/.local/bin"
$HOME/.local/opt/harnes-opencode-v2/bin/opencode2 --version
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
