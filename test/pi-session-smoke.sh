#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
server_pid=""
cleanup() {
  [ -z "$server_pid" ] || kill "$server_pid" >/dev/null 2>&1 || true
  rm -rf "$work" /tmp/pi-sessions/smoke-pi-*.json 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$work/bin" "$work/home"
cat > "$work/bin/pi" <<'EOF'
#!/bin/sh
set -eu
prompt=""
for argument in "$@"; do prompt="$argument"; done
if [ "$prompt" = "cancel-me" ]; then
  trap 'printf cancelled > "$PI_CANCELLED_MARKER"; exit 143' TERM
  printf started > "$PI_STARTED_MARKER"
  while :; do sleep 1; done
fi
printf 'fake pi response to: %s' "$prompt"
EOF
chmod +x "$work/bin/pi"

port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
PATH="$work/bin:$PATH" HOME="$work/home" SYMPOZIUM_WORKSPACE="$work" PI_STARTED_MARKER="$work/started" PI_CANCELLED_MARKER="$work/cancelled" \
  MODEL_NAME=test-model MODEL_BASE_URL=http://model.invalid/v1 OPENAI_API_KEY=test-key \
  SYMPOZIUM_HARNESS_CONTRACT_VERSION=v1alpha2 SYMPOZIUM_SESSION_PORT="$port" \
  node "$repo_root/adapters/pi/session-server.mjs" >"$work/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1 && break
  sleep 0.1
done
curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null

response="$(curl -fsS -H 'content-type: application/json' -d '{"session_id":"smoke-pi-json","messages":[{"role":"user","content":"hello"}]}' "http://127.0.0.1:${port}/v1/chat/completions")"
printf '%s' "$response" | jq -e '.choices[0].message.content | contains("hello")' >/dev/null
stream="$(curl -fsS -H 'content-type: application/json' -d '{"session_id":"smoke-pi-stream","stream":true,"messages":[{"role":"user","content":"stream"}]}' "http://127.0.0.1:${port}/v1/chat/completions")"
printf '%s' "$stream" | grep -q 'data: \[DONE\]'

curl --max-time 0.2 -sS -H 'content-type: application/json' -d '{"session_id":"smoke-pi-cancel","messages":[{"role":"user","content":"cancel-me"}]}' "http://127.0.0.1:${port}/v1/chat/completions" >/dev/null 2>&1 || true
for _ in $(seq 1 30); do [ -f "$work/cancelled" ] && break; sleep 0.1; done
[ -f "$work/started" ] || { echo "Pi cancellation smoke never started the child" >&2; exit 1; }
[ -f "$work/cancelled" ] || { echo "Pi cancellation smoke did not terminate the disconnected child" >&2; exit 1; }
curl -fsS "http://127.0.0.1:${port}/healthz" >/dev/null
echo "Pi persistent session smoke passed"
