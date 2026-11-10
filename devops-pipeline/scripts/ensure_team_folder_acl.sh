#!/usr/bin/env bash
# Ensure /Workspace/Teams/<team_name> exists and has ACL for:
#   - deploy Databricks group (CAN_MANAGE) — preferred; put all CD SPs in this group
#   - optional single DEPLOY_SP (CAN_MANAGE) — only if you do not use a deploy group
#   - team Databricks group (CAN_READ by default) — human users
#
# Env (optional — falls back to databricks.yml when BUNDLE_ROOT is set):
#   BUNDLE_TARGET — dev | test | prod (reads targets.<target>.variables.*)
#   TEAM_NAME, TEAM_GROUP, DEPLOY_GROUP, DEPLOY_SP, TEAM_GROUP_LEVEL, BUNDLE_ROOT
#
# Requires: databricks CLI authenticated (e.g. DATABRICKS_AUTH_TYPE=azure-cli)
#
# Inside a DAB folder, non-bundle CLI (current-user / workspace / permissions) ignore
# DATABRICKS_HOST and use the default target. CLI 0.295.x has no --host — use --target.
set -euo pipefail

BUNDLE_ROOT="${BUNDLE_ROOT:-.}"
BUNDLE_TARGET="${BUNDLE_TARGET:-}"
TEAM_GROUP_LEVEL="${TEAM_GROUP_LEVEL:-CAN_READ}"
DEPLOY_GROUP_LEVEL="${DEPLOY_GROUP_LEVEL:-CAN_MANAGE}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dbx() {
  : "${BUNDLE_TARGET:?BUNDLE_TARGET must be set (dev|test|prod) before ACL operations}"
  (cd "${BUNDLE_ROOT}" && databricks --target "${BUNDLE_TARGET}" "$@")
}

read_yml_var() {
  bash "${SCRIPT_DIR}/read_bundle_yml.sh" var "$1"
}

strip_quotes() {
  local v="$1"
  v="${v%\"}"
  v="${v#\"}"
  v="${v%\'}"
  v="${v#\'}"
  echo "$v"
}

TEAM_NAME="$(strip_quotes "${TEAM_NAME:-$(read_yml_var team_name)}")"
TEAM_GROUP="$(strip_quotes "${TEAM_GROUP:-$(read_yml_var team_group)}")"
DEPLOY_GROUP="$(strip_quotes "${DEPLOY_GROUP:-$(read_yml_var deploy_group)}")"
DEPLOY_SP="$(strip_quotes "${DEPLOY_SP:-$(read_yml_var deploy_sp)}")"

if [[ -n "${BUNDLE_TARGET}" ]]; then
  echo "Using databricks.yml target: ${BUNDLE_TARGET} (deploy_group=${DEPLOY_GROUP})"
fi
if [[ -n "${DATABRICKS_HOST:-}" ]]; then
  echo "DATABRICKS_HOST=${DATABRICKS_HOST}"
fi

if [[ -z "${TEAM_NAME}" ]]; then
  echo "TEAM_NAME is required (env or databricks.yml variables.team_name.default)" >&2
  exit 1
fi

TEAM_PATH="/Workspace/Teams/${TEAM_NAME}"
echo "Ensuring team folder: ${TEAM_PATH}"

# Parent /Workspace/Teams must already exist; deploy identity needs rights on it.
dbx workspace mkdirs "${TEAM_PATH}"

STATUS_JSON="$(dbx workspace get-status "${TEAM_PATH}" -o json)"
OBJECT_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["object_id"])' <<<"${STATUS_JSON}")"
echo "Directory object_id=${OBJECT_ID}"

# Optional single-SP fallback when no deploy group is configured
if [[ -z "${DEPLOY_GROUP}" && -z "${DEPLOY_SP}" ]]; then
  if command -v az >/dev/null 2>&1; then
    DEPLOY_SP="$(az account show --query user.name -o tsv 2>/dev/null || true)"
    USER_TYPE="$(az account show --query user.type -o tsv 2>/dev/null || true)"
    if [[ "${USER_TYPE}" != "servicePrincipal" ]]; then
      DEPLOY_SP=""
    fi
  fi
fi

if [[ -z "${DEPLOY_GROUP}" && -z "${DEPLOY_SP}" ]]; then
  echo "Set deploy_group (recommended, e.g. dbx-deploy-dev) or deploy_sp." >&2
  exit 1
fi

ACL_JSON="$(
  DEPLOY_GROUP="${DEPLOY_GROUP}" \
  DEPLOY_GROUP_LEVEL="${DEPLOY_GROUP_LEVEL}" \
  DEPLOY_SP="${DEPLOY_SP}" \
  TEAM_GROUP="${TEAM_GROUP}" \
  TEAM_GROUP_LEVEL="${TEAM_GROUP_LEVEL}" \
  python3 - <<'PY'
import json, os, sys

acl = []
deploy_group = (os.environ.get("DEPLOY_GROUP") or "").strip()
deploy_sp = (os.environ.get("DEPLOY_SP") or "").strip()
team_group = (os.environ.get("TEAM_GROUP") or "").strip()
deploy_level = os.environ.get("DEPLOY_GROUP_LEVEL") or "CAN_MANAGE"
team_level = os.environ.get("TEAM_GROUP_LEVEL") or "CAN_READ"

if deploy_group:
    if deploy_group.lower() == "users":
        print("Refusing DEPLOY_GROUP=users", file=sys.stderr)
        raise SystemExit(1)
    acl.append({"group_name": deploy_group, "permission_level": deploy_level})
    print(f"Grant {deploy_level} to deploy group: {deploy_group}", file=sys.stderr)

if deploy_sp:
    acl.append({"service_principal_name": deploy_sp, "permission_level": "CAN_MANAGE"})
    print(f"Grant CAN_MANAGE to deploy SP: {deploy_sp}", file=sys.stderr)

if team_group and team_group.lower() != "users":
    if team_group != deploy_group:
        acl.append({"group_name": team_group, "permission_level": team_level})
        print(f"Grant {team_level} to team group: {team_group}", file=sys.stderr)
elif team_group.lower() == "users":
    print(
        "Skipping TEAM_GROUP=users (would open folder to all workspace users).",
        file=sys.stderr,
    )

if not acl:
    print("No ACL entries to apply.", file=sys.stderr)
    raise SystemExit(1)

print(json.dumps({"access_control_list": acl}))
PY
)"

echo "Updating directory permissions with:"
echo "${ACL_JSON}"

dbx permissions update directories "${OBJECT_ID}" --json "${ACL_JSON}"

echo "Team folder ACL ready: ${TEAM_PATH}"
