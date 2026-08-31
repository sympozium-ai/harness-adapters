#!/bin/sh
set -eu

adapter="$1"
image="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/ipc/output" "$work/home" "$work/tmp"

set +e
docker run --rm --read-only --user 1000:1000 \
  -e HOME=/home/agent \
  -e TMPDIR=/tmp \
  -e SYMPOZIUM_HARNESS_CONTRACT_VERSION=v1alpha1 \
  -e TASK='Return one word.' \
  -e MODEL_NAME=test-model \
  -e MODEL_BASE_URL=http://127.0.0.1:9/v1 \
  -e OPENAI_API_KEY=not-a-real-key \
  -v "$work/ipc/output:/ipc/output" \
  -v "$work/home:/home/agent" \
  -v "$work/tmp:/tmp" \
  "$image" >/dev/null 2>&1
rc=$?
set -e

[ "$rc" -ne 0 ] || { echo "$adapter accepted an unreachable model endpoint" >&2; exit 1; }
jq -e '.status == "error" and (.error | type == "string") and length > 0' \
  "$work/ipc/output/result.json" >/dev/null
echo "$adapter contract failure-path smoke passed"
