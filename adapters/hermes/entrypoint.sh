#!/bin/sh
set -eu

result_path="${SYMPOZIUM_RESULT_PATH:-/ipc/output/result.json}"
work_path="${TMPDIR:-/tmp}/hermes-output.txt"
usage_path="${TMPDIR:-/tmp}/hermes-usage.json"

emit() {
  status="$1"
  body="$2"
  if [ "$status" = success ]; then
    payload="$(jq -cn --arg response "$body" '{status:"success",response:$response}')"
  else
    payload="$(jq -cn --arg error "$body" '{status:"error",error:$error}')"
  fi
  mkdir -p "$(dirname "$result_path")"
  printf '%s' "$payload" > "$result_path"
  printf '__SYMPOZIUM_RESULT__\n%s\n__SYMPOZIUM_END__\n' "$payload"
}

fail() { emit error "$1"; exit 1; }

[ "${SYMPOZIUM_HARNESS_CONTRACT_VERSION:-}" = v1alpha1 ] || fail "unsupported harness contract"
[ -n "${TASK:-}" ] || fail "no task supplied"
[ -n "${MODEL_NAME:-}" ] || fail "no model supplied"
[ -n "${MODEL_BASE_URL:-}" ] || fail "no model endpoint supplied"
[ -n "${OPENAI_API_KEY:-}" ] || fail "OPENAI_API_KEY is required"

export HERMES_HOME="$HOME/.hermes"
mkdir -p "$HERMES_HOME"
cat > "$HERMES_HOME/config.yaml" <<EOF
model:
  provider: sympozium
platform_toolsets:
  cli: []
providers:
  sympozium:
    name: sympozium
    api: ${MODEL_BASE_URL}
    key_env: OPENAI_API_KEY
    default_model: ${MODEL_NAME}
    transport: chat_completions
EOF

set +e
hermes --ignore-rules --provider sympozium --model "$MODEL_NAME" --usage-file "$usage_path" --oneshot "$TASK" >"$work_path" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  fail "Hermes exited ${rc}: $(tail -c 2000 "$work_path")"
fi
[ -r "$usage_path" ] || fail "Hermes did not produce a usage report"
jq -e --arg model "$MODEL_NAME" \
  '(.completed == true) and (.failed == false) and ((.api_calls // 0) > 0) and (.model == $model)' \
  "$usage_path" >/dev/null || fail "Hermes did not complete a verified model call"
response="$(cat "$work_path")"
[ -n "$response" ] || fail "Hermes returned an empty response"
emit success "$response"
