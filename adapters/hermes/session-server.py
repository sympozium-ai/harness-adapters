#!/usr/bin/env python3
"""Private Sympozium Harness Contract v1alpha2 endpoint for Hermes."""

import json
import os
import re
import signal
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BODY = 1_048_576
MAX_OUTPUT = 2_000_000
MAX_TRANSCRIPT = 1_000_000
SESSION_DIR = Path("/tmp/hermes-sessions")
SESSION_ID = re.compile(r"^[a-zA-Z0-9._-]{1,80}$")
LOCK = threading.Lock()
ACTIVE_CHILD = None


def fail(message):
    raise SystemExit(f"sympozium hermes session: {message}")


for required in ("MODEL_NAME", "MODEL_BASE_URL", "OPENAI_API_KEY"):
    if not os.environ.get(required):
        fail(f"{required} is required")
if os.environ.get("SYMPOZIUM_HARNESS_CONTRACT_VERSION") != "v1alpha2":
    fail("unsupported harness contract")
SESSION_DIR.mkdir(parents=True, exist_ok=True)


def transcript_path(session_id):
    return SESSION_DIR / f"{session_id}.json"


def load_transcript(session_id):
    path = transcript_path(session_id)
    if not path.exists():
        return []
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, list):
        raise ValueError("stored session transcript is invalid")
    return value[-200:]


def save_transcript(session_id, turns):
    turns = turns[-200:]
    encoded = json.dumps(turns).encode()
    # Drop complete user/assistant pairs from the oldest end until durable
    # context remains bounded independently of the per-request body limit.
    while len(encoded) > MAX_TRANSCRIPT and len(turns) > 2:
        turns = turns[2:]
        encoded = json.dumps(turns).encode()
    if len(encoded) > MAX_TRANSCRIPT:
        raise ValueError("session transcript exceeds 1 MB")
    path = transcript_path(session_id)
    temporary = path.with_suffix(f".{uuid.uuid4().hex}.tmp")
    temporary.write_bytes(encoded)
    temporary.replace(path)


def prompt_with_history(turns, prompt):
    if not turns:
        return prompt
    lines = ["Continue this conversation. Treat the transcript as context and answer the final User message.", ""]
    for turn in turns:
        lines.append(f"{turn['role'].capitalize()}: {turn['content']}")
    lines.extend((f"User: {prompt}", "Assistant:"))
    return "\n".join(lines)


def run_hermes(prompt, session_id):
    global ACTIVE_CHILD
    usage_path = SESSION_DIR / f"{session_id}-usage-{uuid.uuid4().hex}.json"
    command = [
        "hermes", "--ignore-rules", "--provider", "sympozium",
        "--model", os.environ["MODEL_NAME"], "--usage-file", str(usage_path),
        "--oneshot", prompt,
    ]
    try:
        ACTIVE_CHILD = subprocess.Popen(
            command, cwd=os.environ.get("SYMPOZIUM_WORKSPACE", "/workspace"), env=os.environ, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False,
        )
        output = bytearray()
        while True:
            chunk = ACTIVE_CHILD.stdout.read(65_536)
            if not chunk:
                break
            output.extend(chunk)
            if len(output) > MAX_OUTPUT:
                ACTIVE_CHILD.terminate()
                ACTIVE_CHILD.wait(timeout=5)
                raise ValueError("adapter output exceeded 2 MB")
        ACTIVE_CHILD.wait()
        text = output.decode("utf-8", errors="replace").strip()
        if ACTIVE_CHILD.returncode != 0:
            raise ValueError(f"Hermes exited {ACTIVE_CHILD.returncode}: {text[-1000:]}")
        if not usage_path.is_file():
            raise ValueError("Hermes did not produce a usage report")
        usage = json.loads(usage_path.read_text(encoding="utf-8"))
        if not (usage.get("completed") is True and usage.get("failed") is False and usage.get("api_calls", 0) > 0 and usage.get("model") == os.environ["MODEL_NAME"]):
            raise ValueError("Hermes did not complete a verified model call")
        if not text:
            raise ValueError("Hermes returned an empty response")
        return text
    finally:
        ACTIVE_CHILD = None
        usage_path.unlink(missing_ok=True)


def shutdown(_signum, _frame):
    if ACTIVE_CHILD is not None and ACTIVE_CHILD.poll() is None:
        ACTIVE_CHILD.terminate()
    raise SystemExit(0)


signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, message, *args):
        print(f"sympozium hermes session: {message % args}")

    def send_json(self, status, value, content_type="application/json"):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("content-length", "2")
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("content-length", "0"))
            if length <= 0 or length > MAX_BODY:
                raise ValueError("request body exceeds 1 MiB" if length > MAX_BODY else "request body is required")
            request = json.loads(self.rfile.read(length))
            messages = request.get("messages")
            users = [m for m in messages or [] if isinstance(m, dict) and m.get("role") == "user" and isinstance(m.get("content"), str)]
            if not users:
                raise ValueError("messages must contain a user message")
            prompt = users[-1]["content"]
            requested_id = request.get("session_id", "default")
            session_id = requested_id if isinstance(requested_id, str) and SESSION_ID.fullmatch(requested_id) else "default"
            with LOCK:
                turns = load_transcript(session_id)
                response = run_hermes(prompt_with_history(turns, prompt), session_id)
                save_transcript(session_id, turns + [{"role": "user", "content": prompt}, {"role": "assistant", "content": response}])
            completion_id = f"chatcmpl-{uuid.uuid4()}"
            created = int(time.time())
            if request.get("stream") is True:
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.send_header("cache-control", "no-cache")
                self.end_headers()
                chunk = {"id": completion_id, "object": "chat.completion.chunk", "created": created, "model": os.environ["MODEL_NAME"], "choices": [{"index": 0, "delta": {"content": response}, "finish_reason": None}]}
                stop = {"id": completion_id, "object": "chat.completion.chunk", "created": created, "model": os.environ["MODEL_NAME"], "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
                self.wfile.write(f"data: {json.dumps(chunk)}\n\ndata: {json.dumps(stop)}\n\ndata: [DONE]\n\n".encode())
                return
            self.send_json(200, {"id": completion_id, "object": "chat.completion", "created": created, "model": os.environ["MODEL_NAME"], "choices": [{"index": 0, "message": {"role": "assistant", "content": response}, "finish_reason": "stop"}]})
        except Exception as error:
            self.send_json(400, {"error": {"message": str(error), "type": "harness_session_error"}})


port = int(os.environ.get("SYMPOZIUM_SESSION_PORT", "8080"))
print(f"sympozium hermes session listening on {port}")
ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
