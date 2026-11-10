#!/usr/bin/env bash
# Read values from the bundle config for a target.
#
# Usage:
#   BUNDLE_ROOT=. BUNDLE_TARGET=dev bash read_bundle_yml.sh host
#   BUNDLE_ROOT=. BUNDLE_TARGET=dev bash read_bundle_yml.sh var deploy_group
#   BUNDLE_ROOT=. bash read_bundle_yml.sh var team_name
#
# Reads databricks.yml, config/platform.yml, and config/project.yml.
# Target values in config/platform.yml win over the same key in config/project.yml
# when both define it. Team values are expected only in config/project.yml.
#
# Env:
#   BUNDLE_ROOT   — directory containing databricks.yml (default: .)
#   BUNDLE_TARGET — dev | test | prod (optional; required for host / target variables)
set -euo pipefail

BUNDLE_ROOT="${BUNDLE_ROOT:-.}"
BUNDLE_TARGET="${BUNDLE_TARGET:-}"
KIND="${1:?usage: read_bundle_yml.sh host | var <name>}"
VAR_NAME="${2:-}"

if [[ ! -f "${BUNDLE_ROOT}/databricks.yml" ]]; then
  echo "databricks.yml not found under BUNDLE_ROOT=${BUNDLE_ROOT}" >&2
  exit 1
fi

if [[ "$KIND" == "host" && -z "$BUNDLE_TARGET" ]]; then
  echo "BUNDLE_TARGET is required to read workspace host" >&2
  exit 1
fi

if [[ "$KIND" == "var" && -z "$VAR_NAME" ]]; then
  echo "usage: read_bundle_yml.sh var <name>" >&2
  exit 1
fi

python3 - "$BUNDLE_ROOT" "$KIND" "$BUNDLE_TARGET" "$VAR_NAME" <<'PY'
import re, sys
from pathlib import Path

root, kind, target, var_name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
root = Path(root)

# platform first so workspace hosts and deploy groups win over a fork's project file
names = ["config/platform.yml", "config/project.yml", "databricks.yml"]
files = []
for name in names:
    path = root / name
    if path.is_file():
        text = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
        files.append((name, text))

if not files:
    print("no bundle config files found", file=sys.stderr)
    raise SystemExit(1)


def target_block(text: str, name: str):
    m = re.search(
        rf"(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z_]|\Z)",
        text,
    )
    return m.group(1) if m else None


if kind == "host":
    for name, text in files:
        block = target_block(text, target)
        if not block:
            continue
        m = re.search(
            r"(?m)^      host:\s*[\"']?([^\"'\n#]+)[\"']?",
            block,
        )
        if m:
            print(m.group(1).strip())
            raise SystemExit(0)
    print(f"workspace.host not found for target {target!r}", file=sys.stderr)
    raise SystemExit(1)

if kind != "var":
    print(f"unknown kind: {kind}", file=sys.stderr)
    raise SystemExit(1)

if target:
    for name, text in files:
        block = target_block(text, target)
        if not block:
            continue
        vm = re.search(
            r"(?ms)^    variables:\n(.*?)(?=^    \S|^  [A-Za-z_]|\Z)",
            block,
        )
        if not vm:
            continue
        km = re.search(
            rf"^\s*{re.escape(var_name)}:\s*[\"']?([^\"'\n#]*)[\"']?",
            vm.group(1),
            re.M,
        )
        if km:
            print(km.group(1).strip())
            raise SystemExit(0)

for name, text in files:
    m = re.search(
        rf"(?m)^  {re.escape(var_name)}:\s*\n(?:.*\n)*?    default:\s*[\"']?([^\"'\n#]*)[\"']?",
        text,
    )
    if m:
        print(m.group(1).strip())
        raise SystemExit(0)

print("")
PY
