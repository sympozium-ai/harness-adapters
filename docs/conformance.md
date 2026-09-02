# Adapter conformance evidence

This record covers the first experimental, stateless adapter release. It is
evidence for the Sympozium adapter contract, not an assertion of upstream
endorsement by Pi or Nous Research.

Hermes `v1alpha2` persistent-session support is published and has completed
real-cluster conformance. Its local smoke verifies
the bounded private HTTP surface, serialized multi-turn transcript state,
restart-safe atomic persistence, health probe, and SSE response framing using
a deterministic fake Hermes executable. It is not yet a published default.

## Images

| Runtime | Upstream | Approved digest | Contract |
|---|---|---|---|
| Pi | `@earendil-works/pi-coding-agent` `0.84.4` | `ghcr.io/sympozium-ai/harness-adapters/pi@sha256:b0d50402dc0a25b2c46f86dbd6b5de963487fa0ffa44058cb324ab2c68934f3b` | `v1alpha1` |
| Hermes | `NousResearch/hermes-agent` `fc0a10a924ce31a7badd0d7a202dcc0779ef7942` | `ghcr.io/sympozium-ai/harness-adapters/hermes@sha256:df66d30c56e7a82c74b9df1d8ef4034127f017640f460c0d3aa7c15f28550ab4` | `v1alpha1` |
| Hermes session | `NousResearch/hermes-agent` `fc0a10a924ce31a7badd0d7a202dcc0779ef7942` | `ghcr.io/sympozium-ai/harness-adapters/hermes@sha256:bdbf6f8fae5f282af8008e0a2c2aef398b8c2146185a32365db8ae7599b833be` | `v1alpha2` |

Both images run as UID 1000 with a read-only root filesystem. Each checks the
contract version, accepts only the run-provided model route and injected
credential, writes `$SYMPOZIUM_RESULT_PATH`, and emits the stdout result
marker. Neither writes credentials to output. Pi is invoked with `--no-tools`.
Hermes explicitly opts out of global MCP discovery and writes a configuration
that disables its native toolsets before invoking the model.

## Automated build checks

[GitHub Actions run 33426656198](https://github.com/sympozium-ai/harness-adapters/actions/runs/33426656198)
built both images, then executed each in a read-only container as UID 1000
with only simulated Sympozium writable mounts. The unreachable-endpoint smoke
must fail and write a well-formed error result; it prevents an adapter from
claiming success without a model call.

## Framework evidence

On the Framework cluster, under the isolated `sympozium-harness-e2e`
namespace and a policy that listed each full image digest:

| AgentRun | Runtime source | Result | Recorded digest |
|---|---|---|---|
| `pi-real-call-002` | explicit `pi-v0-84-4` | `pi hardened call succeeded` | `b0d50402…934f3b` |
| `hermes-real-call-004` | explicit `hermes-v0-20-6` | `hermes final hardened call succeeded` | `df66d30c…550ab4` |
| `pi-inherited-call-002` | `Agent.spec.runtimeRef` | `inherited hardened Pi succeeded` | `b0d50402…934f3b` |
| `pi-real-call-20260901` | explicit `pi-v0-84-4` | `pi real adapter verified 20260901` | `b0d50402…934f3b` |
| `hermes-real-call-20260901` | explicit `hermes-v0-20-6` | `hermes real adapter verified 20260901` | `df66d30c…550ab4` |

All five used the Framework's existing scoped local-model Secret and the
OpenAI-compatible Qwen endpoint. The completed runs remain with `cleanup:
keep` in that namespace for inspection. Both `AgentRuntime` objects reached
`Ready=True` and are marked `conformant` after these runs.

The two 2026-09-01 runs are fresh end-to-end evidence for the supported
**one-shot** path: a real model response travelled through each adapter and
the platform recorded the runtime reference, digest, contract, and structured
result. They do not establish interactive/persistent sessions, streaming, MCP,
native tools, or any other capability the adapters do not declare.

## Explicitly unsupported in this release

The two adapters declare no capabilities. In particular, they do **not**
implement MCP/SkillPack tools, tool filtering, persona/system-prompt mapping,
resume, subagents, or persistent Hermes learning. A run requesting any such
capability must be rejected rather than silently accepting a policy the
adapter cannot honour.

MCP support needs a separate implementation that converts
`MCP_CONFIG_PATH` to the upstream harness's configuration and an allow/deny
conformance suite. Do not treat the successful model-call evidence above as
evidence for that future feature.

## Hermes persistent-session evidence

The Hermes image now has a fail-closed `v1alpha2` mode implementing the
`openai-chat` session protocol. It stores at most 200 transcript turns beneath
`/tmp/hermes-sessions`, which Sympozium mounts on the session PVC, and invokes
the existing verified, tool-disabled one-shot model surface with the bounded
conversation as explicit context. Requests are serialized and writes are
atomic. Streaming clients receive valid SSE framing after the verified Hermes
call completes; this adapter does not claim token-by-token upstream streaming.

GitHub Actions run 33615171452 built, exercised, and published the immutable
image above. On 2026-09-02, `hermes-persistent-chat-e2e-chat` reached Ready on
Framework and used the cluster-local Qwen endpoint through the existing scoped
model credential. It stored `hermes-framework-1788342178`, the pod was deleted
and recreated, and the next real model turn returned that exact token from the
PVC-backed transcript. The namespace AgentRun count remained `18 → 18`.

The session pod ran without a service-account token, used the controller-owned
private Service, PVC, and NetworkPolicy, and retained the existing session
boundary that omits NATS. SSE framing and process-restart continuity are also
covered by `test/hermes-session-smoke.sh`.
