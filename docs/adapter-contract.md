# Adapter contract

Adapters implement Sympozium Harness Contract `v1alpha1`.

The container receives the task and contract environment supplied by
Sympozium, may use the mounted MCP registry and its explicit credentials, and
must write the structured result protocol. It must run as non-root with a
read-only root filesystem and a writable platform-provided HOME.

The adapter is not trusted to enforce Kubernetes policy. Sympozium enforces
admission, image approval, per-run identity, token boundaries, mounts, NATS
ACLs, SkillPack policy, and lifecycle. Harness-native behavior is an
adapter-declared capability until independently verified.

## Conformance gates

Before publication an adapter must prove:

- startup as UID 1000 with read-only root and `/workspace` cwd;
- valid success, error, missing-result, and malformed-result behavior;
- no TTY assumption, bounded noisy output, timeout and SIGTERM behavior;
- real/absent metrics semantics;
- allowed and denied SkillPack MCP tool behavior;
- a scheduled cluster smoke test using a real model call.

The initial test harness will be added under `conformance/`; no adapter is
marked supported solely because it builds.
