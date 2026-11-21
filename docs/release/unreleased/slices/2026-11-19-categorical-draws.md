Categorical draws follow their weights. Every inverse-CDF draw (the
interpreter's `Infer_dist.draw`, Warp's `fresh_index` and the C runtime's
`draw_dist`) ignored entries it could not select: a draw from
`Categorical([])` resumed the model with `()`, and a zero-mass list gave its
last entry. A negative, NaN or infinite entry was never selected on its
merits, but when no entry was selected the draw fell through to the last one,
whatever its weight (with an overflowing total, `[("a", 1e308), ("b", 1e308),
("c", -1.0)]` could give `"c"`). The root sampler, the released
`dist.sample-lw` (`[((), 1.0)]` for an empty list, a full-mass posterior on the
last entry for a zero-mass one), and Warp's sampled lane (an uncaught
`Failure("nth")` on an empty list) inherited this. `jacquard infer lw`, a model
document's `lw` result and `dist.sample-lw-v1` returned confident posteriors
from invalid weights, and enumeration could too: it classified the path
weights, so an observation after the draw pruned a negative branch, and two
single-entry negative sites multiplied to a positive path weight. Both engines
behaved alike.

Recognition: `Infer_dist.dist_of_value` and the C `check_dist` refuse an empty
categorical with the arithmetic error `categorical support is empty`, the
analogue of an empty `UniformInt` range, so `support`, `pmf`, every driver,
Warp and native code stop on it.

Sampling: `Infer_dist.check_weights` validates a categorical without touching
the stream (the first negative or non-finite weight, then a non-finite sum,
then a zero sum) and `Infer_dist.draw_checked` draws only after it passes.
Whether the sum is finite is decided by the weights summed in ascending order
(`Infer_dist.ascending_total`, the C `ascending_total`), which is the same for
every order of the entries; a sum in entry order is not (the largest float
plus two weights of 2^969, a quarter of its ulp, overflows by exactly half an
ulp: in entry order it stays finite when the largest comes first and overflows
when it comes last). To keep this cheap the sort runs only when the entry-order
total is not finite or exceeds half the largest float, below which no order of
finite, nonnegative weights can overflow. A draw keeps its entry-order total,
so valid draws are unchanged; when only that total overflows, the draw uses
the ascending sum. `Infer_dist.draw_total` is that one total, used by
`Infer_dist.draw` and Warp's `fresh_index` (the C `draw_dist` computes the
same), so every draw picks the same entry for the same uniform. `jacquard
review` validates a Distribution domain with `check_weights` instead of its
own entry-order sum, and also checks the support after merging equal values,
which is what its sampled cases draw from, in exhaustive reviews too (E1012,
with a cause that says the weights fail after merging equal values). Merging
sums a value's weights in entry order, as before, unless the whole support's
entry-order sum is not finite or exceeds half the largest float; then every
value's weights are summed in ascending order, so those merged weights, and
whether the merged support is refused, do not depend on the order of the
entries.
`sample_dist`, and so the root sampler and `VaryValue`, turns a failure into an
arithmetic error that names the weight or the sum; the C `categorical_status`
applies the same order and text. A NaN weight is written `nan` whatever its
sign, in both engines (`Infer_dist.show_weight`, the C `show_weight`), because
the sign of a NaN and C libraries' spelling of it differ between platforms.
Valid categoricals take the same single `Rng.float`, so streams, fuel and
allocation charges are unchanged.

Enumeration and likelihood weighting: a draw from a categorical with a
negative, NaN or infinite weight, or with finite weights whose ascending sum
overflows, is refused at the draw with E0917, before any branch is explored or any value
is drawn, so no later factor can prune it. `Infer_dist.invalid_weights` (and
the C `categorical_refusal`) give the reason independent of entry order:
non-finite when any weight is NaN or infinite, else negative mass when any
weight is negative, else non-finite (the ascending sum). `enumerate_v1` and `lw_runs` (behind
`jacquard infer`, `jacquard dist-diff`, model documents and
`dist.sample-lw-weights-v1`) stop there
with an `Invalid_draw` outcome: `jacquard infer` prints the E0917 diagnostic
and a model document says `numerical`. The in-language enumerators
(`dist.enumerate`, `dist.enumerate-v1`) draw through `support`, so the
`support` builtin refuses the same weights with the same E0917 diagnostic, and
`dist.sample-lw-weights-v1` (and so `dist.sample-lw-v1`) stops with it; these
stop the program rather than return an `err` value, because the prelude is
unchanged and a native run cannot be abandoned. `jacquard infer`, the
released `dist.sample-lw` and `dist.sample-lw-v1` report an inner driver's
refusal as their own E0902 runtime failure with the E0917 diagnostic as the
cause, in both engines (the native wrapper keeps the inner code, as it does
for E0901). The in-language enumerators (`dist.enumerate`,
`dist.enumerate-v1`) pass the inner E0917 through unwrapped, as they pass
through any runtime failure. A zero-mass draw keeps its meaning: enumeration
prunes every branch and likelihood weighting makes the run impossible. A run
that is already impossible (after an exact zero observation or a zero-mass
draw) is not refused at a later invalid draw, because enumeration never
reaches a site behind an exact zero factor; it draws there over the shared
total and is dropped when it ends. That differs from the released driver only
when the entry-order total alone overflows: such a run used to fall through to
the last entry and could stop on it (`[(1, 1e308), (1, 1e308), (0, -1e308)]`
behind an exact zero observation, then a division by the draw, was E0902);
it now draws over the ascending sum and ends impossible (E0901), as
enumeration reports. An observation of invalid weights is not a draw: the
`pmf` builtin stays raw, and its factor reaches the classification as a
negative or non-finite path weight as before. The prelude's `dist.pmf` folds
over `support`, so it stops with E0917 on such weights although it draws
nothing.

Every driver that reaches an invalid draw refuses it with E0917, but the
drivers do not reach the same draws. Likelihood weighting refuses only the
sites its runs draw (a site behind `sample(Bernoulli(0.001))` may go unreached
and the posterior comes back), and enumeration stops at the first failure in
its search order, which follows each support's entry order. With several
invalid sites the reason can differ between drivers and seeds, and an earlier
valid categorical's entry order can decide whether enumeration stops with
E0917 at a later invalid draw or with E0902 on a runtime failure in another
branch. The released `dist.sample-lw` (and the
approximate posterior builtin that uses it) weighs a zero-mass run zero and
stops on invalid weights (E0902, or E1547 there). The exact risk boundary
(`posterior.run-exact-v1`) already refused invalid weights at a sample or
observe site (E0911 under E1544) and is unchanged.

Warp: the sampled lane checks each sample site before choosing an index,
including replayed ones, and the exhaustive lane fails a site with invalid
weights or zero total mass (E0902, Warp's code for a runtime failure during
exhaustive execution) instead of a vacuous pass; zero-weight entries of a valid
site are still pruned. Because both lanes now fail generators an earlier driver
passed, `Warp.version` moves from `warp-v3` to `warp-v5`, so a pass cached by
an earlier binary is not served (`warp-v4` is skipped: unreleased builds of
this change used it and could cache a false pass under it).

`jacquard dist-diff` enumerates through `enumerate_v1` and caches posteriors
by the model's hash. A cache written by an earlier binary can hold a posterior
for a model whose draws are now refused (a negative branch pruned by a later
observation, say), so the cache key moves from `dist-diff-v2` to
`dist-diff-v3` and such entries are never read again; refusals are not cached.

This is an erratum: no kernel form, prelude term, signature or operation
identity changes, and the prelude and corpus hash goldens are byte-identical.

Behavior changes:

- `support(Categorical([]))` and `pmf` on it error instead of `nil` and `0.0`;
  `support` of a categorical with a negative, NaN or infinite weight, or an
  overflowing total, stops with E0917 instead of returning the raw list.
- The released `dist.enumerate` on an empty categorical errors instead of
  `nil`, and on invalid weights stops with E0917 instead of returning weights.
- `jacquard infer enumerate` and a model document's `enumerate` result move
  from E0901 (`impossible`) to E0902 (`failure`) for an empty categorical.
- `jacquard infer enumerate`, `infer lw`, `jacquard dist-diff` and
  model-document `enumerate` and `lw` report E0917 (`numerical`) at an invalid draw, where they returned a
  posterior or classified the path weights (`a path weight is negative`).
- `dist.enumerate-v1`, `dist.sample-lw-v1` and `dist.sample-lw-weights-v1`
  stop with E0917 at an invalid draw, where they returned
  `err(inference-numeric-failure-v1 …)`, a posterior, or the raw runs.
- The prelude's `dist.pmf` stops with E0917 on invalid weights, where it
  returned their raw sum, because it folds over `support`.
- A categorical whose finite, nonnegative weights overflow when summed in
  ascending order is refused in every entry order; one whose entry-order sum
  overflows but whose ascending sum does not is drawn by its weights, in
  Warp's sampled lane too (it used to fall through to the last entry, so a
  property that the heavy entry is never drawn could pass). Enumeration's
  posterior still sums path weights in exploration order (see Left for later).
- `jacquard review` accepts a Distribution domain whose entry-order sum alone
  overflows (it was E1012 in some entry orders) and draws it by its weights,
  and refuses one whose merged support overflows (E1012), which it sampled
  from the last entry; the refusal applies to exhaustive reviews too. Whether
  it refuses, and the merged weights of a support whose sum is near the
  largest float, no longer depend on the order of equal values (such a
  domain was E1012 in some orders, and in others was sampled from the last
  entry whatever its weight).
- `jacquard dist-diff` ignores posterior cache entries written under the
  `dist-diff-v2` key.
- `posterior.run-exact-v1` on a model that samples `Categorical([])` reports
  `E1544: exact risk inference failed: E0911: …` (`categorical support is
  empty`) instead of `E1545: exact posterior is impossible because every raw
  class weight is zero`.
- The root sampler, the released `dist.sample-lw` and Warp fail where they
  returned a value or passed. The review command's E1012 refusal of an empty
  domain now names the empty support in its cause.

Evidence: `test/cli/categorical-draws.t` covers the root sampler (and the
unchanged stream of a valid categorical at three seeds), `support` and `pmf`,
both `jacquard infer` drivers, the in-language drivers (including a refusal
nested in another driver), model documents, the `dist-diff` cache key (an entry written under
`dist-diff-v2` is not served; the same entry under `dist-diff-v3` is) and both
Warp lanes (including "never the heavy entry" falsified, sampled and
exhaustive, in every entry order of two weight sets whose entry-order sum
alone overflows) and `jacquard review` on such a domain in two orders and
merged, and, sampled and exhaustive, on a value whose duplicate weights near
the largest float are merged in every order. It runs each
refusal in both entry orders, with an observation after the invalid draw,
behind an integer division, at two single-entry negative sites, with an
overflowing sum beside a negative weight and with a sum that overflows by half
an ulp in three entry orders, and compares every root and
in-language case with a native binary, exit status included.
`test/native-gauntlet/g56-categorical-draws.jqd` pins the cases that do not
stop a program (zero mass, a dead run reaching an invalid draw, an observed
invalid weight, the released driver's zero row) on both engines and runs under
the leak check; g46's negative-mass case is now an observation, since a draw
from a negative weight is refused. `test/test_inference_outcomes.ml` checks
that every driver refuses the same single-site models with the same reason, that both
drivers agree on dead runs, the legacy driver's E0901/E0902 and zero rows, the
order of `check_weights`, the ranking of `invalid_weights`, the `nan` text,
the ascending-sum rule at the overflow boundary, and QCheck properties that
`invalid_weights` and the kind of `check_weights` failure ignore entry order
(over ordinary weights and over weights within an ulp of the largest float) and that
`draw_checked` equals `draw` and leaves the stream where `draw` does on
drawable weights, and that Warp's `fresh_index` picks the index and leaves
the stream where `Infer_dist.draw` does (every order of the two weight sets
picks the heavy entry at twenty seeds, and a QCheck property over ordinary and
near-maximum weights). `test/test_behavior_review.ml` checks that the merged
support, and its refusal, are the same in every order of duplicate weights
near the largest float, and that ordinary duplicates keep their entry-order
sum. `test/test_warp.ml` pins `warp-v5` and that `warp-v1` to `warp-v4`
entries are not reused. `docs/stdlib.md` (Dist and the errata),
`docs/errors.md` (E0902, E0917, E1544, E1547), `docs/warp-testing.md`,
`docs/release/inference-outcomes/DECISION.md` and the upgrade notes state the
rule.

Left for later: a likelihood-weighting run that is already impossible keeps
executing, because the native runtime cannot abandon a run midway. A zero-mass
draw resumes it with the categorical's last entry and a later invalid draw with
the inverse-CDF pick over the shared total. Any runtime failure later in such a run still
stops the program where enumeration, which never reaches it, reports E0901: a
model that inspects such a value can stop with E0902, and so can one that calls
an inner driver that refuses its own draw (E0902 with the inner E0917 as the
cause). Enumeration (`jacquard infer enumerate`, `jacquard dist-diff`, model
documents' `enumerate` and `dist.enumerate-v1`) normalises its posterior by
summing path weights in exploration order, so a categorical the draw accepts
whose total is within rounding of the largest float can fail as a non-finite
total in some entry orders, where likelihood weighting returns a posterior;
this is as before. `jacquard infer enumerate` and `jacquard dist-diff` then
report E0917 ("a path weight or the total mass is not finite") and a model
document's `enumerate` result says `numerical`, while `dist.enumerate-v1`
returns `err(inference-numeric-failure-v1(inference-non-finite-v1, …))`. A total of a few subnormals can round the
scaled uniform up to the total and draw the last entry, a zero-weight one
included (as before; fixing it would move valid streams). The
`UniformInt` range overflow (`hi - lo + 1` wrapping for ranges near the whole
`Int` range) and a coded diagnostic for an invalid distribution are separate
changes.
