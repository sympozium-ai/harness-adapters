# Sympozium harness adapters

Versioned, conformance-tested adapter images for running external agent
harnesses as the primary process of a Sympozium `AgentRun`.

This repository is intentionally separate from the Sympozium control plane.
An adapter image pins a harness release, translates the versioned Sympozium
contract, and is reviewed/scanned/published independently. Sympozium never
downloads a harness dynamically inside an AgentRun and users never provide an
arbitrary image directly to a run.

## Support tiers

| Adapter | Tier | Status |
|---|---|---|
| `reference` | Maintained fixture | Deterministic v1alpha1 contract smoke test; no model call. |
| `pi` | Experimental | Image implementation in review; not yet published or registered. |
| `hermes` | Experimental | Image implementation in review; not yet published or registered. |

Experimental means the image is not selectable until it passes the contract
suite and a real cluster smoke test. It is not a claim of upstream endorsement
or support.

## How an adapter is built

1. Pin an upstream release by immutable source revision and package checksum.
2. Build a minimal, non-root adapter image in CI; do not run an upstream
   installer at AgentRun startup.
3. Translate `TASK`, model configuration, MCP registry, and supported policy
   controls into the harness's native invocation.
4. Emit the Sympozium result protocol and pass conformance.
5. Publish a multi-architecture image by digest. An operator approves that
   digest through `AgentRuntime` and `SympoziumPolicy`.

See [the adapter contract](docs/adapter-contract.md) and the individual
[Pi](adapters/pi/README.md) and [Hermes](adapters/hermes/README.md) plans.
The current experimental conformance evidence and intentionally unsupported
capabilities are recorded in [the conformance report](docs/conformance.md).

## Installing an example

Examples are opt-in. Apply an `AgentRuntime` in the target namespace, then
select it on an Agent in Sympozium's Create Agent flow (or set
`Agent.spec.runtimeRef`). The adapter never creates model credentials; select
an existing scoped model Secret when you create the Agent or run.

```sh
kubectl -n <namespace> apply -f \
  https://raw.githubusercontent.com/sympozium-ai/harness-adapters/main/manifests/pi-v0.84.4.yaml
# or: manifests/hermes-v0.20.6.yaml
```

Before applying either manifest, an administrator must add its **full image
digest** from the manifest to that namespace's
`SympoziumPolicy.spec.imagePolicy.allowedRegistries`. This is intentionally a
separate action: installing an adapter must not broaden image admission or
grant model credentials. The runtime will show as ready only after policy and
CRD validation complete.

## Contributing

Every adapter must declare an owner, upstream revision, supported capabilities,
credential contract, and conformance evidence. See
[CONTRIBUTING.md](CONTRIBUTING.md).
Versioned, conformance-tested adapters for running external agent harnesses on Sympozium
