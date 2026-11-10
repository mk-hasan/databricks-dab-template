#!/usr/bin/env bash
# Log in is the caller's job (Azure CLI must already be authenticated).
# Usage: TARGET=dev bash devops-pipeline/scripts/run_bundle.sh validate|deploy
#
# Same host and auth rules as devops-pipeline/templates/deploy-stage.yml.
# CLI 0.295 inside a bundle folder ignores DATABRICKS_HOST for non-bundle
# commands, so current-user uses --target. Do not pass --host.
set -euo pipefail

TARGET="${TARGET:?TARGET is required (dev, test, or prod)}"
ACTION="${1:?usage: run_bundle.sh validate|deploy}"

chmod +x devops-pipeline/scripts/read_bundle_yml.sh
chmod +x devops-pipeline/scripts/ensure_team_folder_acl.sh

if [[ -z "${DATABRICKS_CLI_BIN:-}" ]]; then
  for candidate in \
    "${RUNNER_TEMP:-}/databricks-cli-bin" \
    "${WORKSPACE:-}/.databricks-cli-bin" \
    "/tmp/databricks-cli-bin"
  do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      export PATH="$(cat "$candidate"):$PATH"
      break
    fi
  done
else
  export PATH="${DATABRICKS_CLI_BIN}:$PATH"
fi

export DATABRICKS_HOST="$(BUNDLE_ROOT="$(pwd)" BUNDLE_TARGET="$TARGET" \
  bash devops-pipeline/scripts/read_bundle_yml.sh host)"
export DATABRICKS_AUTH_TYPE=azure-cli
echo "DATABRICKS_HOST=${DATABRICKS_HOST} (target=${TARGET})"

databricks --target "$TARGET" current-user me

case "$ACTION" in
  validate)
    databricks bundle validate -t "$TARGET"
    ;;
  deploy)
    python3 -m pip install --upgrade build setuptools wheel
    BUNDLE_ROOT="$(pwd)" \
      BUNDLE_TARGET="$TARGET" \
      TEAM_NAME="${TEAM_NAME:-}" \
      TEAM_GROUP="${TEAM_GROUP:-}" \
      DEPLOY_SP="${DEPLOY_SP:-}" \
      bash devops-pipeline/scripts/ensure_team_folder_acl.sh
    databricks bundle validate -t "$TARGET"
    databricks bundle deploy -t "$TARGET"
    ;;
  *)
    echo "usage: run_bundle.sh validate|deploy" >&2
    exit 1
    ;;
esac
