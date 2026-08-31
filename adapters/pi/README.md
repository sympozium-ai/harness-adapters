# Pi adapter (experimental)

Target upstream: [earendil-works/pi](https://github.com/earendil-works/pi),
specifically the `@earendil-works/pi-coding-agent` package.

Before implementation, pin an upstream release and lockfile integrity value;
the Dockerfile must install that exact package with lifecycle scripts disabled
unless a reviewed exception is documented. The adapter must map Sympozium's
task, configured model endpoint/credential, and MCP registry into Pi without
mounting host state or a user home directory.

Required evidence before publication: contract conformance, real model smoke,
SkillPack MCP allow/deny smoke, credential scope review, and support owner.
