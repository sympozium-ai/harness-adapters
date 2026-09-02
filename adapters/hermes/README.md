# Hermes adapter (experimental)

Upstream: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)
at `fc0a10a924ce31a7badd0d7a202dcc0779ef7942` (`0.20.6` source tree).

Hermes has persistent-learning and configuration surfaces that must not be
silently mapped onto an ephemeral AgentRun. The adapter builds the pinned
source against its checked-in `uv.lock`, then generates a fresh ephemeral
`HERMES_HOME` configuration for a named custom OpenAI-compatible provider.
The `v1alpha1` mode invokes `hermes --oneshot`. The `v1alpha2` mode exposes the
private `openai-chat` session endpoint, serializes requests, and stores a
bounded transcript under `/tmp/hermes-sessions` on the Sympozium-owned PVC.
Each turn invokes the same tool-disabled one-shot surface with that transcript
as explicit context. Neither mode uses ambient user configuration, login
state, learning, native Hermes sessions, rules, or MCP configuration.

Capabilities: persistent chat and restart continuity under `v1alpha2`; no
tools. The adapter does not claim tool filtering, persona, MCP, native Hermes
resume, or subagents. It runs as UID 1000 with a read-only root filesystem and
does not log the injected `OPENAI_API_KEY`.

Publication still requires contract conformance, a real model smoke,
egress/credential review, and support owner. MCP/SkillPack support requires a
separate, policy-enforced implementation and test suite.
