# Pi adapter (experimental)

Upstream: [earendil-works/pi](https://github.com/earendil-works/pi),
`@earendil-works/pi-coding-agent` `0.84.4`.

The adapter installs the exact package with lifecycle scripts disabled. It
creates Pi's provider configuration under the run's ephemeral `$HOME`, maps
`MODEL_BASE_URL`, `MODEL_NAME`, and the injected `OPENAI_API_KEY` to an
OpenAI-compatible provider, and invokes `pi --print --no-tools`.

Capabilities: none. This first release deliberately does not expose Pi tools,
MCP, persona, or resume. It runs as UID 1000 with a read-only root filesystem;
only the run-provided `$HOME`, `/workspace`, `/tmp`, and result mount are
writable. The model key is written neither to logs nor to the image.

The same image also has an experimental `v1alpha2` mode for a Sympozium-owned
persistent session. In that mode it starts a private `openai-chat` HTTP
endpoint and serializes Pi turns through a named Pi session file; it still
disables tools, skills, and prompt templates. The endpoint is intended solely
for Sympozium's authenticated API proxy and is not an ingress or a general
purpose OpenAI gateway.

Publication still requires contract conformance, a real model smoke, credential
scope review, and support owner. MCP/SkillPack support is a later capability,
not implied by this image.
