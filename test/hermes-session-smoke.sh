#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
server_pid=""
session_id="smoke-$$"
cleanup() {
  [ -z "$server_pid" ] || kill "$server_pid" >/dev/null 2>&1 || true
  rm -rf "$work" "/tmp/hermes-sessions/${session_id}.json" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$work/bin" "$work/home"
cat > "$work/bin/hermes" <<'EOF'
#!/bin/sh
set -eu
usage=""
previous=""
prompt=""
for argument in "$@"; do
  if [ "$previous" = "--usage-file" ]; then usage="$argument"; fi
  previous="$argument"
  prompt="$argument"
done
[ -n "$usage" ]
printf '{"completed":true,"failed":false,"api_calls":1,"model":"test-model"}' > "$usage"
printf 'fake response to: %s' "$prompt"
EOF
chmod +x "$work/bin/hermes"

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
start_server() {
  PATH="$work/bin:$PATH" HOME="$work/home" SYMPOZIUM_WORKSPACE="$work" \
    MODEL_NAME=test-model MODEL_BASE_URL=http://model.invalid/v1 OPENAI_API_KEY=test-key \
    SYMPOZIUM_HARNESS_CONTRACT_VERSION=v1alpha2 SYMPOZIUM_SESSION_PORT="$port" \
    python3 "$repo_root/adapters/hermes/session-server.py" >"$work/server.log" 2>&1 &
  server_pid=$!
  for _ in $(seq 1 30); do
    curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1 && return
    sleep 0.1
  done
  cat "$work/server.log" >&2
  return 1
}
start_server

first="$(curl -fsS -H 'content-type: application/json' -d "{\"session_id\":\"${session_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"remember cobalt\"}]}" "http://127.0.0.1:${port}/v1/chat/completions")"
printf '%s' "$first" | jq -e '.choices[0].message.content | contains("remember cobalt")' >/dev/null

# The second turn runs in a fresh server process and must recover the first
# turn from the same path the Sympozium PVC preserves across pod restarts.
kill "$server_pid"
wait "$server_pid" >/dev/null 2>&1 || true
server_pid=""
start_server

second="$(curl -fsS -H 'content-type: application/json' -d "{\"session_id\":\"${session_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"what was it\"}]}" "http://127.0.0.1:${port}/v1/chat/completions")"
printf '%s' "$second" | jq -e '.choices[0].message.content | contains("remember cobalt") and contains("what was it")' >/dev/null
jq -e 'length == 4 and .[0].content == "remember cobalt" and .[2].content == "what was it"' "/tmp/hermes-sessions/${session_id}.json" >/dev/null

stream="$(curl -fsS -H 'content-type: application/json' -d "{\"session_id\":\"${session_id}\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"stream now\"}]}" "http://127.0.0.1:${port}/v1/chat/completions")"
printf '%s' "$stream" | grep -q 'data: \[DONE\]'
echo "Hermes persistent session smoke passed"
