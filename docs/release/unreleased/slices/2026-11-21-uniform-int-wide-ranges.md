`UniformInt` ranges whose size exceeds the largest Int are drawn, scored and
shrunk correctly. Every site computed the size as `hi - lo + 1`, which wraps
when `hi - lo` is at least `max-int` (`UniformInt(min-int, max-int)`,
`UniformInt(-1, max-int)`). The interpreter's root sampler and likelihood
weighting then drew `lo` every time from the full range and values outside
other such ranges, `pmf` returned a negative or infinite mass, `support`
returned `nil` for the full range and raised an uncaught
`Invalid_argument("List.init")` for `UniformInt(-1, max-int)` instead of the
enumeration cap, and Warp's sampled lane computed a zero or negative arity, so
it drew only `lo` from the full range and out-of-range offsets from other such
ranges, and every forced replay diverged. The C
runtime computed the size in 64 bits, so it drew differently from the
interpreter (and overflowed for the full range). Exact risk enumeration
(`posterior.run-exact-v1`) computed a large-magnitude narrow range's size in
floats, so `UniformInt(2^60, 2^60 + 5)` weighed each value 1 instead of 1/6.
Every draw scaled one 53-bit uniform float by the size. In a range of more
than 2^52 and fewer than 2^53 values that made some values at least twice as
likely as others or left them unreachable (in `UniformInt(0, 8003926795661438)`,
the value 2^52 is never drawn); a range of more than 2^53 values could reach
at most 2^53 of its values (`UniformInt(0, max-int - 1)` never an odd one).

Every non-empty range is valid. `Infer_dist.uniform_fits`, `uniform_count`
and `uniform_draw` are the one definition the root sampler, the inference
drivers, `pmf`, `support`, exact risk enumeration and Warp's sampled lane use;
the C runtime's `uniform_fits`, `uniform_count` and `uniform_draw` mirror them
in `draw_dist`, `jq_i_pmf`, `pmf_mass` and `support_of`. A range of at most
2^32 values draws by the formula every release used (one uniform float scaled
by the size n), so seeded outputs of such ranges are unchanged in both engines.
Each of the 2^53 equally likely floats gives one value, and every value gets
between q - 1 and q + 1 of them, where q = floor(2^53/n) is at least 2^21, so
every value is reachable and no value is more likely than another by more than
a factor of (q + 1)/(q - 1), below 1 + 10^-6 (exactly uniform when n is a
power of two); `pmf` reports the ideal 1/n. A larger range is drawn exactly uniformly
from integer RNG bits: the top 63 bits of an RNG output are rejected when they are at or above the largest multiple of the
size that is at most 2^63, and otherwise give the offset from `lo` modulo the
size (the full range, 2^63 values, accepts every output). Such a draw consumes
one or more RNG outputs, every value of the range is reachable, and seeded
draws from such ranges change, including ranges whose size fits in an Int
(`UniformInt(0, 4294967296)`, `UniformInt(0, max-int - 1)`). The enumeration cap's error names the exact
size: `UniformInt(min-int, max-int)` has 9223372036854775808 outcomes.

Warp: a `UniformInt` choice index is the offset from `lo`, read as an
unsigned 63-bit number, so the full range's offsets run to 2^63 - 1. The
forced-replay fit check, the shrinker's lowering and its lexicographic order
compare unsigned, the shrink report prints offsets unsigned, and the sampled
lane draws the interpreter's element from the same stream. A `UniformInt`
choice over more than 2^16 values shrinks by trying `lo` (offset 0) first and
then halving its distance from `lo` (the offset less half, a quarter, and so
on of itself), ending with the one-step lowering; every other choice keeps the
one-step lowering. Because an earlier driver could cache a vacuous pass for
such a range, `Warp.version` moves from `warp-v5` to `warp-v6`. An earlier
`jacquard dist-diff` enumerated `UniformInt(min-int, max-int)` as empty and
could cache a posterior missing that branch, so its posterior cache key moves
from `dist-diff-v3` to `dist-diff-v4`.

Evidence: `test/cli/uniform-int-wide.t` runs the root sampler on the full
range, `(-1, max-int)`, `(min-int, 0)`, single-value ranges at both ends, the
top two values, a large-magnitude narrow range, ranges of exactly 2^32 values
at both ends of Int and around zero, ranges of 2^32 + 1, 2^53 and 2^53 + 1
values, and ranges that fit, in the interpreter
and native binaries at the same seeds (including seeds whose first uniform is
near 0 and near 1); it compares 40 seeded streams that interleave wide,
boundary and narrow ranges in both engines and pins a digest of each stream,
and covers `pmf` in and out of range, `dist.sample-lw` (including a model that
returns its wide draws, identical in both engines), the enumeration cap in
both engines, exact risk
enumeration of a large-magnitude narrow range, Warp properties over the full
range (one shrinks and replays from its seed; "never odd" fails) and one over
`(0, max-int - 1)` that shrinks to its exact minimum, and a `dist-diff` entry
planted under `dist-diff-v3` that is not served. `test/test_dist_lib.ml` checks
the rejection rule at its edges, matches wide-range draws against a reference
model of the RNG stream (with rejections observed), checks `pmf` and the cap
message, and a QCheck property checks that `uniform_draw` stays within
`[lo, hi]` for extreme bounds and that ranges of at most 2^32 values keep the
earlier formula. An exact model of the float formula's arithmetic counts the
floats that give each value for n from 1 to 2^32 (every value for small n,
values near the ends, near powers of two and spread over the range for large
n) and checks that each count is between q - 1 and q + 1. `test/test_props.ml` checks the full-range shrink, its seeded
replay, exact offsets at both ends, that forced offsets outside `(-1, max-int)`
and `(0, 5)` diverge, and the shrink over `(0, max-int - 1)`.
`test/test_warp.ml` pins `warp-v6`. `docs/stdlib.md` and
`docs/warp-testing.md` state the rule.
