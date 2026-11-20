#!/bin/sh
# Installs only for the current user. The agent archive is pinned to a tested release.
set -eu

release='v0.1.0'
archive='harnes-agent-0.1.0-2026-11-20T22-37-21-865Z.tar.gz'
archive_sha='0d268cad799103ecb6f7516043723139c2355ec40eed48135865fb6dbaedf625'
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
trap 'rm -rf "$work"' EXIT HUP INT TERM

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
if [ -e "$agent_dir" ] || [ -L "$agent_dir" ]; then
  [ -f "$agent_dir/dist/index.js" ] || fail "$agent_dir already exists but is not a valid agent installation"
  [ "$(node "$agent_dir/dist/index.js" --version)" = '0.1.0' ] || fail 'An existing agent has a different version; upgrade it manually'
else
  fetch "$url" "$work/agent.tar.gz"
  [ "$(checksum "$work/agent.tar.gz")" = "$archive_sha" ] || fail 'Agent archive checksum mismatch'
  tar -xzf "$work/agent.tar.gz" -C "$work"
  [ -f "$work/harnes-agent/dist/index.js" ] || fail 'Agent archive is incomplete'
  mv "$work/harnes-agent" "$agent_dir"
fi
node "$agent_dir/dist/index.js" install
printf '\nInstalled Harnes Agent %s and OpenCode V2 for this user.\n' "$(node "$agent_dir/dist/index.js" --version)"
printf 'Run: %s/bin/harnes-agent doctor\n' "$local_dir"
if [ -x "$node_dir/bin/node" ]; then printf 'If needed, add %s/bin to your shell PATH.\n' "$node_dir"; fi
printf 'Next: log in to your provider locally, then enroll with your HTTPS Harnes server. See README.\n'
