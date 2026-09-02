#!/usr/bin/env node
// Private Sympozium Harness Contract v1alpha2 endpoint for Pi.
import http from "node:http";
import { mkdir, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";

const port = Number(process.env.SYMPOZIUM_SESSION_PORT || "8080");
const maxBody = 1_048_576;
const maxOutput = 2_000_000;
const sessionDir = "/tmp/pi-sessions";
function fail(message) { console.error(`sympozium pi session: ${message}`); process.exit(1); }
for (const name of ["MODEL_NAME", "MODEL_BASE_URL", "OPENAI_API_KEY"]) if (!process.env[name]) fail(`${name} is required`);
if (process.env.SYMPOZIUM_HARNESS_CONTRACT_VERSION !== "v1alpha2") fail("unsupported harness contract");
await mkdir(`${process.env.HOME}/.pi/agent`, { recursive: true });
await mkdir(sessionDir, { recursive: true });
await writeFile(`${process.env.HOME}/.pi/agent/models.json`, JSON.stringify({ providers: { sympozium: { baseUrl: process.env.MODEL_BASE_URL, api: "openai-completions", apiKey: "$OPENAI_API_KEY", compat: { supportsDeveloperRole: false, supportsReasoningEffort: false }, models: [{ id: process.env.MODEL_NAME, reasoning: false, input: ["text"], contextWindow: 32768, maxTokens: 4096 }] } } }));

function readJSON(req) { return new Promise((resolve, reject) => { let size = 0; let body = ""; req.setEncoding("utf8"); req.on("data", (chunk) => { size += Buffer.byteLength(chunk); if (size > maxBody) { reject(new Error("request body exceeds 1 MiB")); req.destroy(); return; } body += chunk; }); req.on("end", () => { try { resolve(JSON.parse(body)); } catch { reject(new Error("request must be valid JSON")); } }); req.on("error", reject); }); }
function promptFrom(messages) { if (!Array.isArray(messages)) throw new Error("messages is required"); const users = messages.filter((m) => m && m.role === "user" && typeof m.content === "string"); if (!users.length) throw new Error("messages must contain a user message"); return users.at(-1).content; }
// Pi emits its response on stdout. Forward each chunk after bounded output
// accounting, so `stream: true` is genuine adapter streaming
// rather than a UI timer replaying a completed answer.
function runPi(prompt, sessionID, onOutput, signal) { return new Promise((resolve, reject) => { const args = ["--print", "--no-skills", "--no-prompt-templates", "--no-tools", "--provider", "sympozium", "--model", process.env.MODEL_NAME, "--session-id", sessionID, "--session-dir", sessionDir, prompt]; const child = spawn("pi", args, { cwd: process.env.SYMPOZIUM_WORKSPACE || "/workspace", env: process.env, stdio: ["ignore", "pipe", "pipe"] }); let output = ""; let stderr = ""; let exceeded = false; let cancelled = false; const cancel = () => { cancelled = true; child.kill("SIGTERM"); }; if (signal?.aborted) cancel(); else signal?.addEventListener("abort", cancel, { once: true }); const collect = (chunk, outputStream) => { if (output.length + stderr.length + chunk.length > maxOutput) { exceeded = true; child.kill("SIGTERM"); return; } if (outputStream) { output += chunk; onOutput?.(chunk); } else stderr += chunk; }; child.stdout.setEncoding("utf8"); child.stderr.setEncoding("utf8"); child.stdout.on("data", (chunk) => collect(chunk, true)); child.stderr.on("data", (chunk) => collect(chunk, false)); child.on("error", reject); child.on("close", (code) => { signal?.removeEventListener("abort", cancel); if (cancelled) return reject(new Error("request cancelled")); if (exceeded) return reject(new Error("adapter output exceeded 2 MB")); if (code !== 0) return reject(new Error(`Pi exited ${code}: ${stderr.slice(-1000)}`)); if (!output.trim()) return reject(new Error("Pi returned an empty response")); resolve(output.trim()); }); }); }

function writeSSE(res, value) { if (!res.writableEnded) res.write(`data: ${JSON.stringify(value)}\n\n`); }

let queue = Promise.resolve();
http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/healthz") { res.writeHead(200).end("ok"); return; }
  if (req.method !== "POST" || req.url !== "/v1/chat/completions") { res.writeHead(404).end(); return; }
  try {
    const request = await readJSON(req);
    const prompt = promptFrom(request.messages);
    const sessionID = typeof request.session_id === "string" && /^[a-zA-Z0-9._-]{1,80}$/.test(request.session_id) ? request.session_id : "default";
    const stream = request.stream === true;
    const id = `chatcmpl-${randomUUID()}`;
    const cancellation = new AbortController();
    res.once("close", () => { if (!res.writableEnded) cancellation.abort(); });
    if (stream) res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", connection: "keep-alive", "x-accel-buffering": "no" });
    const response = await (queue = queue.catch(() => undefined).then(() => runPi(prompt, sessionID, stream ? (chunk) => writeSSE(res, { id, object: "chat.completion.chunk", created: Math.floor(Date.now() / 1000), model: process.env.MODEL_NAME, choices: [{ index: 0, delta: { content: chunk }, finish_reason: null }] }) : undefined, cancellation.signal)));
    if (stream) { writeSSE(res, { id, object: "chat.completion.chunk", created: Math.floor(Date.now() / 1000), model: process.env.MODEL_NAME, choices: [{ index: 0, delta: {}, finish_reason: "stop" }] }); if (!res.writableEnded) res.end("data: [DONE]\n\n"); return; }
    const body = JSON.stringify({ id, object: "chat.completion", created: Math.floor(Date.now() / 1000), model: process.env.MODEL_NAME, choices: [{ index: 0, message: { role: "assistant", content: response }, finish_reason: "stop" }] }); res.writeHead(200, { "content-type": "application/json", "content-length": Buffer.byteLength(body) }).end(body);
  } catch (err) {
    const message = err instanceof Error ? err.message : "session request failed";
    if (res.headersSent) { writeSSE(res, { error: { message, type: "harness_session_error" } }); if (!res.writableEnded) res.end("data: [DONE]\n\n"); return; }
    const body = JSON.stringify({ error: { message, type: "harness_session_error" } }); res.writeHead(400, { "content-type": "application/json", "content-length": Buffer.byteLength(body) }).end(body);
  }
}).listen(port, "0.0.0.0", () => console.log(`sympozium pi session listening on ${port}`));
