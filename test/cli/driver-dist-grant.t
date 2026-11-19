An inference driver owns its model's Dist operations. A root `dist` grant
(`--allow dist`, or the seed-0 grant `--dry-run` installs) answers `sample`
outside a driver only: inside `dist.sample-lw`, `dist.sample-lw-v1`, a model
document's enumerate or lw result, a `posterior.*-v1` builtin or a Warp
property, the driver captures `sample` and `observe` first, so a granted run
gives the driver's own result. Other root grants still reach the model.

  $ export JACQUARD_PRELUDE=$PWD/../../prelude
  $ export JACQUARD_RUNTIME=$PWD/../../runtime
  $ export CC=clang

  $ cat > lw.jqd <<'EOF'
  > (app (var dist.sample-lw) (lam () (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))) (lit 5) (lit 42))
  > EOF
  $ cat > lw-s7.jqd <<'EOF'
  > (app (var dist.sample-lw) (lam () (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))) (lit 5) (lit 7))
  > EOF
  $ cat > lw-obs.jqd <<'EOF'
  > (app (var dist.sample-lw)
  >   (lam ()
  >     (let nonrec (pvar c) (app (var sample) (app (var bernoulli) (lit 0.5)))
  >       (let nonrec (pwild)
  >         (app (var observe)
  >           (app (var bernoulli) (match (var c) (clause (pcon true) (lit 0.9)) (clause (pcon false) (lit 0.1))))
  >           (var true))
  >         (var c))))
  >   (lit 200) (lit 42))
  > EOF
  $ cat > lw-v1.jqd <<'EOF'
  > (app (var dist.sample-lw-v1) (lam () (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))) (lit 5) (lit 42))
  > EOF
  $ cat > lw-v1-obs.jqd <<'EOF'
  > (app (var dist.sample-lw-v1)
  >   (lam ()
  >     (let nonrec (pvar c) (app (var sample) (app (var bernoulli) (lit 0.5)))
  >       (let nonrec (pwild)
  >         (app (var observe)
  >           (app (var bernoulli) (match (var c) (clause (pcon true) (lit 0.9)) (clause (pcon false) (lit 0.1))))
  >           (var true))
  >         (var c))))
  >   (lit 4) (lit 42))
  > EOF

The driver's seed decides the result, with or without the grant and whatever
the root seed is:

  $ for f in lw lw-s7 lw-obs lw-v1 lw-v1-obs; do
  >   jacquard run $f.jqd > $f.plain 2>&1; echo "$f plain exit=$?"
  >   for s in 1 2; do
  >     jacquard run $f.jqd --allow dist --seed $s > $f.$s 2>&1; echo "$f seed $s exit=$?"
  >     cmp -s $f.plain $f.$s || echo "$f: the root grant changed the driver result"
  >   done
  > done
  lw plain exit=0
  lw seed 1 exit=0
  lw seed 2 exit=0
  lw-s7 plain exit=0
  lw-s7 seed 1 exit=0
  lw-s7 seed 2 exit=0
  lw-obs plain exit=0
  lw-obs seed 1 exit=0
  lw-obs seed 2 exit=0
  lw-v1 plain exit=0
  lw-v1 seed 1 exit=0
  lw-v1 seed 2 exit=0
  lw-v1-obs plain exit=0
  lw-v1-obs seed 1 exit=0
  lw-v1-obs seed 2 exit=0
  $ cat lw.1 lw-s7.1 lw-obs.1 lw-v1.1 lw-v1-obs.1
  cons(mk-pair(6, 0.6), cons(mk-pair(4, 0.2), cons(mk-pair(5, 0.2), nil)))
  cons(mk-pair(4, 0.4), cons(mk-pair(1, 0.2), cons(mk-pair(2, 0.2), cons(mk-pair(3, 0.2), nil))))
  cons(mk-pair(true, 0.9052734375000013), cons(mk-pair(false, 0.09472656249999985), nil))
  ok(inference-posterior-v1(cons(mk-pair(6, 0.2), cons(mk-pair(6, 0.2), cons(mk-pair(6, 0.2), cons(mk-pair(5, 0.2), cons(mk-pair(4, 0.2), nil))))), inference-metadata-v1(inference-likelihood-weighting-v1, false, some(42), 5, 5)))
  ok(inference-posterior-v1(cons(mk-pair(false, 0.25), cons(mk-pair(false, 0.25), cons(mk-pair(false, 0.25), cons(mk-pair(false, 0.25), nil)))), inference-metadata-v1(inference-likelihood-weighting-v1, false, some(42), 4, 4)))

`--dry-run` installs the dist grant with seed 0; a model's observe is still
the driver's (the dry run's audit trail follows the result):

  $ jacquard run lw-obs.jqd --dry-run > lw-obs.dry 2>&1; echo "exit=$?"
  exit=0
  $ head -1 lw-obs.dry | cmp lw-obs.plain - && echo same-posterior
  same-posterior

A driver no longer draws from the root stream, so a root draw after it is the
first draw of the root seed, as `sample(uniform-int 1 6)` alone gives:

  $ cat > die.jqd <<'EOF'
  > (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))
  > EOF
  $ cat > mixed.jqd <<'EOF'
  > (tuple (app (var dist.sample-lw) (lam () (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))) (lit 3) (lit 42))
  >        (app (var sample) (app (var uniform-int) (lit 1) (lit 6))))
  > EOF
  $ cat > lw3.jqd <<'EOF'
  > (app (var dist.sample-lw) (lam () (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))) (lit 3) (lit 42))
  > EOF
  $ jacquard run lw3.jqd
  cons(mk-pair(6, 1.0), nil)
  $ for s in 1 3; do jacquard run die.jqd --allow dist --seed $s; jacquard run mixed.jqd --allow dist --seed $s; done
  4
  (cons(mk-pair(6, 1.0), nil), 4)
  1
  (cons(mk-pair(6, 1.0), nil), 1)

Other root grants still reach the model:

  $ cat > lw-console.jac <<'EOF'
  > dist.sample-lw(fn () -> { print("in model\n"); sample(Bernoulli(0.5)) }, 2, 42)
  > EOF
  $ jacquard run lw-console.jac --allow console
  in model
  in model
  cons(mk-pair(false, 1.0), nil)
  $ jacquard run lw-console.jac --allow console --allow dist --seed 1
  in model
  in model
  cons(mk-pair(false, 1.0), nil)

Nested drivers each own their model's draws, and a root draw beside them
still follows the root seed:

  $ cat > nested.jqd <<'EOF'
  > (tuple
  >   (app (var dist.sample-lw)
  >     (lam ()
  >       (let nonrec (pvar i) (app (var dist.sample-lw) (lam () (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))) (lit 3) (lit 7))
  >         (tuple (var i) (app (var sample) (app (var bernoulli) (lit 0.5))))))
  >     (lit 4) (lit 42))
  >   (app (var sample) (app (var uniform-int) (lit 1) (lit 6))))
  > EOF
  $ jacquard run nested.jqd --allow dist --seed 1 > nested.1; echo "exit=$?"
  exit=0
  $ jacquard run nested.jqd --allow dist --seed 3 > nested.3; echo "exit=$?"
  exit=0
  $ cat nested.1 nested.3
  (cons(mk-pair((cons(mk-pair(4, 0.6666666666666666), cons(mk-pair(3, 0.3333333333333333), nil)), false), 1.0), nil), 4)
  (cons(mk-pair((cons(mk-pair(4, 0.6666666666666666), cons(mk-pair(3, 0.3333333333333333), nil)), false), 1.0), nil), 1)

A recording lists the driver's draws as captured steps (`result missing`),
with or without the grant:

  $ jacquard run lw.jqd --record plain.log > /dev/null; echo "exit=$?"
  exit=0
  $ jacquard run lw.jqd --allow dist --seed 1 --record granted.log > /dev/null; echo "exit=$?"
  exit=0
  $ grep -c '^result missing' plain.log granted.log
  plain.log:5
  granted.log:5

A task's draw is charged to the root grant (`Dist@task`), and a driver inside
another task still owns its model's draws:

  $ cat > tasks.jac <<'EOF'
  > t() = async.scope(fn () -> {
  >     let a = async.spawn(fn () -> sample(UniformInt(1, 6)))
  >     let b = async.spawn(fn () -> dist.sample-lw(fn () -> sample(UniformInt(1, 6)), 3, 42))
  >     (async.await(a), async.await(b))
  >   })
  > t()
  > EOF
  $ jacquard check tasks.jac --print-sigs
  t : () ->{Dist@task} TaskResult (TaskResult Int, TaskResult (List (Pair Int Real)))
  _ : TaskResult (TaskResult Int, TaskResult (List (Pair Int Real)))
  $ jacquard run tasks.jac --allow dist --seed 1
  done((done(4), done(cons(mk-pair(6, 1.0), nil))))
  $ jacquard run tasks.jac --allow dist --seed 3
  done((done(1), done(cons(mk-pair(6, 1.0), nil))))

Model documents: the enumerate result explores both paths and the lw result
follows the document's seed:

  $ cat > m.jac <<'EOF'
  > coin(p) = sample(Bernoulli(p))
  > EOF
  $ cat > doc.model <<'EOF'
  > jacquard-model format=1
  > source m.jac
  > assumption chance = 0.5
  > result flip entry coin args chance driver enumerate max-branches=10 fuel=100000
  > result flip-lw entry coin args chance driver lw seed=7 samples=50 fuel=1000000
  > EOF
  $ jacquard model eval doc.model --cache mc > doc.plain; echo "exit=$?"
  exit=0
  $ cat doc.plain
  flip: fresh
    posterior complete, 2 paths explored
      0.500000  false#c665b4997cada5268e43d722a9da3883b9eddd5e10ef5b1d39ee5c0034390e8c
      0.500000  true#bf5c9d86f11ef2591a2f1b7b9dcbc26342dcb093fce099341ce56e14b75482fb
  flip-lw: fresh
    posterior sampled, 50 runs
      0.560000  true#bf5c9d86f11ef2591a2f1b7b9dcbc26342dcb093fce099341ce56e14b75482fb
      0.440000  false#c665b4997cada5268e43d722a9da3883b9eddd5e10ef5b1d39ee5c0034390e8c
  $ for s in 1 2; do jacquard model eval doc.model --cache mc --allow dist --seed $s > doc.$s; echo "exit=$?"; grep -v '^flip' doc.plain > a; grep -v '^flip' doc.$s > b; cmp -s a b || echo "the root grant changed a model result"; done
  exit=0
  exit=0

The posterior builtins: exact risk enumeration explores both branches and the
sampled evidence follows its configured seed:

  $ cat > models.jac <<'EOF'
  > m1 : (GovernanceCall) ->{Dist} Risk
  > m1(c) = if sample(Bernoulli(0.5)) then Low else High
  > EOF
  $ jacquard hash models.jac > hashes.txt
  $ h=$(awk '$1 ~ /:m1$/ {print $2}' hashes.txt)
  $ cat models.jac - > posterior.jac <<'EOF'
  > call() = governance.make-call("workspace.read-file", quote { arguments("report.txt") }, Nil, "read the release report", quote { preconditions("reviewed") }, None)
  > exact(hex) = match call() {
  >   | Err(msg) -> Err(msg)
  >   | Ok(c) -> match hash.parse(hex) {
  >       | Err(msg) -> Err(msg)
  >       | Ok(h) -> posterior.run-exact-v1(PosteriorRiskModelRefV1(h), PosteriorExactConfigV1(8), quote { source-evidence-v1("fixture") }, c)
  >     }
  > }
  > sampled(hex) = match call() {
  >   | Err(msg) -> Err(msg)
  >   | Ok(c) -> match hash.parse(hex) {
  >       | Err(msg) -> Err(msg)
  >       | Ok(h) -> posterior.sample-evidence-v1(PosteriorRiskModelRefV1(h), PosteriorApproximateConfigV1(8, 1), quote { source-evidence-v1("fixture") }, c)
  >     }
  > }
  > EOF
  $ printf '%s\nexact("%s")\n' "$(cat posterior.jac)" "$h" > exact.jac
  $ printf '%s\nsampled("%s")\n' "$(cat posterior.jac)" "$h" > sampled.jac
  $ jacquard run exact.jac > exact.plain; grep -o 'posterior-risk-weights-v1([^)]*)' exact.plain
  posterior-risk-weights-v1(0.5, 0.0, 0.5, 0.0)
  $ jacquard run sampled.jac > sampled.plain; grep -o 'posterior-risk-belief-v1([^)]*)' sampled.plain
  posterior-risk-belief-v1(0.25, 0.0, 0.75, 0.0)
  $ for s in 1 2 3; do
  >   jacquard run exact.jac --allow dist --seed $s > exact.$s || echo "exact: seed $s failed"
  >   cmp -s exact.plain exact.$s || echo "exact: seed $s changed the result"
  >   jacquard run sampled.jac --allow dist --seed $s > sampled.$s || echo "sampled: seed $s failed"
  >   cmp -s sampled.plain sampled.$s || echo "sampled: seed $s changed the result"
  > done

Warp properties own their draws: the grant changes neither the exhaustive
verdict nor the sampled counterexample, and a cached verdict is the same with
and without it:

  $ cat > props.jqd <<'EOF'
  > (defterm ((binding needle ()
  >   (app (var prop) (lit "avoids 3")
  >     (lam ()
  >       (let nonrec (pvar x) (app (var sample) (app (var uniform-int) (lit 0) (lit 9)))
  >         (app (var check.true) (app (var bool.not) (app (var eq) (var x) (lit 3))) (lit "not 3"))))))))
  > EOF
  $ jacquard test props.jqd --exhaustive --no-cache --allow dist; echo "exit=$?"
  FAIL needle/avoids 3 (prop: falsified exhaustively)
    - not 3
  0 passed, 1 failed, 0 skipped, 0 refused
  exit=1
  $ jacquard test props.jqd --seed 42 --samples 50 --no-cache > sampled.plain; echo "exit=$?"
  exit=1
  $ jacquard test props.jqd --seed 42 --samples 50 --no-cache --allow dist > sampled.granted; echo "exit=$?"
  exit=1
  $ cmp sampled.plain sampled.granted && cat sampled.granted
  FAIL needle/avoids 3 (prop: falsified on case 10 of 50, seed 42; shrunk to 1 choice [3])
    - not 3
  0 passed, 1 failed, 0 skipped, 0 refused
  $ jacquard test props.jqd --exhaustive --cache-dir wc --allow dist; echo "exit=$?"
  FAIL needle/avoids 3 (prop: falsified exhaustively)
    - not 3
  0 passed, 1 failed, 0 skipped, 0 refused
  cache: 0 hit, 1 ran
  exit=1
  $ jacquard test props.jqd --exhaustive --cache-dir wc; echo "exit=$?"
  FAIL needle/avoids 3 (prop: falsified exhaustively) [cached]
    - not 3
  0 passed, 1 failed, 0 skipped, 0 refused
  cache: 1 hit, 0 ran
  exit=1

The native runtime gives the same results: its likelihood-weighting driver
intercepts the model's sample and observe before the root grant.

  $ for f in lw lw-s7 lw-obs mixed; do
  >   jacquard build $f.jqd -o n-$f > /dev/null || echo "build $f failed"
  >   ./n-$f > $f.nplain 2>&1; echo "$f native exit=$?"
  >   for s in 1 3; do
  >     ./n-$f --allow dist --seed $s > $f.n$s 2>&1; echo "$f native seed $s exit=$?"
  >     jacquard run $f.jqd --allow dist --seed $s > $f.i$s 2>&1
  >     cmp -s $f.i$s $f.n$s || echo "$f: native differs from the interpreter at seed $s"
  >   done
  > done
  lw native exit=0
  lw native seed 1 exit=0
  lw native seed 3 exit=0
  lw-s7 native exit=0
  lw-s7 native seed 1 exit=0
  lw-s7 native seed 3 exit=0
  lw-obs native exit=0
  lw-obs native seed 1 exit=0
  lw-obs native seed 3 exit=0
  mixed native exit=3
  mixed native seed 1 exit=0
  mixed native seed 3 exit=0
  $ for f in lw lw-s7 lw-obs; do for s in 1 3; do cmp -s $f.plain $f.n$s || echo "$f: the root grant changed the native driver result"; done; done
  $ cat mixed.n1 mixed.n3
  (cons(mk-pair(6, 1.0), nil), 4)
  (cons(mk-pair(6, 1.0), nil), 1)
