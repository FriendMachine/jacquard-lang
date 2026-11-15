A task (an async.spawn child or an async.scope body) may leave Async, Channel
and the root-grantable effects unhandled (see task-effects.t): the scheduler and
the root grants handle them. An in-language handler written around the task
never sees those operations, so it must not discharge them either. Outside the
task such an effect E carries a separate label, its root twin `E@task`, that no
handler discharges: it stays in the row and is charged to the root, where
`--allow`, manifests and Warp read it as E. Printed signatures show E;
diagnostics show `E@task`.

  $ export JACQUARD_PRELUDE=$PWD/../../prelude

A scripted console around a scope whose child prints formerly checked as pure,
and printed through the root console. The child's Console is now charged.

  $ cat > scripted.jac <<'EOF'
  > t() = throw.to-result(fn () -> console.scripted(fn () -> async.scope(fn () -> {
  >     let c = async.spawn(fn () -> print("child\n"))
  >     async.await(c)
  >   }), Nil))
  > t()
  > EOF
  $ jacquard check scripted.jac --print-sigs
  t : () ->{Console} Result Text (TaskResult (TaskResult ()))
  _ : Result Text (TaskResult (TaskResult ()))
  $ jacquard check scripted.jac --manifest dist
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires console [world/low] — talk to the process terminal, which is not granted (performed via `print`).
    Next step: grant it with --allow console, or handle the effect in the program
  [1]
  $ jacquard run scripted.jac
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires console [world/low] — talk to the process terminal, which is not granted (performed via `t`).
    Next step: grant it with --allow console, or handle the effect in the program
  [3]
  $ jacquard run scripted.jac --allow console
  child
  ok(done(done(())))

`dist.enumerate` around a scope that samples does not enumerate the child's
sample, which goes to the root Dist grant: Dist stays in the row.

  $ cat > enumerate.jac <<'EOF'
  > t() = dist.enumerate(fn () -> async.scope(fn () -> {
  >     let c = async.spawn(fn () -> sample(Bernoulli(0.5)))
  >     async.await(c)
  >   }))
  > t()
  > EOF
  $ jacquard check enumerate.jac --print-sigs
  t : forall a. () ->{Dist} List (Pair (TaskResult (TaskResult a)) Real)
  _ : forall a. List (Pair (TaskResult (TaskResult a)) Real)
  $ jacquard run enumerate.jac --seed 1
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires dist [uncertainty/none] — denote and condition finite possibilities, which is not granted (performed via `t`).
    Next step: grant it with --allow dist, or handle the effect in the program
  [3]
  $ jacquard run enumerate.jac --allow dist --seed 1
  cons(mk-pair(done(done(false)), 1.0), nil)

`clock.fixed` around a scope whose body reads the clock is charged the same
way, as is a handler between a child and its nested scope.

  $ cat > nested.jac <<'EOF'
  > fixed() = clock.fixed(fn () -> async.scope(fn () -> now()), 7)
  > nested() = async.scope(fn () -> {
  >     let c = async.spawn(fn () -> clock.fixed(fn () -> async.scope(fn () -> now()), 7))
  >     async.await(c)
  >   })
  > EOF
  $ jacquard check nested.jac --print-sigs
  fixed : () ->{Clock} TaskResult Int
  nested : () ->{Clock} TaskResult (TaskResult (TaskResult Int))

A handler written directly in the program around such a task is warned about
(W0802): its clauses never run for the task's operations.

  $ cat > handler.jac <<'EOF'
  > quiet(thunk) = handle thunk() {
  > | return v -> v
  > | print(s) resume k -> k(())
  > | read-line() resume k -> k("")
  > }
  > t() = handle async.scope(fn () -> print("child\n")) {
  > | return v -> v
  > | print(s) resume k -> k(())
  > | read-line() resume k -> k("")
  > }
  > u() = quiet(fn () -> async.scope(fn () -> print("child\n")))
  > (t(), u())
  > EOF
  $ jacquard check handler.jac --print-sigs
  handler.jac:6:7-10:2: warning[W0802]: A handler does not handle the operations of a task it encloses
    Cause: this handler handles `console`, but a task (an async.spawn child or an async.scope body) in its body also performs `console` and leaves it unhandled; a task runs on a fresh continuation, so those operations go to the root grant, not to this handler, and the row keeps `console@task`
    Next step: Handle the effect inside the thunk passed to async.spawn or async.scope, or grant it at the root.
  quiet : forall a | e. (() ->{Console | e} a) ->{| e} a
  t : () ->{Console} TaskResult ()
  u : () ->{Console} TaskResult ()
  _ : (TaskResult (), TaskResult ())
  $ jacquard run handler.jac --allow console
  child
  child
  (done(()), done(()))

The warning is best-effort: `u` above uses the same handler through the
wrapper `quiet`, whose handler body row is a parameter row, so only `t` is
warned about; both are charged.

Known limit: a handler that re-performs the effect it handles, such as
`fs.read-only`, already keeps the effect in the row, so the charge cannot show
that the child's write bypasses it. The write happens.

  $ cat > read-only.jac <<'EOF'
  > t() = throw.to-result(fn () -> fs.read-only(fn () -> async.scope(fn () -> {
  >     let c = async.spawn(fn () -> write("out.txt", "written\n"))
  >     async.await(c)
  >   })))
  > t()
  > EOF
  $ jacquard check read-only.jac --print-sigs
  t : () ->{Fs} Result Text (TaskResult (TaskResult ()))
  _ : Result Text (TaskResult (TaskResult ()))
  $ jacquard run read-only.jac --allow fs
  ok(done(done(())))
  $ cat out.txt
  written

A row a programmer writes stays exact: a closed row that names Console does not
admit `console@task`, and the diagnostic says why.

  $ cat > closed.jac <<'EOF'
  > t : () ->{Console} TaskResult ()
  > t() = async.scope(fn () -> print("child\n"))
  > EOF
  $ jacquard check closed.jac
  closed.jac:2:1-45: error[E0804]: The value does not satisfy its annotation
    Cause: equation definition `t` does not match its signature: expected () ->{console} task-result (), got () ->{console@task | e} task-result () (a closed effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) leaves to the root grant, and a row that names the effect does not include it: leave the row open or handle the effect inside the task)
    Next step: Change the value or its annotation so the two types agree.
  [1]

A hermetic Warp Case or Prop keeps its closed row as well: a task in its body
may not leave Console or Dist to the root.

  $ cat > hermetic.jac <<'EOF'
  > c = Case("prints in a task", fn () -> {
  >     let r = async.scope(fn () -> print("child\n"))
  >     ()
  >   })
  > EOF
  $ jacquard check hermetic.jac
  hermetic.jac:1:30-4:4: error[E0801]: Types do not agree
    Cause: argument: expected () ->{check} (), got () ->{console@task | e} () (a closed effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) leaves to the root grant, and a row that names the effect does not include it: leave the row open or handle the effect inside the task)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ cat > prop.jac <<'EOF'
  > p = Prop("samples in a task", fn () -> {
  >     let r = async.scope(fn () -> sample(Bernoulli(0.5)))
  >     ()
  >   })
  > EOF
  $ jacquard check prop.jac
  prop.jac:1:31-4:4: error[E0801]: Types do not agree
    Cause: argument: expected () ->{dist, check} (), got () ->{dist@task | e} () (a closed effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) leaves to the root grant, and a row that names the effect does not include it: leave the row open or handle the effect inside the task)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]

A world case's row admits the twins of the effects it lists, so a task inside a
WCase may leave them to the root.

  $ cat > world.jac <<'EOF'
  > w = wcase("prints in a task", fn () -> {
  >     let r = async.scope(fn () -> print("child\n"))
  >     ()
  >   })
  > EOF
  $ jacquard check world.jac
  ok

Programs whose tasks leave nothing to the root are unchanged: a scripted console
around the parent's own print and a pure scope or a pure spawn, and a handler
inside the child.

  $ cat > unchanged.jac <<'EOF'
  > parent() = throw.to-result(fn () -> console.scripted(fn () -> {
  >     print("parent\n")
  >     async.scope(fn () -> 1)
  >   }, Nil))
  > pure-spawn() = throw.to-result(fn () -> console.scripted(fn () -> async.scope(fn () -> {
  >     let c = async.spawn(fn () -> 1)
  >     async.await(c)
  >   }), Nil))
  > inside() = async.scope(fn () -> {
  >     let c = async.spawn(fn () -> throw.to-result(fn () -> console.scripted(fn () -> print("child\n"), Nil)))
  >     async.await(c)
  >   })
  > (parent(), pure-spawn(), inside())
  > EOF
  $ jacquard check unchanged.jac --print-sigs
  parent : () ->{} Result Text (TaskResult Int)
  pure-spawn : () ->{} Result Text (TaskResult (TaskResult Int))
  inside : () ->{} TaskResult (TaskResult (Result Text ()))
  _ : (Result Text (TaskResult Int), Result Text (TaskResult (TaskResult Int)), TaskResult (TaskResult (Result Text ())))
  $ jacquard run unchanged.jac
  (ok(done(1)), ok(done(done(1))), done(done(ok(()))))

When both the parent and a child print under one handler, the parent's print is
handled and the child's is charged.

  $ cat > both.jac <<'EOF'
  > t() = throw.to-result(fn () -> console.scripted(fn () -> {
  >     print("parent\n")
  >     async.scope(fn () -> print("child\n"))
  >   }, Nil))
  > t()
  > EOF
  $ jacquard check both.jac --print-sigs
  t : () ->{Console} Result Text (TaskResult ())
  _ : Result Text (TaskResult ())
  $ jacquard run both.jac --allow console
  child
  ok(done(()))

A polymorphic helper keeps each use independent, and joining a printing scope
with a pure function under a handler charges the printing branch's Console.

  $ cat > helper.jac <<'EOF'
  > go(g) = async.scope(g)
  > loud() = go(fn () -> print("loud\n"))
  > silent() = throw.to-result(fn () -> console.scripted(fn () -> go(fn () -> 1), Nil))
  > pick(b) = throw.to-result(fn () -> console.scripted(fn () -> {
  >     let f = if b then fn () -> async.scope(fn () -> print("x\n")) else fn () -> Done(())
  >     f()
  >   }, Nil))
  > EOF
  $ jacquard check helper.jac --print-sigs
  go : forall a | e e1. (() ->{Async | e1} a) ->{| e} TaskResult a
  loud : () ->{Console} TaskResult ()
  silent : () ->{} Result Text (TaskResult Int)
  pick : (Bool) ->{Console} Result Text (TaskResult ())
