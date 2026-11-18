An inference model run by a driver (`dist.sample-lw`, `dist.sample-lw-v1`,
`jacquard infer`, a model document's enumerate or lw result, or a
`posterior.*-v1` builtin) runs on a fresh continuation. The driver handles
Dist, and the root grants handle the root-grantable effects. No handler
written around the driver ever sees the model's other operations, and no
driver has a scheduler (see docs/concurrency.md).

  $ export JACQUARD_PRELUDE=$PWD/../../prelude

A non-grantable effect performed in a `dist.sample-lw` model is refused at
check time (E0838). A handler around the driver call cannot handle it.

  $ cat > emit.jac <<'EOF'
  > t() = emit.collect(fn () -> dist.sample-lw(fn () -> { emit(1); sample(Bernoulli(0.5)) }, 4, 1))
  > t()
  > EOF
  $ jacquard check emit.jac
  emit.jac:1:29-95: error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: an inference model (the thunk passed to dist.sample-lw) performs `emit`, and no handler inside the model handles it; the driver runs the model on a fresh continuation without a scheduler, so only Dist and the root grants reach it, and a handler outside the model never handles its operations
    Next step: Handle the effect inside the thunk passed to dist.sample-lw.
  [1]
  $ cat > throw.jac <<'EOF'
  > t() = throw.to-result(fn () -> dist.sample-lw(fn () -> { let b = sample(Bernoulli(0.5)); if b then throw("x") else 1 }, 4, 1))
  > t()
  > EOF
  $ jacquard check throw.jac
  throw.jac:1:32-126: error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: an inference model (the thunk passed to dist.sample-lw) performs `throw`, and no handler inside the model handles it; the driver runs the model on a fresh continuation without a scheduler, so only Dist and the root grants reach it, and a handler outside the model never handles its operations
    Next step: Handle the effect inside the thunk passed to dist.sample-lw.
  [1]
  $ cat > emit-v1.jac <<'EOF'
  > t() = emit.collect(fn () -> dist.sample-lw-v1(fn () -> { emit(1); sample(Bernoulli(0.5)) }, 4, 1))
  > t()
  > EOF
  $ jacquard check emit-v1.jac
  emit-v1.jac:1:29-98: error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: an inference model (the thunk passed to dist.sample-lw) performs `emit`, and no handler inside the model handles it; the driver runs the model on a fresh continuation without a scheduler, so only Dist and the root grants reach it, and a handler outside the model never handles its operations
    Next step: Handle the effect inside the thunk passed to dist.sample-lw.
  [1]

The scheduler's effects are refused too: a driver has no scheduler.

  $ cat > yield.jac <<'EOF'
  > t() = async.scope(fn () -> dist.sample-lw(fn () -> { async.yield(); sample(Bernoulli(0.5)) }, 2, 1))
  > t()
  > EOF
  $ jacquard check yield.jac
  yield.jac:1:28-100: error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: an inference model (the thunk passed to dist.sample-lw) performs `async`, and no handler inside the model handles it; the driver runs the model on a fresh continuation without a scheduler, so only Dist and the root grants reach it, and a handler outside the model never handles its operations
    Next step: Handle the effect inside the thunk passed to dist.sample-lw.
  [1]
  $ cat > channel.jac <<'EOF'
  > t() = async.scope(fn () -> match channel.open(1) {
  >     | Ok(ch) -> Ok(dist.sample-lw(fn () -> { let s = channel.send(ch, 1); sample(Bernoulli(0.5)) }, 2, 1))
  >     | Err(e) -> Err(e)
  >   })
  > t()
  > EOF
  $ jacquard check channel.jac
  channel.jac:2:20-106: error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: an inference model (the thunk passed to dist.sample-lw) performs `channel`, and no handler inside the model handles it; the driver runs the model on a fresh continuation without a scheduler, so only Dist and the root grants reach it, and a handler outside the model never handles its operations
    Next step: Handle the effect inside the thunk passed to dist.sample-lw.
  [1]

A root-grantable effect a model leaves to the root is charged as its root twin
`E@task`, which no handler discharges, so a handler around the driver call
cannot hide it from the root grant (W0802 warns about such a handler).

  $ cat > print.jac <<'EOF'
  > t() = dist.sample-lw(fn () -> { print("hi\n"); sample(Bernoulli(0.5)) }, 2, 1)
  > t()
  > EOF
  $ jacquard check print.jac --print-sigs
  t : forall a. () ->{Console@task} List (Pair a Real)
  _ : forall a. List (Pair a Real)
  $ jacquard run print.jac
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires console [world/low] — talk to the process terminal, which is not granted (performed via `t`).
    Next step: grant it with --allow console, or handle the effect in the program
  [3]
  $ jacquard run print.jac --allow console
  hi
  hi
  cons(mk-pair(false, 1.0), nil)
  $ cat > scripted.jac <<'EOF'
  > t() = throw.to-result(fn () -> console.scripted(fn () -> dist.sample-lw(fn () -> { print("hi\n"); sample(Bernoulli(0.5)) }, 2, 1), Nil))
  > t()
  > EOF
  $ jacquard check scripted.jac --print-sigs
  t : forall a. () ->{Console@task} Result Text (List (Pair a Real))
  _ : forall a. Result Text (List (Pair a Real))
  $ jacquard run scripted.jac
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires console [world/low] — talk to the process terminal, which is not granted (performed via `t`).
    Next step: grant it with --allow console, or handle the effect in the program
  [3]
  $ cat > quiet.jac <<'EOF'
  > t() = handle dist.sample-lw(fn () -> { print("hi\n"); sample(Bernoulli(0.5)) }, 2, 1) {
  > | return v -> v
  > | print(s) resume k -> k(())
  > | read-line() resume k -> k("")
  > }
  > EOF
  $ jacquard check quiet.jac --print-sigs
  quiet.jac:1:7-5:2: warning[W0802]: A handler does not handle the operations of a task or an inference model it encloses
    Cause: this handler handles `console`, but a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) in its body also performs `console` and leaves it unhandled; a task or a model runs on a fresh continuation, so those operations go to the root grant, not to this handler, and the row keeps `console@task`
    Next step: Handle the effect inside the thunk passed to async.spawn, async.scope or dist.sample-lw, or grant it at the root.
  t : forall a. () ->{Console@task} List (Pair a Real)

A model that runs a scope whose child samples keeps `Dist@task`: that sample
goes to the root, not to the driver.

  $ cat > scope-sample.jac <<'EOF'
  > t() = dist.sample-lw(fn () -> { let r = async.scope(fn () -> sample(Bernoulli(0.5))); sample(Bernoulli(0.5)) }, 2, 1)
  > EOF
  $ jacquard check scope-sample.jac --print-sigs
  t : forall a. () ->{Dist@task} List (Pair a Real)

`async.scope` cannot run inside an inference model: no driver has a scheduler.
Every driver stops with E0922 when the model opens a scope.

  $ cat > scope.jac <<'EOF'
  > t() = dist.sample-lw(fn () -> { let x = sample(Bernoulli(0.5)); async.scope(fn () -> x) }, 2, 1)
  > t()
  > EOF
  $ jacquard check scope.jac --print-sigs
  t : forall a. () ->{} List (Pair (TaskResult a) Real)
  _ : forall a. List (Pair (TaskResult a) Real)
  $ jacquard run scope.jac
  error[E0922]: async.scope cannot run inside an inference model.
    Cause: the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model document's enumerate or lw result, or a posterior builtin) runs the model on a fresh continuation without a scheduler, so a scope cannot run inside it
    Next step: Open the scope outside the inference model and pass its result in.
  [2]
  $ cat > scope-v1.jac <<'EOF'
  > dist.sample-lw-v1(fn () -> { let x = sample(Bernoulli(0.5)); async.scope(fn () -> x) }, 2, 1)
  > EOF
  $ jacquard run scope-v1.jac
  error[E0922]: async.scope cannot run inside an inference model.
    Cause: the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model document's enumerate or lw result, or a posterior builtin) runs the model on a fresh continuation without a scheduler, so a scope cannot run inside it
    Next step: Open the scope outside the inference model and pass its result in.
  [2]
  $ cat > scope-model.jac <<'EOF'
  > { let x = sample(Bernoulli(0.5)); async.scope(fn () -> x) }
  > EOF
  $ jacquard infer enumerate scope-model.jac
  error[E0922]: async.scope cannot run inside an inference model.
    Cause: the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model document's enumerate or lw result, or a posterior builtin) runs the model on a fresh continuation without a scheduler, so a scope cannot run inside it
    Next step: Open the scope outside the inference model and pass its result in.
  [1]
  $ jacquard infer lw --seed 1 --samples 4 scope-model.jac
  error[E0922]: async.scope cannot run inside an inference model.
    Cause: the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model document's enumerate or lw result, or a posterior builtin) runs the model on a fresh continuation without a scheduler, so a scope cannot run inside it
    Next step: Open the scope outside the inference model and pass its result in.
  [1]
  $ cat > m.jac <<'EOF'
  > coin(p) = { let x = sample(Bernoulli(p)); async.scope(fn () -> x) }
  > EOF
  $ cat > doc.model <<'DOC'
  > jacquard-model format=1
  > source m.jac
  > assumption chance = 0.3
  > result flip entry coin args chance driver enumerate max-branches=10 fuel=100000
  > result flip-lw entry coin args chance driver lw seed=7 samples=5 fuel=1000000
  > DOC
  $ jacquard model eval doc.model
  flip: fresh
    failure E0922
  flip-lw: fresh
    failure E0922
  [2]
  $ cat > scope-a.jqd <<'EOF'
  > (let nonrec (pvar x) (app (var sample) (app (var bernoulli) (lit 0.5))) (app (var async.scope) (lam () (lit 1))))
  > EOF
  $ cat > scope-b.jqd <<'EOF'
  > (app (var async.scope) (lam () (lit 2)))
  > EOF
  $ jacquard dist-diff scope-a.jqd scope-b.jqd --tolerance 0.001 --cache-dir dd
  error[E0922]: async.scope cannot run inside an inference model.
    Cause: the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model document's enumerate or lw result, or a posterior builtin) runs the model on a fresh continuation without a scheduler, so a scope cannot run inside it
    Next step: Open the scope outside the inference model and pass its result in.
  [1]

The command-line drivers refuse a model that leaves Dist to the root from a
task: those samples go to the root, so inference never sees them. A model
document keeps such a Dist in the result's world, so it needs the root grant.

  $ cat > twin-model.jac <<'EOF'
  > async.scope(fn () -> sample(Bernoulli(0.5)))
  > EOF
  $ jacquard infer enumerate twin-model.jac
  error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: the model leaves `dist@task` to the root from a task (an async.spawn child or an async.scope body) or a nested inference model; inference never sees those operations
    Next step: Perform the effect in the model body itself, outside any task or nested model, or handle it inside that task or model.
  [1]
  $ jacquard infer lw --seed 1 --samples 4 twin-model.jac
  error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: the model leaves `dist@task` to the root from a task (an async.spawn child or an async.scope body) or a nested inference model; inference never sees those operations
    Next step: Perform the effect in the model body itself, outside any task or nested model, or handle it inside that task or model.
  [1]
  $ cat > child.jac <<'EOF'
  > child(p) = async.scope(fn () -> sample(Bernoulli(p)))
  > EOF
  $ cat > child.model <<'DOC'
  > jacquard-model format=1
  > source child.jac
  > assumption chance = 0.3
  > result kid entry child args chance driver enumerate max-branches=10 fuel=100000
  > DOC
  $ jacquard model eval child.model
  kid: refused
  error[E1806]: A model result needs a root grant that was not given.
    Cause: line 4: result kid requires dist, which only a root grant provides
    Next step: Evaluate with --allow for those effects; such results are never cached.
  [3]

The posterior builtins accept exactly the closed row `{Dist}`. A model whose row
names `Dist@task`, alone or beside Dist, is refused (E1543), and a model that
opens a scope stops with E0922 inside E1544 or E1547.

  $ cat > models.jac <<'EOF'
  > m1 : (GovernanceCall) ->{Dist} Risk
  > m1(c) = if sample(Bernoulli(0.5)) then Low else High
  > m3 : (GovernanceCall) ->{Dist@task} Risk
  > m3(c) = Low
  > m4 : (GovernanceCall) ->{} Risk
  > m4(c) = Low
  > m5 : (GovernanceCall) ->{Dist, Dist@task} Risk
  > m5(c) = if sample(Bernoulli(0.5)) then Low else High
  > m6 : (GovernanceCall) ->{Dist} Risk
  > m6(c) = { let x = if sample(Bernoulli(0.5)) then Low else High; let t = async.scope(fn () -> 1); x }
  > EOF
  $ jacquard hash models.jac > hashes.txt
  $ grep -E '^[0-9]+:m[0-9]' hashes.txt | cut -c1-20
  0:m1 7bc9439b04f389a
  1:m3 55e2c249c7988ac
  2:m4 ecd5b1fb1913230
  3:m5 69528dfbd47362c
  4:m6 354c458fde14626
  $ cat models.jac - > posterior.jac <<'EOF'
  > call() = governance.make-call("workspace.read-file", quote { arguments("report.txt") }, Nil, "read the release report", quote { preconditions("reviewed") }, None)
  > exact(hex) = match call() {
  >   | Err(msg) -> Err(msg)
  >   | Ok(c) -> match hash.parse(hex) {
  >       | Err(msg) -> Err(msg)
  >       | Ok(h) -> match posterior.run-exact-v1(PosteriorRiskModelRefV1(h), PosteriorExactConfigV1(8), quote { source-evidence-v1("fixture") }, c) {
  >           | Err(msg) -> Err(msg)
  >           | Ok(r) -> Ok("exact result")
  >         }
  >     }
  > }
  > sampled(hex) = match call() {
  >   | Err(msg) -> Err(msg)
  >   | Ok(c) -> match hash.parse(hex) {
  >       | Err(msg) -> Err(msg)
  >       | Ok(h) -> match posterior.sample-evidence-v1(PosteriorRiskModelRefV1(h), PosteriorApproximateConfigV1(8, 1), quote { source-evidence-v1("fixture") }, c) {
  >           | Err(msg) -> Err(msg)
  >           | Ok(r) -> Ok("sampled evidence")
  >         }
  >     }
  > }
  > EOF
  $ for m in m1 m3 m4 m5 m6; do h=$(awk -v m="$m" '$1 ~ (":" m "$") {print $2}' hashes.txt); printf '%s\nexact("%s")\n' "$(cat posterior.jac)" "$h" > run-$m.jac; printf '%s\nsampled("%s")\n' "$(cat posterior.jac)" "$h" > sample-$m.jac; echo "$m: $(jacquard run run-$m.jac 2>&1)"; echo "$m: $(jacquard run sample-$m.jac 2>&1)"; done
  m1: ok("exact result")
  m1: ok("sampled evidence")
  m3: err("E1543: model must have the closed signature (GovernanceCall) ->{Dist} Risk; its row names a root twin such as `dist@task`, an effect a task or a nested inference model in the model leaves to the root, which posterior inference never sees")
  m3: err("E1543: model must have the closed signature (GovernanceCall) ->{Dist} Risk; its row names a root twin such as `dist@task`, an effect a task or a nested inference model in the model leaves to the root, which posterior inference never sees")
  m4: err("E1543: model must have the closed signature (GovernanceCall) ->{Dist} Risk")
  m4: err("E1543: model must have the closed signature (GovernanceCall) ->{Dist} Risk")
  m5: err("E1543: model must have the closed signature (GovernanceCall) ->{Dist} Risk; its row names a root twin such as `dist@task`, an effect a task or a nested inference model in the model leaves to the root, which posterior inference never sees")
  m5: err("E1543: model must have the closed signature (GovernanceCall) ->{Dist} Risk; its row names a root twin such as `dist@task`, an effect a task or a nested inference model in the model leaves to the root, which posterior inference never sees")
  m6: err("E1544: exact risk inference failed: E0922: E0922: async.scope cannot run inside an inference model. (the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model document's enumerate or lw result, or a posterior builtin) runs the model on a fresh continuation without a scheduler, so a scope cannot run inside it)")
  m6: err("E1547: approximate risk inference failed: E0922: E0922: async.scope cannot run inside an inference model. (the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model document's enumerate or lw result, or a posterior builtin) runs the model on a fresh continuation without a scheduler, so a scope cannot run inside it)")

Programs that do not leave an unhandled effect to an inference model still
check and run. A parent effect performed after the driver returns is handled
by the parent's handler:

  $ cat > g27.jac <<'EOF'
  > t() = emit.collect(fn () -> { let p = dist.sample-lw(fn () -> sample(Bernoulli(0.5)), 4, 1); emit(1); p })
  > t()
  > EOF
  $ jacquard check g27.jac --print-sigs
  t : forall a. () ->{} (List (Pair a Real), List Int)
  _ : forall a. (List (Pair a Real), List Int)
  $ jacquard run g27.jac
  (cons(mk-pair(false, 0.75), cons(mk-pair(true, 0.25), nil)), cons(1, nil))

A handler inside the model, a nested driver, a driver inside a scope body, and
the typed outcome and `gen` wrappers:

  $ cat > fine.jac <<'EOF'
  > inside() = dist.sample-lw(fn () -> emit.collect(fn () -> { emit(1); sample(Bernoulli(0.5)) }), 2, 1)
  > nested() = dist.sample-lw(fn () -> { let i = dist.sample-lw(fn () -> sample(Bernoulli(0.5)), 2, 7); sample(Bernoulli(0.5)) }, 2, 1)
  > in-scope() = async.scope(fn () -> dist.sample-lw(fn () -> sample(Bernoulli(0.5)), 2, 1))
  > typed() = dist.sample-lw-v1(fn () -> sample(Bernoulli(0.5)), 4, 1)
  > (inside(), nested(), in-scope(), typed())
  > EOF
  $ jacquard check fine.jac --print-sigs
  inside : forall a. () ->{} List (Pair (a, List Int) Real)
  nested : forall a. () ->{} List (Pair a Real)
  in-scope : forall a. () ->{} TaskResult (List (Pair a Real))
  typed : forall a. () ->{} Result InferenceFailureV1 (InferencePosteriorV1 a)
  _ : forall a b c d. (List (Pair (a, List Int) Real), List (Pair b Real), TaskResult (List (Pair c Real)), Result InferenceFailureV1 (InferencePosteriorV1 d))
  $ jacquard run fine.jac
  (cons(mk-pair((false, cons(1, nil)), 1.0), nil), cons(mk-pair(false, 1.0), nil), done(cons(mk-pair(false, 1.0), nil)), ok(inference-posterior-v1(cons(mk-pair(false, 0.25), cons(mk-pair(false, 0.25), cons(mk-pair(false, 0.25), cons(mk-pair(true, 0.25), nil)))), inference-metadata-v1(inference-likelihood-weighting-v1, false, some(1), 4, 4))))

A wrapper of the driver infers two row variables, as a wrapper of `async.scope`
does, and leaves the model's effects to the model. A wrapper annotated with one
row variable for both rows merges them, so a handler around its use is refused
(the known limit of docs/concurrency.md).

  $ cat > wrappers.jac <<'EOF'
  > lw(m) = dist.sample-lw(m, 4, 1)
  > ok() = emit.collect(fn () -> { let p = lw(fn () -> sample(Bernoulli(0.5))); emit(1); p })
  > EOF
  $ jacquard check wrappers.jac --print-sigs
  lw : forall a | e e1. (() ->{Dist | e1} a) ->{| e} List (Pair a Real)
  ok : forall a. () ->{} (List (Pair a Real), List Int)
  $ cat > one-var.jac <<'EOF'
  > lw : forall a | e. (() ->{Dist | e} a) ->{| e} List (Pair a Real)
  > lw(m) = dist.sample-lw(m, 4, 1)
  > t() = emit.collect(fn () -> lw(fn () -> sample(Bernoulli(0.5))))
  > EOF
  $ jacquard check one-var.jac
  one-var.jac:3:7-65: error[E0838]: An effect performed in an inference model is not handled inside the model
    Cause: an inference model (the thunk passed to dist.sample-lw) performs `emit`, and no handler inside the model handles it; the driver runs the model on a fresh continuation without a scheduler, so only Dist and the root grants reach it, and a handler outside the model never handles its operations
    Next step: Handle the effect inside the thunk passed to dist.sample-lw.
  [1]

In-language `dist.enumerate` is a deep handler, not a fresh-continuation
driver: an operation it does not handle reaches the handler around it.

  $ cat > enumerate.jac <<'EOF'
  > t() = emit.collect(fn () -> dist.enumerate(fn () -> { emit(1); sample(Bernoulli(0.5)) }))
  > t()
  > EOF
  $ jacquard check enumerate.jac --print-sigs
  t : forall a. () ->{} (List (Pair a Real), List Int)
  _ : forall a. (List (Pair a Real), List Int)
  $ jacquard run enumerate.jac
  (cons(mk-pair(true, 0.5), cons(mk-pair(false, 0.5), nil)), cons(1, nil))
