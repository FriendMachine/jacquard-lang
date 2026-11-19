# Typed inference outcomes (INF.1)

Status: accepted. Scope: the application-facing discrete inference API
(`dist.*` in the prelude) and `jacquard infer`.

## Problem

Before this change, the library and the CLI disagreed about failure:

- `dist.enumerate` returned `+nan.0` weights for impossible evidence, while
  `jacquard infer enumerate` reported E0901 for the same model.
- An enumeration path whose weight underflowed to zero was pruned as though it
  were impossible.
- NaN and infinite weights printed as a posterior.
- `dist.sample-lw` stopped the program with E0901 and offered no value to
  inspect.

No result said whether it was exhaustive, which seed or bound produced it, or
how much work was done.

## Decision

**D-INF1.1: versioned identities, released ones unchanged.**
`dist.enumerate-v1` and `dist.sample-lw-v1` are new canonical identities
(`prelude/31-inference-outcome.jqd`). They follow the `-v1` precedent for
changed return types. `dist.enumerate`, `dist.sample-lw`, `enum-run` and
`normalize` keep their hashes and behaviour: the prelude hash golden only
grows.

Note (later change): the identities are still unchanged, but three released
behaviours changed with the categorical-draw correction. `dist.enumerate` over
a model that samples `Categorical([])` now stops with an arithmetic error
instead of returning `nil`, because an empty categorical is refused wherever it
is recognised. `dist.enumerate` over a model that draws from a categorical with
a negative, NaN or infinite weight (or an overflowing total) now stops with
E0917, because `support`, its draw, refuses those weights. `dist.sample-lw` now
reports E0901 when every run drew from a zero-mass categorical and E0902 for a
draw from a negative, NaN or infinite weight, where it used to return a
posterior on the last entry or on an entry the weights did not select.

**D-INF1.2: one typed result, built from the existing `result` type.**

```text
dist.enumerate-v1 : (() ->{Dist | e} a, Int) ->{| e}
                      Result InferenceFailureV1 (InferencePosteriorV1 a)
dist.sample-lw-v1 : (() ->{Dist | e} a, Int, Int) ->{| e}
                      Result InferenceFailureV1 (InferencePosteriorV1 a)
```

Note (later change): the model's row now has its own tail, linked one way to
the call's row (`(() ->{Dist | e1} a, Int, Int) ->{| e} ...`, every effect of
`e1` also in `e`), and a model must handle every effect but Dist and the
root-grantable ones (E0838); see `docs/concurrency.md`.

`InferenceFailureV1` has three cases:

- `InferenceImpossibleV1`: no surviving path or run.
- `InferenceExhaustedV1`: the budget was reached before every path was explored.
- `InferenceNumericFailureV1`: carries a reason, one of `InferenceUnderflowV1`,
  `InferenceNonFiniteV1` or `InferenceNegativeMassV1`.

Every outcome, success or failure, carries `InferenceMetadataV1`:

- `method`: exact enumeration or likelihood weighting.
- `complete`: true only when enumeration reached every terminal path; never for
  sampling.
- `seed`: `none` for enumeration.
- `bound`: the terminal-path budget, or the sample count.
- `explored`: terminal paths reached, or runs executed.

No new syntax or abstract type is needed.

**D-INF1.3: one classification contract.** `dist.classify-v1` in the prelude
and `Infer_dist.classify` in OCaml apply the same checks, in this order:

1. Any surviving weight is non-finite: non-finite.
2. Any surviving weight is negative: negative mass.
3. Nothing survives: impossible.
4. The total is non-finite (overflow): non-finite.
5. The total is zero (every surviving path underflowed): underflow.
6. Otherwise: the normalized posterior.

What "surviving" means:

- An enumeration path is pruned only when one of its factors is exactly zero. A
  pruned path still counts against the budget and in `explored`.
- A path whose product merely underflows survives, so underflow is not
  impossibility.
- A sampled run is impossible when an observation factor is exactly zero or it
  draws from a categorical whose support has zero total mass. Impossible runs are
  dropped, not weighted zero.

Both drivers multiply a path's factors forward, in model order. The library
threads the weight through its handler instead of scaling results on the way
back, so both see the same binary64 path weight even when the order decides
whether a product underflows. The test suite checks library/CLI agreement model
by model, including such an order-sensitive model. Posteriors agree to
within floating-point summation order: the library leaves entries unmerged,
while the CLI merges them by rendering.

**D-INF1.4: explicit budgets and no partial posteriors.** `dist.enumerate-v1`
takes a maximum number of terminal paths. Attempting one more path yields
`InferenceExhaustedV1`, with `complete = false` and `explored = budget`. A
non-positive budget is exhausted before the model runs, with `explored = 0`.
The budget counts terminal paths: a model that loops before reaching one is
not bounded by it. `jacquard infer enumerate
--max-branches N` gives the CLI the same bound; it is unbounded by default.
Sampling is bounded by its sample count and is never described as exhaustive.

**D-INF1.5: the CLI applies the contract.**

- `jacquard infer enumerate` and `jacquard infer lw` report:
  - impossible: E0901 (unchanged)
  - numerical failure: E0917 (new)
  - exhausted budget: E0918 (new)
- `--metadata` prints one extra line after the posterior.
- `--samples` and `--max-branches` must be positive integers; anything else is a
  usage error, exit 124.
- The `dist-diff` command enumerates through the same driver.

Note (later change): enumeration and likelihood weighting now refuse a draw
from a categorical with a negative, NaN or infinite weight, or with finite
weights whose sum in ascending order overflows, with E0917 at the draw, before
any later factor can prune the path. The reason does not depend on the order
of the entries: non-finite when any weight is NaN or infinite, else negative
mass when any weight is negative, else non-finite (the ascending sum, which is
the same in every entry order; a sum in entry order can overflow in one order
and not another). `jacquard infer enumerate`, `jacquard infer lw`, `jacquard
dist-diff` and a model document's `enumerate` and `lw` results report it as that
numeric failure (`numerical`); the in-language `dist.enumerate-v1`,
`dist.sample-lw-v1` and `dist.sample-lw-weights-v1` stop with the E0917
diagnostic instead of returning an `err` value, because the prelude
enumerators draw through `support`, which refuses the same weights, and a
native run cannot be abandoned. Before, likelihood weighting returned a
posterior from such weights, and enumeration classified their path weights,
so a later observation could prune a negative branch and two single-entry
negative sites gave a positive path. A run that is already impossible is not
refused at a later invalid draw, since enumeration never reaches it. An
observation of such weights is not a draw: its raw factor still reaches the
classification as a negative or non-finite path weight.

**D-INF1.6: native parity.** The seeded runs come from a new builtin,
`dist.sample-lw-weights-v1`, implemented in the interpreter and the C runtime.
It uses the same stream and run isolation as `dist.sample-lw`. Classification
and budgeted enumeration are ordinary prelude code, so both engines run them.
`test/native-gauntlet/g46-inference-outcomes.jqd` pins byte-identical output.

## Behaviour changes at the CLI

| model | before | after |
|---|---|---|
| every enumeration path underflows | E0901 (pruned as impossible) | E0917, underflow |
| a NaN or infinite weight | a NaN/inf posterior table | E0917, non-finite |
| a negative categorical weight | a table with negative or >1 probabilities | E0917, negative mass |
| `infer lw` drawing only from zero-mass categoricals | a posterior | E0901 |
| `infer lw --samples 0` | E0901 | usage error (exit 124) |
| `infer lw` where some runs are impossible | the impossible values listed with probability 0 | impossible runs are dropped, so those rows are absent |
| `infer enumerate` where some paths underflow but others do not | underflowed paths pruned, so their values were absent | underflowed paths survive and are listed with probability 0 |
| `infer lw` drawing from a categorical with a negative, NaN or infinite weight (later change) | a posterior over the entries the draw could select | E0917 at the draw, negative mass or non-finite, as `infer enumerate` |
| `infer enumerate` drawing from such a categorical (later change) | E0917 from the path weights, or a posterior when a later observation pruned the negative branch | E0917 at the draw, whatever the model observes afterwards |
| `dist.enumerate-v1` or `dist.sample-lw-v1` drawing from such a categorical (later change) | `err(InferenceNumericFailureV1 …)` from the path weights, or a posterior | the program stops with E0917 |
| `infer enumerate` or `infer lw` sampling `Categorical([])` (later change) | E0901 | E0902, `categorical support is empty` |

Otherwise, a well-formed model prints the same posterior as before, provided
its total is positive and representable and no path underflows.

## Migration

| today | move to | handle |
|---|---|---|
| `dist.enumerate(model)` | `dist.enumerate-v1(model, max-paths)` | `ok(InferencePosteriorV1(entries, meta))` holds the same unmerged weights (normalized by division rather than by multiplying by a reciprocal, so the last bit can differ); match `err(...)` instead of testing for NaN |
| `dist.sample-lw(model, n, seed)` | `dist.sample-lw-v1(model, n, seed)` | entries are one per surviving run: `dist.tally(entries, eq)` recovers the merged table, without the zero-probability rows of impossible runs |
| scripts parsing `jacquard infer` | unchanged output | add `--metadata` to record method, completeness, seed and bound; treat E0917 and E0918 as distinct from E0901 |

Choose a budget from the model's finite support: the product of the support sizes
along the deepest path bounds the number of terminal paths.

## Non-claims

- Sampled posteriors are estimates. `complete = false` states that, and
  nothing here bounds their error.
- The classification detects non-finite, negative and underflowed mass. It does
  not validate distributions elsewhere; for example, a categorical weight above
  one still enumerates.
- A total that overflows in one summation order but not another could, in
  principle, classify differently in the library (unmerged, right fold) and the
  CLI (merged). The tests pin the ordinary overflow case, which agrees.
- The released `dist.enumerate` and `dist.sample-lw` are not deprecated
  or removed; their errata remain documented in `docs/stdlib.md` §12.

## Evidence

- `test/test_inference_outcomes.ml` (8 cases):
  - a normalized posterior with metadata
  - impossible evidence (observation, all-zero support) in the library, the
    driver, the CLI code and sampling
  - underflow distinct from impossibility
  - non-finite, NaN, negative and overflowing-total failures
  - bounded exploration: exact budget, one path over, zero budget, and pruned
    paths spending budget
  - seeded reproducibility, and agreement with `dist.sample-lw` on the same stream
  - library/CLI agreement across nine models
  - the released identity is unchanged
- `test/cli/inference-outcomes.t`: CLI codes, flags and metadata.
- `test/native-gauntlet/g46-inference-outcomes.jqd`: native parity.
- `corpus/golden/prelude-hashes.golden`: additions only.
