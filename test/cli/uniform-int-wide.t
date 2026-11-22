Every non-empty `UniformInt` range is drawn inside its bounds, including ranges
whose size exceeds the largest Int, such as `UniformInt(min-int, max-int)` (2^63
values). A range of at most 2^32 values draws the same values as before (one
uniform float scaled by its size, which reaches every value and is uniform to
within a factor below 1 + 1e-6); a larger range is drawn exactly uniformly from
integer RNG bits, with rejection. `pmf` is one over the size,
enumeration refuses a range above 10000 values with its exact size, and the
interpreter and native binaries agree.

  $ export JACQUARD_PRELUDE=$PWD/../../prelude
  $ export JACQUARD_RUNTIME=$PWD/../../runtime
  $ export CC=clang

  $ MIN=-4611686018427387904; MAX=4611686018427387903
  $ cat > ranges <<EOF
  > full|$MIN|$MAX
  > to-max|-1|$MAX
  > from-min|$MIN|0
  > max|$MAX|$MAX
  > min|$MIN|$MIN
  > top-two|4611686018427387902|$MAX
  > wide-shifted|-3|4611686018427387900
  > fits-widest|0|4611686018427387902
  > large-narrow|1152921504606846976|1152921504606846981
  > die|1|6
  > exact-2-32|0|4294967295
  > above-2-32|0|4294967296
  > top-2-32|4611686014132420608|$MAX
  > bottom-2-32|$MIN|-4611686014132420609
  > signed-2-32|-2147483648|2147483647
  > exact-2-53|0|9007199254740991
  > above-2-53|0|9007199254740992
  > top-2-53|4602678819172646912|$MAX
  > bottom-2-53|$MIN|-4602678819172646913
  > EOF

The root sampler, interpreter then native. Seed 1281032's first uniform is
within 2^-20 of 1, and seed 1127518's within 2^-21 of 0:

  $ while IFS='|' read name lo hi; do
  >   printf 'sample(UniformInt(%s, %s))\n' "$lo" "$hi" > "s-$name.jac"
  >   jacquard build "s-$name.jac" -o "s-$name" > /dev/null || echo "REFUSED $name"
  >   for seed in 1 2 3 1281032 1127518; do
  >     i=$(jacquard run "s-$name.jac" --allow dist --seed $seed 2>&1); n=$(./"s-$name" --allow dist --seed $seed 2>&1)
  >     if [ "$i" = "$n" ]; then echo "$name $seed: $i"; else echo "$name $seed: DIVERGED $i | $n"; fi
  >   done
  > done < ranges
  full 1: 613922171173023328
  full 2: 841076844450786151
  full 3: -3565291305925818378
  full 1281032: 4611680769194558108
  full 1127518: -4611684485629987870
  to-max 1: 4098490376910890116
  to-max 2: 2873898384346578323
  to-max 3: 1046394712501569525
  to-max 1281032: 4030425889018428609
  to-max 1127518: 1532797400033
  from-min 1: -513195641516497787
  from-min 2: -1737787634080809580
  from-min 3: -3565291305925818378
  from-min 1281032: -581260129408959294
  from-min 1127518: -4611684485629987870
  max 1: 4611686018427387903
  max 2: 4611686018427387903
  max 3: 4611686018427387903
  max 1281032: 4611686018427387903
  max 1127518: 4611686018427387903
  min 1: -4611686018427387904
  min 2: -4611686018427387904
  min 3: -4611686018427387904
  min 1281032: -4611686018427387904
  min 1127518: -4611686018427387904
  top-two 1: 4611686018427387903
  top-two 2: 4611686018427387903
  top-two 3: 4611686018427387902
  top-two 1281032: 4611686018427387903
  top-two 1127518: 4611686018427387902
  wide-shifted 1: 613922171173023325
  wide-shifted 2: 841076844450786148
  wide-shifted 3: 1046394712501569523
  wide-shifted 1281032: 4611680769194558105
  wide-shifted 1127518: 1532797400031
  fits-widest 1: 613922171173023329
  fits-widest 2: 841076844450786152
  fits-widest 3: 1046394712501569526
  fits-widest 1281032: 4611680769194558109
  fits-widest 1127518: 1532797400034
  large-narrow 1: 1152921504606846979
  large-narrow 2: 1152921504606846979
  large-narrow 3: 1152921504606846976
  large-narrow 1281032: 1152921504606846981
  large-narrow 1127518: 1152921504606846976
  die 1: 4
  die 2: 4
  die 3: 1
  die 1281032: 6
  die 1127518: 1
  exact-2-32 1: 2433363436
  exact-2-32 2: 2539140574
  exact-2-32 3: 487265508
  exact-2-32 1281032: 4294964851
  exact-2-32 1127518: 713
  above-2-32 1: 4227602283
  above-2-32 2: 3265237113
  above-2-32 3: 1593523588
  above-2-32 1281032: 1364690787
  above-2-32 1127518: 3789042302
  top-2-32 1: 4611686016565784044
  top-2-32 2: 4611686016671561182
  top-2-32 3: 4611686014619686116
  top-2-32 1281032: 4611686018427385459
  top-2-32 1127518: 4611686014132421321
  bottom-2-32 1: -4611686015994024468
  bottom-2-32 2: -4611686015888247330
  bottom-2-32 3: -4611686017940122396
  bottom-2-32 1281032: -4611686014132423053
  bottom-2-32 1127518: -4611686018427387191
  signed-2-32 1: 285879788
  signed-2-32 2: 391656926
  signed-2-32 3: -1660218140
  signed-2-32 1281032: 2147481203
  signed-2-32 1127518: -2147482935
  exact-2-53 1: 1432621850635872
  exact-2-53 2: 3407313759873895
  exact-2-53 3: 1559598951614454
  exact-2-53 1281032: 9001950021911196
  exact-2-53 1127518: 1532797400034
  above-2-53 1: 1432621850635292
  above-2-53 2: 3407313759873290
  above-2-53 3: 1559598951614338
  above-2-53 1281032: 4207822149204739
  above-2-53 1127518: 1532797400034
  top-2-53 1: 4604111441023282784
  top-2-53 2: 4606086132932520807
  top-2-53 3: 4604238418124261366
  top-2-53 1281032: 4611680769194558108
  top-2-53 1127518: 4602680351970046946
  bottom-2-53 1: -4610253396576752032
  bottom-2-53 2: -4608278704667514009
  bottom-2-53 3: -4610126419475773450
  bottom-2-53 1281032: -4602684068405476708
  bottom-2-53 1127518: -4611684485629987870

Many draws interleave wide, boundary and narrow ranges in one seeded stream,
so the engines agree only if they consume the same RNG outputs per draw
(`(-1, max-int)` rejects almost half of its bits). Seed 1's draws are shown;
every seed prints a digest of each engine's output, so the values are pinned:

  $ cat > fuzz.jac <<EOF
  > step() = [sample(UniformInt($MIN, $MAX)), sample(UniformInt(-1, $MAX)), sample(UniformInt(1, 6)), sample(UniformInt($MIN, 0)), sample(UniformInt(0, 9007199254740992)), sample(UniformInt(0, 9007199254740991)), sample(UniformInt(0, 4294967296)), sample(UniformInt(0, 4294967295)), sample(UniformInt(-2147483648, 2147483647)), sample(UniformInt(4602678819172646911, $MAX)), sample(UniformInt($MIN, 4611686018427387902)), sample(UniformInt(-4611686018427387903, $MAX)), sample(UniformInt(0, 4611686018427387902)), sample(UniformInt(-3, 4611686018427387900)), sample(UniformInt(-2305843009213693952, 2305843009213693952))]
  > draws(n) = if eq(n, 0) then nil else cons(step(), draws(sub(n, 1)))
  > draws(20)
  > EOF
  $ jacquard build fuzz.jac -o fuzz > /dev/null
  $ jacquard run fuzz.jac --allow dist --seed 1 > seed1.out
  $ cut -c1-200 seed1.out
  cons(cons(613922171173023328, cons(4098490376910890116, cons(3, cons(-1978333202481209644, cons(473095918891166, cons(7580288723658672, cons(1021926361, cons(1953943434, cons(129188310, cons(460653902
  $ for seed in $(seq 1 40); do
  >   i=$(jacquard run fuzz.jac --allow dist --seed $seed) || echo "interpreter failed: $seed"
  >   n=$(./fuzz --allow dist --seed $seed) || echo "native failed: $seed"
  >   echo "$seed $(printf '%s' "$i" | sha256sum | cut -c1-16) $(printf '%s' "$n" | sha256sum | cut -c1-16)"
  > done
  1 35af87847d896e51 35af87847d896e51
  2 ea3f0fc143f6b73a ea3f0fc143f6b73a
  3 c11942b3d42ba0a1 c11942b3d42ba0a1
  4 5fffc0a1291e472c 5fffc0a1291e472c
  5 a1cbe1cf5dec2c29 a1cbe1cf5dec2c29
  6 ab396e6a6e0c31a6 ab396e6a6e0c31a6
  7 61b3c2d1e9f89828 61b3c2d1e9f89828
  8 5c351ce2275049ee 5c351ce2275049ee
  9 954396dc7246cd62 954396dc7246cd62
  10 4880b19679c257c3 4880b19679c257c3
  11 70914d8a106c6f9a 70914d8a106c6f9a
  12 01986c03a479b02e 01986c03a479b02e
  13 33df4033d2100057 33df4033d2100057
  14 91270053b791b5d7 91270053b791b5d7
  15 47f4b64af0974474 47f4b64af0974474
  16 943646f80e80ec4f 943646f80e80ec4f
  17 f48673d58ecfd8da f48673d58ecfd8da
  18 665612cf33f5e2df 665612cf33f5e2df
  19 58aacb1f11944633 58aacb1f11944633
  20 2304608ca7757817 2304608ca7757817
  21 3ede5240968010b5 3ede5240968010b5
  22 438d52728ca95622 438d52728ca95622
  23 2f6cedaf76cced5d 2f6cedaf76cced5d
  24 dba76d1888d5e094 dba76d1888d5e094
  25 029d86ef99fb1c58 029d86ef99fb1c58
  26 5b2ff3447af43436 5b2ff3447af43436
  27 6b04dbb48ca6e0b2 6b04dbb48ca6e0b2
  28 6ae47ef6c1f136f7 6ae47ef6c1f136f7
  29 46e794e488f20dec 46e794e488f20dec
  30 1c8348eccf778eed 1c8348eccf778eed
  31 cd985e4f427cbf5d cd985e4f427cbf5d
  32 d2f9279fb4d14985 d2f9279fb4d14985
  33 906539394a627068 906539394a627068
  34 4b9a23b716eda8d2 4b9a23b716eda8d2
  35 35bcc87746dcba1f 35bcc87746dcba1f
  36 b08fa6f6f1148920 b08fa6f6f1148920
  37 6792bb7e59ff7d78 6792bb7e59ff7d78
  38 69e2bca5e56903c5 69e2bca5e56903c5
  39 f705ad6764ac23b7 f705ad6764ac23b7
  40 f678193b690864d2 f678193b690864d2

`pmf` in and out of range:

  $ cat > pmf.jac <<EOF
  > [pmf(UniformInt($MIN, $MAX), 0), pmf(UniformInt(-1, $MAX), $MAX), pmf(UniformInt(-1, $MAX), -2), pmf(UniformInt($MIN, 0), $MIN), pmf(UniformInt($MAX, $MAX), $MAX), pmf(UniformInt(1152921504606846976, 1152921504606846981), 1152921504606846980)]
  > EOF
  $ jacquard run pmf.jac
  cons(1.0842021724855044e-19, cons(2.168404344971009e-19, cons(0.0, cons(2.168404344971009e-19, cons(1.0, cons(0.16666666666666666, nil))))))
  $ jacquard build pmf.jac -o pmf > /dev/null && ./pmf
  cons(1.0842021724855044e-19, cons(2.168404344971009e-19, cons(0.0, cons(2.168404344971009e-19, cons(1.0, cons(0.16666666666666666, nil))))))

Likelihood weighting draws and scores the wide ranges in both engines:

  $ cat > lw.jac <<EOF
  > dist.sample-lw(fn () -> { let x = sample(UniformInt($MIN, $MAX)); let _ = observe(UniformInt(-1, $MAX), x); lt(x, 0) }, 50, 7)
  > EOF
  $ jacquard run lw.jac
  cons(mk-pair(false, 1.0), cons(mk-pair(true, 0.0), nil))
  $ jacquard build lw.jac -o lw > /dev/null && ./lw
  cons(mk-pair(false, 1.0), cons(mk-pair(true, 0.0), nil))

A model that returns its wide draws themselves shows that both engines draw
the same values under likelihood weighting:

  $ cat > lw-draws.jac <<EOF
  > dist.sample-lw(fn () -> { let x = sample(UniformInt($MIN, $MAX)); let y = sample(UniformInt(-1, $MAX)); let _ = observe(UniformInt(-1, $MAX), y); [x, y] }, 6, 9)
  > EOF
  $ jacquard run lw-draws.jac > lw-draws.i
  $ jacquard build lw-draws.jac -o lw-draws > /dev/null && ./lw-draws > lw-draws.n
  $ cmp lw-draws.i lw-draws.n && cat lw-draws.i
  cons(mk-pair(cons(-2234758809303325453, cons(3752438846058360309, nil)), 0.16666666666666666), cons(mk-pair(cons(-3331366034801352771, cons(1518115710792572885, nil)), 0.16666666666666666), cons(mk-pair(cons(-3589035977316205839, cons(1277182350037771387, nil)), 0.16666666666666666), cons(mk-pair(cons(-3920272737411978962, cons(1561763178347816272, nil)), 0.16666666666666666), cons(mk-pair(cons(3302411963607765365, cons(1997055396173046578, nil)), 0.16666666666666666), cons(mk-pair(cons(91053925613949725, cons(1367069479157711367, nil)), 0.16666666666666666), nil))))))

Enumeration refuses a range above 10000 values and names its exact size:

  $ echo "support(UniformInt($MIN, $MAX))" > sup.jac
  $ jacquard run sup.jac
  error: Arithmetic operation failed
    Cause: arithmetic error: uniform-int -4611686018427387904..4611686018427387903 has 9223372036854775808 outcomes; enumeration caps at 10000
    Next step: Correct the arithmetic inputs and run the program again.
  [2]
  $ jacquard build sup.jac -o sup > /dev/null && ./sup
  error: Arithmetic operation failed
    Cause: arithmetic error: uniform-int -4611686018427387904..4611686018427387903 has 9223372036854775808 outcomes; enumeration caps at 10000
    Next step: Correct the arithmetic inputs and run the program again.
  [2]
  $ echo "sample(UniformInt(-1, $MAX))" > enum.jac
  $ jacquard infer enumerate enum.jac
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: uniform-int -1..4611686018427387903 has 4611686018427387905 outcomes; enumeration caps at 10000
    Next step: Correct the reported model runtime failure and rerun inference.
  [1]

Exact risk enumeration weighs each value of a large-magnitude narrow range by
one over its size (three values here, so `Low` has weight 1/2 + 1/6):

  $ cat > models.jac <<'JAC'
  > m1 : (GovernanceCall) ->{Dist} Risk
  > m1(c) = if sample(Bernoulli(0.5)) then Low else if eq(sample(UniformInt(1152921504606846976, 1152921504606846978)), 1152921504606846976) then Low else High
  > JAC
  $ jacquard hash models.jac > hashes.txt
  $ h=$(awk '$1 ~ /:m1$/ {print $2}' hashes.txt)
  $ cat models.jac - > exact.jac <<JAC
  > call() = governance.make-call("workspace.read-file", quote { arguments("report.txt") }, Nil, "read the release report", quote { preconditions("reviewed") }, None)
  > exact(hex) = match call() {
  >   | Err(msg) -> Err(msg)
  >   | Ok(c) -> match hash.parse(hex) {
  >       | Err(msg) -> Err(msg)
  >       | Ok(h) -> posterior.run-exact-v1(PosteriorRiskModelRefV1(h), PosteriorExactConfigV1(8), quote { source-evidence-v1("fixture") }, c)
  >     }
  > }
  > exact("$h")
  > JAC
  $ jacquard run exact.jac > exact.out; grep -o 'posterior-risk-weights-v1([^)]*)' exact.out
  posterior-risk-weights-v1(0.6666666666666666, 0.0, 0.3333333333333333, 0.0)

A Warp property over the whole Int range runs, replays from its seed, and
shrinks; choice offsets from `lo` print unsigned, so `x = 0` is offset 2^62:

  $ cat > wide-props.jqd <<EOF
  > (defterm ((binding negative ()
  >   (app (var prop) (lit "draws are negative")
  >     (lam ()
  >       (let nonrec (pvar x) (app (var sample) (app (var uniform-int) (lit $MIN) (lit $MAX)))
  >         (app (var check.true) (app (var lt) (var x) (lit 0)) (lit "negative"))))))))
  > EOF
  $ jacquard test wide-props.jqd --seed 3 --samples 20 --no-cache
  FAIL negative/draws are negative (prop: falsified on case 1 of 20, seed 3; shrunk to 1 choice [4611686018427387904])
    - negative
  0 passed, 1 failed, 0 skipped, 0 refused
  [1]
  $ jacquard test wide-props.jqd --seed 3 --samples 20 --no-cache
  FAIL negative/draws are negative (prop: falsified on case 1 of 20, seed 3; shrunk to 1 choice [4611686018427387904])
    - negative
  0 passed, 1 failed, 0 skipped, 0 refused
  [1]

Full-range draws reach odd values, so "never odd" fails. A range above 2^16
values shrinks by trying `lo` first and then halving the distance, whether or
not its size fits in an Int, so "below 1000" over `(0, max-int - 1)` shrinks to
exactly 1000 at once:

  $ cat > more-props.jqd <<EOF
  > (defterm ((binding odd ()
  >   (app (var prop) (lit "never odd")
  >     (lam ()
  >       (let nonrec (pvar x) (app (var sample) (app (var uniform-int) (lit $MIN) (lit $MAX)))
  >         (app (var check.true) (app (var eq) (app (var mod) (var x) (lit 2)) (lit 0)) (lit "even"))))))))
  > (defterm ((binding bigfit ()
  >   (app (var prop) (lit "below 1000")
  >     (lam ()
  >       (let nonrec (pvar x) (app (var sample) (app (var uniform-int) (lit 0) (lit 4611686018427387902)))
  >         (app (var check.true) (app (var lt) (var x) (lit 1000)) (lit "lt"))))))))
  > EOF
  $ jacquard test more-props.jqd --seed 3 --samples 20 --no-cache
  FAIL bigfit/below 1000 (prop: falsified on case 1 of 20, seed 3; shrunk to 1 choice [1000])
    - lt
  FAIL odd/never odd (prop: falsified on case 1 of 20, seed 3; shrunk to 1 choice [3])
    - even
  0 passed, 2 failed, 0 skipped, 0 refused
  [1]

`jacquard dist-diff` caches enumerated posteriors. An earlier driver
enumerated `UniformInt(min-int, max-int)` as empty, so a posterior it cached
lacks that branch; the cache key moves from `dist-diff-v3` to `dist-diff-v4`
and such an entry is never served. The same entry under the current key is
served, so only the key keeps it out:

  $ cat > dd-a.jqd <<EOF
  > (match (app (var sample) (app (var bernoulli) (lit 0.5))) (clause (pcon true) (app (var sample) (app (var uniform-int) (lit $MIN) (lit $MAX)))) (clause (pcon false) (lit 0)))
  > EOF
  $ sed 's/(lit 0)))$/(lit 1)))/' dd-a.jqd > dd-b.jqd
  $ jacquard hash dd-a.jqd > dd-ha; echo "exit $?"
  exit 0
  $ jacquard hash dd-b.jqd > dd-hb; echo "exit $?"
  exit 0
  $ ha=$(cut -d' ' -f2 dd-ha); hb=$(cut -d' ' -f2 dd-hb)
  $ entry() { mkdir -p "$1"; printf '(posterior\n  (entry (shown "%s") 1.0))\n' "$4" > "$1/$(printf '%s|%s' "$2" "$3" | sha256sum | cut -d' ' -f1).jqd"; }
  $ entry dd-old dist-diff-v3 "$ha" 0; entry dd-old dist-diff-v3 "$hb" 1
  $ jacquard dist-diff dd-a.jqd dd-b.jqd --cache-dir dd-old > dd.out 2>&1; echo "exit $?"; grep -v 'Next step' dd.out
  exit 1
  error[E0902]: Probabilistic inference stopped on a runtime failure.
    Cause: arithmetic error: uniform-int -4611686018427387904..4611686018427387903 has 9223372036854775808 outcomes; enumeration caps at 10000
  $ entry dd-new dist-diff-v4 "$ha" 0; entry dd-new dist-diff-v4 "$hb" 1
  $ jacquard dist-diff dd-a.jqd dd-b.jqd --cache-dir dd-new > dd.out 2>&1; echo "exit $?"; sort dd.out
  exit 0
  dist-diff: cached posterior 30e8327d
  dist-diff: cached posterior fd38b9c9
  support gained: 1
  support lost:   0
