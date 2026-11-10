#!/usr/bin/env bash
# Install the pinned Databricks CLI onto PATH for this job.
# Version: DATABRICKS_CLI_VERSION (for example 0.295.1).
set -euo pipefail

VER="${DATABRICKS_CLI_VERSION:?DATABRICKS_CLI_VERSION is required}"
TAG="v${VER#v}"
VER_NUM="${VER#v}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) A="amd64" ;;
  aarch64) A="arm64" ;;
  *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

ROOT="${AGENT_TOOLSDIRECTORY:-/azp/_work/_tool}"
BIN="$ROOT/databricks-cli/$TAG/bin"

mkdir -p "$BIN"

curl -fL \
  "https://github.com/databricks/cli/releases/download/$TAG/databricks_cli_${VER_NUM}_linux_${A}.tar.gz" \
  -o cli.tgz

tar -xzf cli.tgz
mv databricks "$BIN/databricks"
chmod +x "$BIN/databricks"
rm -f cli.tgz

# Azure DevOps: later steps see this directory on PATH.
echo "##vso[task.prependpath]$BIN"
# GitHub Actions: later steps see this directory on PATH.
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$BIN" >> "$GITHUB_PATH"
fi
# Jenkins and other callers: read this path in the same job.
if [[ -n "${RUNNER_TEMP:-}" ]]; then
  PATH_FILE="$RUNNER_TEMP/databricks-cli-bin"
elif [[ -n "${WORKSPACE:-}" ]]; then
  PATH_FILE="$WORKSPACE/.databricks-cli-bin"
else
  PATH_FILE="/tmp/databricks-cli-bin"
fi
echo "$BIN" > "$PATH_FILE"
echo "DATABRICKS_CLI_BIN=$BIN"
"$BIN/databricks" version
