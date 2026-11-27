# Warp Test Reference

Part of the Jacquard agent guide: Warp detail beyond the Warp Tests section of
[the core guide](../SKILL.md). The full manual is [warp-testing.md](../warp-testing.md).

## Posterior Checks And Governance

`check.posterior` and `check.same-dist` are testing laws, not governance
authorization. GM.21's decision-bearing uncertainty path is
`judge.posterior-exact-v1`: it resolves a stored
`(GovernanceCall) ->{Dist} Risk` model by content hash, obtains an independent
baseline from the next outer Judge, performs bounded exact enumeration, and
only raises the baseline risk. `posterior.replay-exact-v1` reruns that exact
evidence. Exact `observe` accepts transparent primitive, tuple, and constructor
data; closures and opaque runtime values fail closed rather than comparing
equal through their redacted rendering. Seeded `posterior.sample-evidence-v1` returns the distinct
`NonAuthorizingApproximateRiskEvidenceV1` carrier and cannot project an
assessment or reach the gate.

## Cache

Warp's cache keys on canonical content hashes and dependencies. A comment,
format, or ordinary term-rename-only edit reruns zero tests. A canonical
dependency-content edit reruns affected dependents. Use `--no-cache` for
demonstrations and a fixed `--seed` for repeatable sampled properties.
