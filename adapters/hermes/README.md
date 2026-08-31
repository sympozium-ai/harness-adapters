# Hermes adapter (experimental)

Target upstream: [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent).

Hermes has persistent-learning and configuration surfaces that must not be
silently mapped onto an ephemeral AgentRun. The initial adapter is one-shot:
it receives only the explicit task and approved model credentials, writes the
Sympozium result, and treats persistent learning/session state as unavailable
until a mediated contract exists.

Required evidence before publication: a pinned upstream revision and Python
dependency lock, contract conformance, real model smoke, SkillPack MCP
allow/deny smoke, egress/credential review, and support owner.
