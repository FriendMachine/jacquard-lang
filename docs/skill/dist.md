# Discrete Probability With Dist

Part of the Jacquard agent guide: discrete probabilistic models and exact and
approximate inference. Start with [the core guide](../SKILL.md).

The prelude defines distribution values such as `Bernoulli(p)`,
`Categorical(weighted-pairs)`, and `UniformInt(low, high)`. Models perform
`sample` and `observe` through the `Dist` effect. `Bernoulli(p)` is a
`Distribution Bool` and `UniformInt(low, high)` a `Distribution Int`, so a draw
from either is a `Bool` or an `Int`; using it at another type is a check error.

```jacquard doctest=skill-dist mode=check fixture=skill-dist.jac stdout=skill-dist.stdout stderr=empty exit=0
coin-model : () ->{Dist} Bool
coin-model() = {
  let first = `op:sample`(Bernoulli(0.5))
  let second = `op:sample`(Bernoulli(0.5))
  `op:observe`(
    Bernoulli(if bool.or(first, second) then 1.0 else 0.0),
    True)
  first
}

coin-model()
```

Run the exact and approximate handlers over the same file:

```sh
jac hash coin.jac > before.hash
jac infer enumerate coin.jac
jac infer lw coin.jac --seed 42 --samples 100000
jac hash coin.jac > after.hash
cmp before.hash after.hash
```

Exact enumeration resumes once per support value, multiplies observation
likelihoods, prunes exact zero-weight paths, merges equal outcomes at the CLI,
and normalizes. Likelihood weighting is deterministic for the same seed and
sample count. `Categorical` weights are relative. `UniformInt` exact support is
capped at 10,000 outcomes.

Inside Jacquard, use `dist.enumerate(fn () -> model())`, then
`dist.tally(table, equality)` when equal outcomes should be merged. The
in-language all-impossible case may expose NaN weights; CLI enumeration reports
a diagnostic instead. An unhandled root `observe` is an error.
