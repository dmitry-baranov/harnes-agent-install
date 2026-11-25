#!/bin/sh
# Installs only for the current user. The agent archive is pinned to a tested release.
set -eu

release='v0.1.6'
archive='harnes-agent-0.1.6-2026-11-21T08-12-36-325Z.tar.gz'
archive_sha='4c64725dcc957e1b9e2bff7ac0b0806f896024abc036a4b99d514ea9721154d1'
url="https://github.com/dmitry-baranov/harnes-agent-install/releases/download/$release/$archive"

fail() { printf 'Harnes installer: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || fail 'curl is required'
command -v tar >/dev/null 2>&1 || fail 'tar is required'
[ -n "${HOME:-}" ] && [ -d "$HOME" ] || fail 'HOME must point to your home directory'
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail 'Only macOS and Linux are supported' ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x64 ;;
  *) fail 'Only x64 and arm64 are supported' ;;
esac

checksum() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1
  else fail 'shasum or sha256sum is required'; fi
}
fetch() { curl -fLSs --retry 3 -o "$2" "$1"; }
local_dir="$HOME/.local"
mkdir -p "$local_dir/opt" "$local_dir/share"
work=$(mktemp -d "$local_dir/.harnes-install.XXXXXXXX")
trap 'code=$?; if [ "$code" -ne 0 ] && [ -n "${backup:-}" ] && [ -d "$backup" ]; then printf "Upgrade interrupted; previous agent preserved at %s. Check the user service before retrying.\n" "$backup" >&2; fi; rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

# Use an existing compatible Node; otherwise install an official Node 22 archive locally.
node_ok=0
if command -v node >/dev/null 2>&1; then
  major=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || true)
  if [ "${major:-0}" -ge 22 ] 2>/dev/null; then node_ok=1; fi
fi
node_dir="$local_dir/opt/harnes-node22"
if [ "$node_ok" -ne 1 ]; then
  if [ ! -x "$node_dir/bin/node" ]; then
    [ ! -e "$node_dir" ] || fail "$node_dir already exists but has no usable Node"
    fetch https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt "$work/SHASUMS256.txt"
    file=$(awk -v platform="$os-$arch" '$2 ~ ("^node-v[0-9.]+-" platform "\\.tar\\.gz$") {print $2; exit}' "$work/SHASUMS256.txt")
    [ -n "$file" ] || fail "No official Node 22 archive for $os-$arch"
    expected=$(awk -v name="$file" '$2 == name {print $1; exit}' "$work/SHASUMS256.txt")
    fetch "https://nodejs.org/dist/latest-v22.x/$file" "$work/node.tar.gz"
    [ "$(checksum "$work/node.tar.gz")" = "$expected" ] || fail 'Node.js checksum mismatch'
    mkdir "$work/node"
    tar -xzf "$work/node.tar.gz" -C "$work/node" --strip-components=1
    "$work/node/bin/node" --version >/dev/null
    mv "$work/node" "$node_dir"
  fi
  PATH="$node_dir/bin:$PATH"
  export PATH
fi

# V2 is installed side-by-side; the existing global OpenCode (possibly V1) is untouched.
opencode_dir="$local_dir/opt/harnes-opencode-v2"
if [ -n "${OPENCODE_V2_BIN:-}" ]; then
  "$OPENCODE_V2_BIN" --version | awk '/v2\.|^2\./ {ok=1} END {exit !ok}' || fail 'OPENCODE_V2_BIN must point to OpenCode V2'
elif [ -e "$opencode_dir" ]; then
  [ -x "$opencode_dir/bin/opencode2" ] || fail "$opencode_dir already exists but is incomplete"
  "$opencode_dir/bin/opencode2" --version | awk '/v2\.|^2\./ {ok=1} END {exit !ok}' || fail 'Existing side-by-side OpenCode is not V2'
else
  command -v npm >/dev/null 2>&1 || fail 'npm is required to install OpenCode V2'
  npm install --prefix "$work/opencode" --no-audit --no-fund @opencode/cli@2.3.2
  mkdir -p "$work/opencode/bin"
  ln -s ../node_modules/.bin/opencode2 "$work/opencode/bin/opencode2"
  "$work/opencode/bin/opencode2" --version | awk '/v2\.|^2\./ {ok=1} END {exit !ok}' || fail 'OpenCode V2 installation failed'
  mv "$work/opencode" "$opencode_dir"
fi

agent_dir="$local_dir/share/harnes-agent"
old_version=''
if [ -e "$agent_dir" ] || [ -L "$agent_dir" ]; then
  [ -f "$agent_dir/dist/index.js" ] || fail "$agent_dir already exists but is not a valid agent installation"
  old_version=$(node "$agent_dir/dist/index.js" --version)
  case "$old_version" in 0.1.0|0.1.1|0.1.2|0.1.3|0.1.4|0.1.5|0.1.6) ;; *) fail 'An existing agent has a different version; upgrade it manually' ;; esac
fi
if [ "$old_version" != '0.1.6' ]; then
  fetch "$url" "$work/agent.tar.gz"
  [ "$(checksum "$work/agent.tar.gz")" = "$archive_sha" ] || fail 'Agent archive checksum mismatch'
  tar -xzf "$work/agent.tar.gz" -C "$work"
  [ -f "$work/harnes-agent/dist/index.js" ] || fail 'Agent archive is incomplete'
  [ "$(node "$work/harnes-agent/dist/index.js" --version)" = '0.1.6' ] || fail 'Unexpected agent version in archive'
  was_running=0
  if [ -n "$old_version" ]; then
    backup="$local_dir/share/harnes-agent.previous-$old_version"
    [ ! -e "$backup" ] || fail "Backup $backup exists; preserve it before upgrading"
    if [ "$os" = darwin ] && launchctl print "gui/$(id -u)/com.harnes.agent" >/dev/null 2>&1; then
      launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.harnes.agent.plist"
      was_running=1
    elif [ "$os" = linux ] && command -v systemctl >/dev/null 2>&1 && systemctl --user is-active --quiet harnes-agent; then
      systemctl --user stop harnes-agent
      was_running=1
    fi
    mv "$agent_dir" "$backup"
  fi
  mv "$work/harnes-agent" "$agent_dir"
fi

install_harness_config() {
  case "${HARNES_CONFIG:-auto}" in
    off) printf 'Harness configuration disabled by HARNES_CONFIG=off.\n'; return 0 ;;
    auto) ;;
    *) printf 'Invalid HARNES_CONFIG; expected auto or off. Skipping configuration.\n' >&2; return 1 ;;
  esac
  if ! command -v git >/dev/null 2>&1; then
    printf 'Git is not installed; skipping optional private harness configuration.\n' >&2
    return 1
  fi
  config_repo='https://github.com/dmitry-baranov/agents.git'
  config_branch='refactor/harness-config'
  config_revision='2293a8144adcbb51a36edf7643e0cb385e761031'
  config_target="$HOME/projects/harness-config"
  config_profile="${HARNES_CONFIG_PROFILE:-personal}"
  case "$config_profile" in
    personal|backend|ml-research|devops) ;;
    *) printf 'Unsupported remote harness profile: %s\n' "$config_profile" >&2; return 1 ;;
  esac
  if [ -e "$config_target" ] || [ -L "$config_target" ]; then
    if [ -L "$config_target" ] || [ ! -d "$config_target/.git" ]; then
      printf 'Existing harness path is not a regular Git checkout; left untouched: %s\n' "$config_target" >&2
      return 1
    fi
    config_origin=$(git -C "$config_target" remote get-url origin 2>/dev/null) || return 1
    case "$config_origin" in
      "$config_repo"|git@github.com:dmitry-baranov/agents.git|ssh://git@github.com/dmitry-baranov/agents.git) ;;
      *) printf 'Existing harness origin differs from the expected repository; left untouched.\n' >&2; return 1 ;;
    esac
    if ! git -C "$config_target" cat-file -e "$config_revision^{commit}" 2>/dev/null; then
      GIT_TERMINAL_PROMPT=0 git -C "$config_target" fetch --no-tags origin "$config_branch" || return 1
    fi
  else
    mkdir -p "$HOME/projects" || return 1
    printf 'Fetching optional private harness configuration (existing Git credentials required).\n'
    GIT_TERMINAL_PROMPT=0 git clone --no-checkout --branch "$config_branch" "$config_repo" "$work/harness-checkout" || return 1
    git -C "$work/harness-checkout" checkout --detach "$config_revision" || return 1
    [ ! -e "$config_target" ] && [ ! -L "$config_target" ] || return 1
    mv "$work/harness-checkout" "$config_target" || return 1
  fi
  # Render from the pinned Git commit, not from potentially modified checkout files.
  git -C "$config_target" archive --format=tar "$config_revision" > "$work/harness-config.tar" || return 1
  mkdir "$work/harness-source" || return 1
  tar -xf "$work/harness-config.tar" -C "$work/harness-source" || return 1
  config_cli="$work/harness-source/harness/scripts/harness.mjs"
  [ -f "$config_cli" ] || return 1
  node "$config_cli" plan --runtime opencode --profile "$config_profile" --capabilities-only || return 1
  node "$config_cli" sync --runtime opencode --profile "$config_profile" --capabilities-only || return 1
  printf 'Harness capabilities installed (%s); checkout: %s\n' "$config_profile" "$config_target"
  printf 'Existing OpenCode sessions/services may need a restart to load the new instructions and skills.\n'
}

node "$agent_dir/dist/index.js" install
if ! install_harness_config; then
  printf 'Optional harness configuration was not applied; the device agent installation continues.\n' >&2
  printf 'Authenticate GitHub and review configuration conflicts before retrying; no --replace is used.\n' >&2
fi
if [ "${was_running:-0}" -eq 1 ]; then
  if [ "$os" = darwin ]; then launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.harnes.agent.plist"
  else systemctl --user daemon-reload && systemctl --user start harnes-agent; fi
fi
printf '\nInstalled Harnes Agent %s and OpenCode V2 for this user.\n' "$(node "$agent_dir/dist/index.js" --version)"
printf 'Run: %s/bin/harnes-agent doctor\n' "$local_dir"
if [ -x "$node_dir/bin/node" ]; then printf 'If needed, add %s/bin to your shell PATH.\n' "$node_dir"; fi
printf 'Home is locally approved. Once enrolled, a Home workspace appears on the site.\n'
if [ -n "${HARNES_SERVER:-}" ]; then
  [ -t 0 ] || fail 'Interactive pairing needs a terminal. Use sh -c "$(curl -fsSL URL)" instead of curl | sh.'
  node "$agent_dir/dist/index.js" enroll --server "$HARNES_SERVER"
  # A second-server enrollment starts its own service inside the agent.
  if [ "$os" = darwin ]; then
    if ! launchctl print "gui/$(id -u)/com.harnes.agent" >/dev/null 2>&1; then
      launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.harnes.agent.plist" || fail 'Enrolled; start the primary user service manually'
    fi
  elif command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload && systemctl --user enable --now harnes-agent || fail 'Enrolled; start the primary user service manually'
  fi
  printf 'Pairing complete. If auth was shared during approval, personal and world profiles are now installed.\n'
else
  printf 'Next: generate a pairing code on your Harnes site, then enroll with harnes-agent enroll --server https://your-server.\n'
fi
