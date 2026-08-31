#!/bin/sh
set -eu

adapter="$1"
image="$2"
work="$(mktemp -d)"
# Image tooling can create nested files as a mapped container UID.  This is a
# disposable test directory; failure to remove a host-owned cache must not
# hide the contract assertion above.
trap 'rm -rf "$work" 2>/dev/null || true' EXIT
mkdir -p "$work/ipc/output" "$work/home" "$work/tmp"
# Docker bind mounts preserve host ownership.  The production pod supplies
# writable emptyDirs to UID 1000, so mirror that contract explicitly on CI.
# The parent is also a bind-mount path and must be searchable by that UID.
chmod 0777 "$work" "$work/ipc" "$work/ipc/output" "$work/home" "$work/tmp"

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
