A draw must produce an element of the support. An empty `Categorical` is
refused wherever a distribution is recognised, like an empty `UniformInt`
range. The root sampler, Warp and `VaryValue` refuse a categorical whose
weights are not finite and nonnegative or that sum to zero. Enumeration and
likelihood weighting refuse a draw from a negative, NaN or infinite weight (or
a total that overflows summed in ascending order) with E0917 at the draw,
whatever the model observes afterwards and whichever entry comes first
(enumeration's posterior still sums path weights in exploration order, so near
the largest float an accepted categorical can fail as a non-finite total in
some orders); a zero-mass draw is an impossible branch or run. The released `dist.sample-lw` weighs a zero-mass run zero and
fails on invalid weights. Valid distributions draw exactly as before. Native
binaries agree byte for byte.

  $ export JACQUARD_PRELUDE=$PWD/../../prelude
  $ export JACQUARD_RUNTIME=$PWD/../../runtime
  $ export CC=clang

  $ NAN='real.div(0.0, 0.0)'; INF='real.div(1.0, 0.0)'

`MAX` is the largest float and `Q` is 2^969, a quarter of its ulp, so
`MAX + Q + Q` overflows by exactly half an ulp. Summed in entry order the total
stays finite when `MAX` comes first or between the two, and overflows when it
comes last; the ascending sum, which decides, overflows in every order:

  $ MAX=1.7976931348623157e308; Q=4.9896007738368e291
  $ cat > dists <<EOF
  > empty|Categorical([])
  > zero|Categorical([MkPair("a", 0.0), MkPair("b", 0.0)])
  > negmix|Categorical([MkPair("a", -1.0), MkPair("b", 2.0)])
  > nan|Categorical([MkPair("a", $NAN), MkPair("b", 1.0)])
  > inf|Categorical([MkPair("a", $INF), MkPair("b", 1.0)])
  > negnan|Categorical([MkPair("a", -1.0), MkPair("b", $NAN)])
  > overflow|Categorical([MkPair("a", 1e308), MkPair("b", 1e308)])
  > ok|Categorical([MkPair("a", 1.0), MkPair("b", 3.0)])
  > ov-huge-first|Categorical([MkPair("a", $MAX), MkPair("b", $Q), MkPair("c", $Q)])
  > ov-huge-last|Categorical([MkPair("b", $Q), MkPair("c", $Q), MkPair("a", $MAX)])
  > ov-huge-between|Categorical([MkPair("b", $Q), MkPair("a", $MAX), MkPair("c", $Q)])
  > EOF
  $ while IFS='|' read name d; do printf 'sample(%s)\n' "$d" > "s-$name.jac"; done < dists

The root sampler refuses every draw that cannot follow the weights, in both
engines, and keeps the stream of a valid categorical (seeds 1, 2, 3):

  $ for name in empty zero negmix nan inf negnan overflow ov-huge-first ov-huge-last ov-huge-between; do
  >   echo "== $name"
  >   jacquard run "s-$name.jac" --allow dist --seed 1 > i.out 2>&1; ie=$?
  >   jacquard build "s-$name.jac" -o prog > /dev/null 2>&1 || { echo "REFUSED"; continue; }
  >   ./prog --allow dist --seed 1 > n.out 2>&1; ne=$?
  >   grep Cause i.out; echo "exit $ie"
  >   if diff -q i.out n.out > /dev/null && [ "$ie" = "$ne" ]; then echo native identical; else echo "DIVERGED native=$ne"; diff i.out n.out; fi
  > done
  == empty
    Cause: arithmetic error: categorical support is empty
  exit 2
  native identical
  == zero
    Cause: arithmetic error: categorical weights sum to zero; there is nothing to draw
  exit 2
  native identical
  == negmix
    Cause: arithmetic error: categorical weight 0 is -1; a draw needs finite, nonnegative weights
  exit 2
  native identical
  == nan
    Cause: arithmetic error: categorical weight 0 is nan; a draw needs finite, nonnegative weights
  exit 2
  native identical
  == inf
    Cause: arithmetic error: categorical weight 0 is inf; a draw needs finite, nonnegative weights
  exit 2
  native identical
  == negnan
    Cause: arithmetic error: categorical weight 0 is -1; a draw needs finite, nonnegative weights
  exit 2
  native identical
  == overflow
    Cause: arithmetic error: categorical weights sum to inf; a draw needs a finite total
  exit 2
  native identical
  == ov-huge-first
    Cause: arithmetic error: categorical weights sum to inf; a draw needs a finite total
  exit 2
  native identical
  == ov-huge-last
    Cause: arithmetic error: categorical weights sum to inf; a draw needs a finite total
  exit 2
  native identical
  == ov-huge-between
    Cause: arithmetic error: categorical weights sum to inf; a draw needs a finite total
  exit 2
  native identical

  $ jacquard build s-ok.jac -o ok > /dev/null
  $ for seed in 1 2 3; do jacquard run s-ok.jac --allow dist --seed $seed; ./ok --allow dist --seed $seed; done
  "b"
  "b"
  "b"
  "b"
  "a"
  "a"

The empty draw no longer reaches the continuation as `()`:

  $ echo 'text.length(sample(Categorical([])))' > len.jac
  $ jacquard run len.jac --allow dist --seed 1
  error: Arithmetic operation failed
    Cause: arithmetic error: categorical support is empty
    Next step: Correct the arithmetic inputs and run the program again.
  [2]

`support` is the in-language enumerators' draw, so it refuses an empty
categorical and invalid weights (E0917) and returns drawable weights raw, zero
mass included; `pmf` refuses an empty one and stays raw otherwise:

  $ echo 'support(Categorical([]))' > sup-empty.jac
  $ jacquard run sup-empty.jac
  error: Arithmetic operation failed
    Cause: arithmetic error: categorical support is empty
    Next step: Correct the arithmetic inputs and run the program again.
  [2]
  $ echo 'pmf(Categorical([]), "a")' > pmf-empty.jac
  $ jacquard run pmf-empty.jac
  error: Arithmetic operation failed
    Cause: arithmetic error: categorical support is empty
    Next step: Correct the arithmetic inputs and run the program again.
  [2]
  $ printf 'support(Categorical([MkPair("a", -1.0), MkPair("b", %s)]))\n' "$NAN" > sup-invalid.jac
  $ jacquard run sup-invalid.jac
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
    Next step: Rescale the model's weights so every path weight and the total stay finite, nonnegative, and representable.
  [2]
  $ jacquard build sup-invalid.jac -o sup-invalid > /dev/null && ./sup-invalid
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
    Next step: Rescale the model's weights so every path weight and the total stay finite, nonnegative, and representable.
  [2]
  $ echo 'support(Categorical([MkPair("a", 0.0), MkPair("b", 0.0)]))' > sup-zero.jac
  $ jacquard run sup-zero.jac
  cons(mk-pair("a", 0.0), cons(mk-pair("b", 0.0), nil))
  $ printf 'pmf(Categorical([MkPair("a", %s), MkPair("b", 1.0)]), "a")\n' "$NAN" > pmf-raw.jac
  $ jacquard run pmf-raw.jac
  +nan.0

`jacquard infer`: an empty categorical is a runtime failure (E0902) for both
drivers; both refuse invalid weights at the draw with the same E0917:

  $ for name in empty zero negmix nan inf negnan overflow ov-huge-first ov-huge-last ov-huge-between; do
  >   echo "== $name"
  >   jacquard infer enumerate "s-$name.jac" > e.out 2>&1; ee=$?
  >   jacquard infer lw --seed 1 --samples 20 "s-$name.jac" > l.out 2>&1; le=$?
  >   grep -v 'Next step' e.out; grep -v 'Next step' l.out; echo "exit $ee $le"
  > done
  == empty
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: categorical support is empty
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: categorical support is empty
  exit 1 1
  == zero
  error[E0901]: The posterior is empty.
    Cause: the posterior is empty: every branch is impossible under the observations
  error[E0901]: The posterior is empty.
    Cause: the posterior is empty: every run is impossible under the observations
  exit 1 1
  == negmix
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  exit 1 1
  == nan
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 1 1
  == inf
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 1 1
  == negnan
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 1 1
  == overflow
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 1 1
  == ov-huge-first
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 1 1
  == ov-huge-last
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 1 1
  == ov-huge-between
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 1 1

In-language drivers, interpreter and native. `dist.sample-lw-v1` and
`dist.enumerate-v1` stop with the same E0917 on invalid weights; the released
`dist.sample-lw` reports E0901 when every run drew from zero mass and E0902 for
invalid weights; an empty categorical stops every driver:

  $ while IFS='|' read name d; do
  >   printf 'dist.sample-lw(fn () -> sample(%s), 5, 1)\n' "$d" > "lw-$name.jac"
  >   printf 'dist.sample-lw-v1(fn () -> sample(%s), 5, 1)\n' "$d" > "lwv1-$name.jac"
  >   printf 'dist.enumerate-v1(fn () -> sample(%s), 10)\n' "$d" > "env1-$name.jac"
  >   printf 'dist.enumerate(fn () -> sample(%s))\n' "$d" > "en-$name.jac"
  > done < dists
  $ for f in lw-empty lw-zero lw-negmix lw-nan lwv1-empty lwv1-negmix lwv1-nan lwv1-inf lwv1-zero env1-empty env1-negmix env1-negnan env1-zero en-empty en-negmix lwv1-ov-huge-first lwv1-ov-huge-last lwv1-ov-huge-between env1-ov-huge-first env1-ov-huge-last env1-ov-huge-between; do
  >   echo "== $f"
  >   jacquard run "$f.jac" > i.out 2>&1; ie=$?
  >   jacquard build "$f.jac" -o prog > /dev/null 2>&1 || { echo "REFUSED"; continue; }
  >   ./prog > n.out 2>&1; ne=$?
  >   grep -v 'Next step' i.out; echo "exit $ie"
  >   if diff -q i.out n.out > /dev/null && [ "$ie" = "$ne" ]; then echo native identical; else echo "DIVERGED native=$ne"; diff i.out n.out; fi
  > done
  == lw-empty
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: categorical support is empty
  exit 2
  native identical
  == lw-zero
  error[E0901]: The posterior is empty.
    Cause: the posterior is empty: every run is impossible under the observations
  exit 2
  native identical
  == lw-negmix
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: categorical weight 0 is -1; a draw needs finite, nonnegative weights
  exit 2
  native identical
  == lw-nan
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: categorical weight 0 is nan; a draw needs finite, nonnegative weights
  exit 2
  native identical
  == lwv1-empty
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: categorical support is empty
  exit 2
  native identical
  == lwv1-negmix
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  exit 2
  native identical
  == lwv1-nan
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == lwv1-inf
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == lwv1-zero
  err(inference-impossible-v1(inference-metadata-v1(inference-likelihood-weighting-v1, false, some(1), 5, 5)))
  exit 0
  native identical
  == env1-empty
  error: Arithmetic operation failed
    Cause: arithmetic error: categorical support is empty
  exit 2
  native identical
  == env1-negmix
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  exit 2
  native identical
  == env1-negnan
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == env1-zero
  err(inference-impossible-v1(inference-metadata-v1(inference-exact-enumeration-v1, true, none, 10, 2)))
  exit 0
  native identical
  == en-empty
  error: Arithmetic operation failed
    Cause: arithmetic error: categorical support is empty
  exit 2
  native identical
  == en-negmix
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  exit 2
  native identical
  == lwv1-ov-huge-first
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == lwv1-ov-huge-last
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == lwv1-ov-huge-between
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == env1-ov-huge-first
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == env1-ov-huge-last
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical
  == env1-ov-huge-between
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  exit 2
  native identical

Every driver that reaches a draw refuses it with the same reason. The reason
ranks the weights, never their order: non-finite when a weight is NaN or
infinite, else negative mass when a weight is negative, else non-finite when
the weights summed in ascending order overflow. The refusal comes at the draw,
so an observation after it (which enumeration would use to prune the negative
branch), a continuation that fails on one entry, or a second negative site
cannot change it. Likelihood weighting refuses only the sites a run reaches.
A site behind an exact zero observation is never reached by enumeration, so a
run that is already impossible is not refused there:

  $ DEAD='{ let _ = observe(Categorical([MkPair("b", 1.0)]), "a"); sample(Categorical([MkPair("a", -1.0)])) }'
  $ cat > models <<EOF
  > obs-neg-first|{ let x = sample(Categorical([MkPair("a", -1.0), MkPair("b", 2.0)])); let _ = observe(Categorical([MkPair("b", 1.0)]), x); x }
  > obs-neg-second|{ let x = sample(Categorical([MkPair("b", 2.0), MkPair("a", -1.0)])); let _ = observe(Categorical([MkPair("b", 1.0)]), x); x }
  > div-neg-first|int.div(10, sample(Categorical([MkPair(1, -1.0), MkPair(0, 2.0)])))
  > div-neg-second|int.div(10, sample(Categorical([MkPair(0, 2.0), MkPair(1, -1.0)])))
  > two-neg-sites|{ let a = sample(Categorical([MkPair(1, -1.0)])); let b = sample(Categorical([MkPair(2, -1.0)])); a }
  > overflow-then-neg|sample(Categorical([MkPair("a", 1e308), MkPair("b", 1e308), MkPair("c", -1.0)]))
  > neg-then-overflow|sample(Categorical([MkPair("c", -1.0), MkPair("a", 1e308), MkPair("b", 1e308)]))
  > huge-negatives|sample(Categorical([MkPair("a", -1e308), MkPair("b", -1e308)]))
  > nan-then-neg|sample(Categorical([MkPair("a", $NAN), MkPair("b", -1.0)]))
  > dead|$DEAD
  > coin-or-dead|if sample(Bernoulli(0.5)) then $DEAD else "ok"
  > EOF
  $ while IFS='|' read name m; do
  >   printf '%s\n' "$m" > "m-$name.jac"
  >   printf 'dist.enumerate-v1(fn () -> %s, 10)\n' "$m" > "mev1-$name.jac"
  >   printf 'dist.sample-lw-v1(fn () -> %s, 20, 1)\n' "$m" > "mlw1-$name.jac"
  >   printf 'dist.enumerate(fn () -> %s)\n' "$m" > "men-$name.jac"
  > done < models
  $ for name in $(cut -d'|' -f1 models); do
  >   echo "== $name"
  >   jacquard infer enumerate "m-$name.jac" > e.out 2>&1; ee=$?
  >   jacquard infer lw --seed 1 --samples 20 "m-$name.jac" > l.out 2>&1; le=$?
  >   grep -v 'Next step' e.out; if diff -q e.out l.out > /dev/null; then echo "lw: same"; else grep -v 'Next step' l.out; fi
  >   echo "exit $ee $le"
  >   for d in mev1 mlw1; do
  >     jacquard run "$d-$name.jac" > i.out 2>&1; ie=$?
  >     jacquard build "$d-$name.jac" -o prog > /dev/null 2>&1 || { echo "$d: REFUSED"; continue; }
  >     ./prog > n.out 2>&1; ne=$?
  >     echo "$d: $(grep -v 'Next step' i.out | tr '\n' ' ')exit $ie"
  >     if ! diff -q i.out n.out > /dev/null || [ "$ie" != "$ne" ]; then echo "DIVERGED native=$ne"; diff i.out n.out; fi
  >   done
  > done
  == obs-neg-first
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == obs-neg-second
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == div-neg-first
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == div-neg-second
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == two-neg-sites
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == overflow-then-neg
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == neg-then-overflow
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == huge-negatives
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  == nan-then-neg
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total
  lw: same
  exit 1 1
  mev1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total exit 2
  mlw1: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a weight or a total that is not finite; enumeration and likelihood weighting draw only from finite weights with a finite total exit 2
  == dead
  error[E0901]: The posterior is empty.
    Cause: the posterior is empty: every branch is impossible under the observations
  error[E0901]: The posterior is empty.
    Cause: the posterior is empty: every run is impossible under the observations
  exit 1 1
  mev1: err(inference-impossible-v1(inference-metadata-v1(inference-exact-enumeration-v1, true, none, 10, 1))) exit 0
  mlw1: err(inference-impossible-v1(inference-metadata-v1(inference-likelihood-weighting-v1, false, some(1), 20, 20))) exit 0
  == coin-or-dead
  1.000000  "ok"
  lw: same
  exit 0 0
  mev1: ok(inference-posterior-v1(cons(mk-pair("ok", 1.0), nil), inference-metadata-v1(inference-exact-enumeration-v1, true, none, 10, 2))) exit 0
  mlw1: ok(inference-posterior-v1(cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), cons(mk-pair("ok", 0.07692307692307693), nil))))))))))))), inference-metadata-v1(inference-likelihood-weighting-v1, false, some(1), 20, 20))) exit 0

The released `dist.enumerate` explores zero-weight branches too, so unlike the
-v1 drivers it reaches, and refuses, the site behind the zero observation:

  $ for name in obs-neg-first obs-neg-second dead; do
  >   jacquard run "men-$name.jac" > i.out 2>&1; ie=$?
  >   jacquard build "men-$name.jac" -o prog > /dev/null 2>&1 || { echo "REFUSED"; continue; }
  >   ./prog > n.out 2>&1; ne=$?
  >   echo "$name: $(grep -v 'Next step' i.out | tr '\n' ' ')exit $ie"
  >   if ! diff -q i.out n.out > /dev/null || [ "$ie" != "$ne" ]; then echo "DIVERGED native=$ne"; diff i.out n.out; fi
  > done
  obs-neg-first: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  obs-neg-second: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2
  dead: error[E0917]: Inference failed numerically.   Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights exit 2

An enclosing driver reports an inner driver's refusal as its own runtime
failure, with the E0917 diagnostic as the cause, in both engines:

  $ NEG='sample(Categorical([MkPair("a", -1.0), MkPair("b", 2.0)]))'
  $ printf 'dist.sample-lw(fn () -> { let _ = dist.sample-lw-v1(fn () -> %s, 2, 1); 1 }, 2, 1)\n' "$NEG" > nest-v1-in-legacy.jac
  $ printf 'dist.sample-lw-v1(fn () -> { let _ = dist.sample-lw-v1(fn () -> %s, 2, 1); 1 }, 2, 1)\n' "$NEG" > nest-v1-in-v1.jac
  $ printf 'dist.sample-lw(fn () -> { let _ = dist.enumerate-v1(fn () -> %s, 10); 1 }, 2, 1)\n' "$NEG" > nest-enum-in-legacy.jac
  $ for f in nest-v1-in-legacy nest-v1-in-v1 nest-enum-in-legacy; do
  >   echo "== $f"
  >   jacquard run "$f.jac" > i.out 2>&1; ie=$?
  >   jacquard build "$f.jac" -o prog > /dev/null 2>&1 || { echo "REFUSED"; continue; }
  >   ./prog > n.out 2>&1; ne=$?
  >   grep -v 'Next step' i.out; echo "exit $ie"
  >   if diff -q i.out n.out > /dev/null && [ "$ie" = "$ne" ]; then echo native identical; else echo "DIVERGED native=$ne"; diff i.out n.out; fi
  > done
  == nest-v1-in-legacy
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: E0917: Inference failed numerically. (a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights)
  exit 2
  native identical
  == nest-v1-in-v1
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: E0917: Inference failed numerically. (a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights)
  exit 2
  native identical
  == nest-enum-in-legacy
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: E0917: Inference failed numerically. (a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights)
  exit 2
  native identical

Model documents classify the same way:

  $ mkdir md
  $ cat > md/m.jac <<'EOF'
  > empty(n) = sample(Categorical([]))
  > zero(n) = sample(Categorical([MkPair(n, 0.0), MkPair(add(n, 1), 0.0)]))
  > neg(n) = sample(Categorical([MkPair(n, -1.0), MkPair(add(n, 1), 2.0)]))
  > obs(n) = { let x = sample(Categorical([MkPair(n, -1.0), MkPair(add(n, 1), 2.0)])); let _ = observe(Categorical([MkPair(add(n, 1), 1.0)]), x); x }
  > EOF
  $ cat > md/doc.model <<'EOF'
  > jacquard-model format=1
  > source m.jac
  > assumption base = 3
  > result e-enum entry empty args base driver enumerate max-branches=10 fuel=100000
  > result e-lw entry empty args base driver lw seed=7 samples=5 fuel=100000
  > result z-enum entry zero args base driver enumerate max-branches=10 fuel=100000
  > result z-lw entry zero args base driver lw seed=7 samples=5 fuel=100000
  > result n-enum entry neg args base driver enumerate max-branches=10 fuel=100000
  > result n-lw entry neg args base driver lw seed=7 samples=5 fuel=100000
  > result o-enum entry obs args base driver enumerate max-branches=10 fuel=100000
  > result o-lw entry obs args base driver lw seed=7 samples=5 fuel=100000
  > EOF
  $ jacquard model eval md/doc.model --no-cache
  e-enum: uncacheable (no-cache)
    failure E0902
  e-lw: uncacheable (no-cache)
    failure E0902
  z-enum: uncacheable (no-cache)
    impossible (complete, 2 paths explored)
  z-lw: uncacheable (no-cache)
    impossible (sampled, 5 runs)
  n-enum: uncacheable (no-cache)
    numerical (complete, 0 paths explored)
  n-lw: uncacheable (no-cache)
    numerical (sampled, 1 runs)
  o-enum: uncacheable (no-cache)
    numerical (complete, 0 paths explored)
  o-lw: uncacheable (no-cache)
    numerical (sampled, 1 runs)
  [2]

`jacquard dist-diff` enumerates through the same driver, so it refuses the
negative branch a later observation would prune. Its posterior cache key moves
from `dist-diff-v2` to `dist-diff-v3`: an entry written under the old key may
hold a posterior from such a model, and is never served. The same entry
written under the current key is served, so only the key keeps it out:

  $ cat > dd-neg.jqd <<'EOF'
  > (let nonrec (pvar x) (app (var sample) (app (var categorical) (app (var cons) (app (var mk-pair) (lit "a") (lit -1.0)) (app (var cons) (app (var mk-pair) (lit "b") (lit 2.0)) (var nil))))) (let nonrec (pwild) (app (var observe) (app (var categorical) (app (var cons) (app (var mk-pair) (lit "b") (lit 1.0)) (var nil))) (var x)) (var x)))
  > EOF
  $ cat > dd-fair.jqd <<'EOF'
  > (app (var sample) (app (var categorical) (app (var cons) (app (var mk-pair) (lit "a") (lit 1.0)) (app (var cons) (app (var mk-pair) (lit "b") (lit 1.0)) (var nil)))))
  > EOF
  $ jacquard hash dd-neg.jqd > dd-hash; echo "exit $?"
  exit 0
  $ h=$(cut -d' ' -f2 dd-hash)
  $ entry() { mkdir -p "$1"; printf '(posterior\n  (entry (shown "\\"b\\"") 1.0))\n' > "$1/$(printf '%s|%s' "$2" "$h" | sha256sum | cut -d' ' -f1).jqd"; }
  $ entry dd-old dist-diff-v2
  $ jacquard dist-diff dd-neg.jqd dd-fair.jqd --tolerance 0.001 --cache-dir dd-old > dd.out 2>&1; echo "exit $?"; grep -v 'Next step' dd.out
  exit 1
  error[E0917]: Inference failed numerically.
    Cause: a categorical to draw from has a negative weight; enumeration and likelihood weighting draw only from finite, nonnegative weights
  $ entry dd-new dist-diff-v3
  $ jacquard dist-diff dd-neg.jqd dd-fair.jqd --tolerance 0.001 --cache-dir dd-new > dd.out 2>&1; echo "exit $?"; sort dd.out
  exit 0
  P("b"): 1.000000 -> 0.500000 (delta -0.500000)
  dist-diff: cached posterior 4847edc6
  dist-diff: enumerated a0439ad7
  support gained: "a"

Warp: a generator whose weights cannot be drawn from is an error in the
sampled lane and in the exhaustive lane, never a pass:

  $ for name in empty zero negmix; do
  >   case $name in
  >     empty) cat_='(app (var categorical) (var nil))' ;;
  >     zero) cat_='(app (var categorical) (app (var cons) (app (var mk-pair) (lit "a") (lit 0.0)) (app (var cons) (app (var mk-pair) (lit "b") (lit 0.0)) (var nil))))' ;;
  >     negmix) cat_='(app (var categorical) (app (var cons) (app (var mk-pair) (lit "a") (lit -1.0)) (app (var cons) (app (var mk-pair) (lit "b") (lit 2.0)) (var nil))))' ;;
  >   esac
  >   cat > "w-$name.jqd" <<EOF
  > (defterm ((binding law-$name ()
  >   (app (var prop) (lit "$name")
  >     (lam ()
  >       (app (var prop.for)
  >         (lam () (app (var sample) $cat_))
  >         (lam ((pvar x)) (app (var check.true) (var true) (lit "ok")))))))))
  > EOF
  >   echo "== $name sampled"; jacquard test "w-$name.jqd" --seed 3 --no-cache; echo "exit $?"
  >   echo "== $name exhaustive"; jacquard test "w-$name.jqd" --exhaustive --no-cache; echo "exit $?"
  > done
  == empty sampled
  error: Runtime value has the wrong type
    Cause: type error: test runner error: law-empty/empty: arithmetic error: categorical support is empty
    Next step: Pass a value of the type required by this operation.
  exit 2
  == empty exhaustive
  FAIL law-empty/empty (prop: exhaustive refusal)
    ! error[E0902]: Property execution failed during exhaustive verification
        Cause: arithmetic error: categorical support is empty
        Next step: Fix the reported runtime failure and run the property again.
  0 passed, 1 failed, 0 skipped, 0 refused
  exit 1
  == zero sampled
  error: Runtime value has the wrong type
    Cause: type error: test runner error: law-zero/zero: arithmetic error: categorical weights sum to zero; there is nothing to draw
    Next step: Pass a value of the type required by this operation.
  exit 2
  == zero exhaustive
  FAIL law-zero/zero (prop: exhaustive refusal)
    ! error[E0902]: Property execution failed during exhaustive verification
        Cause: arithmetic error: categorical weights sum to zero; there is nothing to draw
        Next step: Fix the reported runtime failure and run the property again.
  0 passed, 1 failed, 0 skipped, 0 refused
  exit 1
  == negmix sampled
  error: Runtime value has the wrong type
    Cause: type error: test runner error: law-negmix/negmix: arithmetic error: categorical weight 0 is -1; a draw needs finite, nonnegative weights
    Next step: Pass a value of the type required by this operation.
  exit 2
  == negmix exhaustive
  FAIL law-negmix/negmix (prop: exhaustive refusal)
    ! error[E0902]: Property execution failed during exhaustive verification
        Cause: arithmetic error: categorical weight 0 is -1; a draw needs finite, nonnegative weights
        Next step: Fix the reported runtime failure and run the property again.
  0 passed, 1 failed, 0 skipped, 0 refused
  exit 1

Warp's sampled lane draws over the same total as the interpreter draw. With
weights whose entry-order sum overflows but whose ascending sum is finite (the
largest float's predecessor with 2^970 + 2^918 and 2^970; the largest float
less three ulps between two weights of one and a half ulps), the heavy entry
carries all but about 1e-16 of the mass, so "never the heavy entry" is
falsified in every entry order, sampled as exhaustively:

  $ W1H=1.7976931348623155e308; W1X=9.979201547673601e291; W1Y=9.9792015476736e291
  $ W2H=1.7976931348623151e308; W2L=2.9937604643020797e292
  $ for order in 1:hxy 1:hyx 1:xhy 1:xyh 1:yhx 1:yxh 2:hlm 2:lhm 2:lmh; do
  >   set_=${order%%:*}; letters=${order#*:}; list='(var nil)'
  >   for letter in $(echo "$letters" | rev | fold -w1); do
  >     case $set_$letter in
  >       1h) w=$W1H ;; 1x) w=$W1X ;; 1y) w=$W1Y ;; 2h) w=$W2H ;; *) w=$W2L ;;
  >     esac
  >     list="(app (var cons) (app (var mk-pair) (lit \"$letter\") (lit $w)) $list)"
  >   done
  >   cat > "w-heavy.jqd" <<EOF
  > (defterm ((binding law-heavy ()
  >   (app (var prop) (lit "never heavy")
  >     (lam ()
  >       (app (var prop.for)
  >         (lam () (app (var sample) (app (var categorical) $list)))
  >         (lam ((pvar x)) (app (var check.true) (app (var bool.not) (app (var text.eq?) (var x) (lit "h"))) (lit "not h")))))))))
  > EOF
  >   jacquard test w-heavy.jqd --seed 3 --no-cache > s.out; se=$?
  >   jacquard test w-heavy.jqd --exhaustive --no-cache > x.out; xe=$?
  >   echo "== $order sampled, exit $se: $(head -1 s.out)"
  >   echo "== $order exhaustive, exit $xe: $(head -1 x.out)"
  > done
  == 1:hxy sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [0])
  == 1:hxy exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 1:hyx sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [0])
  == 1:hyx exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 1:xhy sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [1])
  == 1:xhy exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 1:xyh sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [2])
  == 1:xyh exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 1:yhx sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [1])
  == 1:yhx exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 1:yxh sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [2])
  == 1:yxh exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 2:hlm sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [0])
  == 2:hlm exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 2:lhm sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [1])
  == 2:lhm exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)
  == 2:lmh sampled, exit 1: FAIL law-heavy/never heavy (prop: falsified on case 1 of 100, seed 3; shrunk to 1 choice [2])
  == 2:lmh exhaustive, exit 1: FAIL law-heavy/never heavy (prop: falsified exhaustively)

`VaryValue` draws its value through the same check:

  $ cat > vary.jac <<'JACQUARD'
  > vary-zero =
  >   SameUnder(
  >     "zero mass",
  >     VaryValue(
  >       Categorical([MkPair((1, 2), 0.0)]),
  >       fn (ignored) -> 0))
  > JACQUARD
  $ jacquard test vary.jac --seed 73 --no-cache > vary.out 2>&1; echo "exit $?"
  exit 1
  $ sed -E 's/seed -?[0-9]+/seed <seed>/g' vary.out
  FAIL vary-zero/zero mass (same under value: generator failed, seed <seed>)
    ! VaryValue generator failed: arithmetic error: categorical weights sum to zero; there is nothing to draw
  0 passed, 1 failed, 0 skipped, 0 refused

`jacquard review` validates a Distribution domain by the same rule, and its
sampled cases draw over the same total. Weights that overflow summed in entry
order but not in ascending order are accepted and drawn by their weights in
every order (every sampled case is the heavy `H`, which the new version
scores differently). Sampled cases draw from the support with equal values
merged, so a merged weight or sum that overflows is refused:

  $ cat > rv-old.jac <<'JACQUARD'
  > type Kind = | H | X | Y
  > score : (Kind) ->{} Int
  > score(k) = 0
  > JACQUARD
  $ cat > rv-new.jac <<'JACQUARD'
  > type Kind = | H | X | Y
  > score : (Kind) ->{} Int
  > score(k) = match k { | H -> 1 | X -> 0 | Y -> 0 }
  > JACQUARD
  $ cat > rv-cases.jac <<JACQUARD
  > hxy = Categorical([MkPair(H, $W1H), MkPair(X, $W1X), MkPair(Y, $W1Y)])
  > yxh = Categorical([MkPair(Y, $W1Y), MkPair(X, $W1X), MkPair(H, $W1H)])
  > merged = Categorical([MkPair(H, $W1H), MkPair(Y, $W1Y), MkPair(H, $W1X)])
  > JACQUARD
  $ for d in hxy yxh merged; do
  >   echo "== $d"
  >   jacquard review run --old rv-old.jac --new rv-new.jac --cases rv-cases.jac --entry score --domain $d --sample 20 --seed 7 > rv.out 2>&1; echo "exit $?"
  >   grep -E 'run:|Cause' rv.out
  > done
  == hxy
  exit 1
    20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == yxh
  exit 1
    20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == merged
  exit 3
    Cause: domain `merged`: its weights, after merging equal values, are not finite and non-negative with a positive total

Merging is the same in every order of equal values. When the support's
entry-order sum exceeds half the largest float, each value's weights are summed
in ascending order: three weights of `H` that overflow in some entry orders
(the largest float less two ulps, 1.5 ulps and half an ulp) merge to the
largest float in all six, and a light value whose duplicates sum to just under
half an ulp in ascending order but to exactly half an ulp in some entry orders
does not tie the merged total to infinity beside the largest float. Every order
is accepted and drawn by its weights, sampled and exhaustive:

  $ Q=1.7976931348623153e308; R=2.9937604643020797e292; P=9.9792015476736e291
  $ M=1.7976931348623157e308; B=9.979201547673597e291; L=6.924462078501392e275
  $ : > rv-merge.jac
  $ for o in "$Q $R $P" "$Q $P $R" "$R $Q $P" "$R $P $Q" "$P $Q $R" "$P $R $Q"; do
  >   set -- $o; n=$((n + 1))
  >   echo "h$n = Categorical([MkPair(H, $1), MkPair(X, 1.0), MkPair(H, $2), MkPair(H, $3)])" >> rv-merge.jac
  > done
  $ for o in "$B $L $L" "$L $B $L" "$L $L $B"; do
  >   set -- $o; m=$((m + 1))
  >   echo "y$m = Categorical([MkPair(H, $M), MkPair(Y, $1), MkPair(Y, $2), MkPair(Y, $3)])" >> rv-merge.jac
  > done
  $ for d in h1 h2 h3 h4 h5 h6 y1 y2 y3; do
  >   jacquard review run --old rv-old.jac --new rv-new.jac --cases rv-merge.jac --entry score --domain $d --sample 20 --seed 7 > rv.out 2>&1; se=$?
  >   s=$(grep -E 'run:|Cause' rv.out)
  >   jacquard review run --old rv-old.jac --new rv-new.jac --cases rv-merge.jac --entry score --domain $d > rv.out 2>&1; ee=$?
  >   echo "== $d sampled, exit $se:$s"
  >   echo "== $d exhaustive, exit $ee:$(grep -E 'run:|Cause' rv.out)"
  > done
  == h1 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h1 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h2 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h2 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h3 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h3 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h4 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h4 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h5 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h5 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h6 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == h6 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == y1 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == y1 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == y2 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == y2 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == y3 sampled, exit 1:  20 run: 0 agree, 20 differ, 0 inconclusive, 0 failed in both, 0 unrun.
  == y3 exhaustive, exit 1:  2 run: 1 agree, 1 differ, 0 inconclusive, 0 failed in both, 0 unrun.
