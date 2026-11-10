#!/usr/bin/env bash
# Fail a fork when required project values are still placeholders.
# The template repo sets BLOCKING=false and skips those checks.
# VERSION must always match presets.tags.template_version.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BUNDLE_ROOT="${BUNDLE_ROOT:-$ROOT}"
export BLOCKING="${BLOCKING:-false}"

python3 - <<'PY'
import os, re, sys
from pathlib import Path

root = Path(os.environ["BUNDLE_ROOT"])
blocking = os.environ.get("BLOCKING", "false").strip().lower() in {"1", "true", "yes"}
errors = []
warnings = []

def read(path: Path) -> str:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")

def var_default(text, name):
    m = re.search(
        rf"(?m)^  {re.escape(name)}:\s*\n(?:[ \t]+.*\n)*?[ \t]+default:\s*[\"']?([^\"'\n#]*)[\"']?",
        text,
    )
    return m.group(1).strip() if m else None

project = read(root / "config" / "project.yml")
cost_center = var_default(project, "cost_center_id")
purpose = var_default(project, "purpose")
team_group = var_default(project, "team_group")

placeholder_problems = []
if cost_center == "YOUR-COST-CENTER-ID":
    placeholder_problems.append("config/project.yml cost_center_id is still YOUR-COST-CENTER-ID")
if purpose == "template":
    placeholder_problems.append('config/project.yml purpose is still "template"')
if team_group is None or team_group == "" or team_group.lower() == "users":
    placeholder_problems.append("config/project.yml team_group is empty or users")

if placeholder_problems:
    if blocking:
        errors.extend(placeholder_problems)
    else:
        warnings.extend(placeholder_problems)

version = (root / "VERSION").read_text(encoding="utf-8").strip()
bundle = read(root / "databricks.yml")
tag = re.search(r'(?m)^    template_version:\s*["\']?([^"\'\n#]+)["\']?', bundle)
if not tag or tag.group(1).strip() != version:
    found = tag.group(1).strip() if tag else "<missing>"
    errors.append(f"VERSION ({version}) and databricks.yml template_version ({found}) differ")

for line in warnings:
    print(f"WARNING: {line}")
    print("##vso[task.logissue type=warning]" + line)
if warnings and not blocking:
    print("Placeholder checks are skipped because blocking is false. Forks set blocking to true.")

for line in errors:
    print(f"ERROR: {line}", file=sys.stderr)
    print("##vso[task.logissue type=error]" + line)

if errors:
    raise SystemExit(1)
print("Fork config check passed.")
PY
