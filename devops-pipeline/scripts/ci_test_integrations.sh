#!/usr/bin/env bash
# Run tests for each package under src/ (except common).
# BLOCKING=true fails the build on test failures. The template repo leaves it false.
set -euo pipefail

BLOCKING="${BLOCKING:-false}"
fail=0

python -m pip install --upgrade pip
pip install pytest
if [[ -f tests/requirements.txt ]]; then
  pip install -r tests/requirements.txt
fi
pip install .

run_tests() {
  local name="$1"
  local test_dir="tests/${name}"
  if [[ ! -d "$test_dir" ]]; then
    echo "No ${test_dir} — skipped"
    return 0
  fi
  echo "Testing ${name}"
  if ! pytest "$test_dir" -q; then
    echo "##vso[task.logissue type=warning]Tests failed for ${name}"
    fail=1
  fi
}

shopt -s nullglob
for dir in src/*/; do
  name="$(basename "$dir")"
  if [[ "$name" == "common" || "$name" == "__pycache__" ]]; then
    continue
  fi
  run_tests "$name"
done

if [[ "$fail" -ne 0 ]]; then
  case "${BLOCKING}" in
    true|True|TRUE|1|yes)
      echo "Tests failed and blocking is true."
      exit 1
      ;;
    *)
      echo "Tests failed and blocking is false. Forks set blocking to true in azure-pipelines-ci.yml."
      exit 0
      ;;
  esac
fi

echo "Integration tests passed."
