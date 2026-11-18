A task (an async.spawn child or an async.scope body) may leave Async, Channel
and the root-grantable effects unhandled (see task-effects.t): the scheduler and
the root grants handle them. An in-language handler written around the task
never sees those operations, so it must not discharge them either. Outside the
task such an effect E carries a separate label, its root twin `E@task`, that no
handler discharges: it stays in the row and is charged to the root, where
`--allow`, manifests and Warp read it as E. Printed signatures show it as
`E@task` (diagnostics in lowercase), and a written row may name it.

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
  t : () ->{Console@task} Result Text (TaskResult (TaskResult ()))
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
  t : forall a. () ->{Dist@task} List (Pair (TaskResult (TaskResult a)) Real)
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
  fixed : () ->{Clock@task} TaskResult Int
  nested : () ->{Clock@task} TaskResult (TaskResult (TaskResult Int))

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
  handler.jac:6:7-10:2: warning[W0802]: A handler does not handle the operations of a task or an inference model it encloses
    Cause: this handler handles `console`, but a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) in its body also performs `console` and leaves it unhandled; a task or a model runs on a fresh continuation, so those operations go to the root grant, not to this handler, and the row keeps `console@task`
    Next step: Handle the effect inside the thunk passed to async.spawn, async.scope or dist.sample-lw, or grant it at the root.
  quiet : forall a | e. (() ->{Console | e} a) ->{| e} a
  t : () ->{Console@task} TaskResult ()
  u : () ->{Console@task} TaskResult ()
  _ : (TaskResult (), TaskResult ())
  $ jacquard run handler.jac --allow console
  child
  child
  (done(()), done(()))

The warning is best-effort: `u` above uses the same handler through the
wrapper `quiet`, whose handler body row is a parameter row, so only `t` is
warned about; both are charged. Nested handlers of the same effect are each
bypassed, and each is warned about once.

  $ cat > nested-handlers.jac <<'EOF'
  > t() = handle {
  >     handle async.scope(fn () -> print("child\n")) {
  >     | return v -> v
  >     | print(s) resume k -> k(())
  >     | read-line() resume k -> k("")
  >     }
  >   } {
  >   | return v -> v
  >   | print(s) resume k -> k(())
  >   | read-line() resume k -> k("")
  >   }
  > EOF
  $ jacquard check nested-handlers.jac --print-sigs
  nested-handlers.jac:1:7-11:4: warning[W0802]: A handler does not handle the operations of a task or an inference model it encloses
    Cause: this handler handles `console`, but a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) in its body also performs `console` and leaves it unhandled; a task or a model runs on a fresh continuation, so those operations go to the root grant, not to this handler, and the row keeps `console@task`
    Next step: Handle the effect inside the thunk passed to async.spawn, async.scope or dist.sample-lw, or grant it at the root.
  nested-handlers.jac:2:5-6:6: warning[W0802]: A handler does not handle the operations of a task or an inference model it encloses
    Cause: this handler handles `console`, but a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) in its body also performs `console` and leaves it unhandled; a task or a model runs on a fresh continuation, so those operations go to the root grant, not to this handler, and the row keeps `console@task`
    Next step: Handle the effect inside the thunk passed to async.spawn, async.scope or dist.sample-lw, or grant it at the root.
  t : () ->{Console@task} TaskResult ()

Known limit: a handler that re-performs the effect it handles, such as
`fs.read-only`, already keeps the effect in the row, so the grant is the same:
the signature shows `Fs@task` beside `Fs`, but nothing refuses the child's
write, which bypasses the read-only handler. The write happens.

  $ cat > read-only.jac <<'EOF'
  > t() = throw.to-result(fn () -> fs.read-only(fn () -> async.scope(fn () -> {
  >     let c = async.spawn(fn () -> write("out.txt", "written\n"))
  >     async.await(c)
  >   })))
  > t()
  > EOF
  $ jacquard check read-only.jac --print-sigs
  t : () ->{Fs, Fs@task} Result Text (TaskResult (TaskResult ()))
  _ : Result Text (TaskResult (TaskResult ()))
  $ jacquard run read-only.jac --allow fs
  ok(done(done(())))
  $ cat out.txt
  written

A row a programmer writes stays exact: a row that names only Console, closed
or open, does not admit `console@task`, and the diagnostic says what to write.

  $ cat > closed.jac <<'EOF'
  > t : () ->{Console} TaskResult ()
  > t() = async.scope(fn () -> print("child\n"))
  > EOF
  $ jacquard check closed.jac
  closed.jac:2:1-45: error[E0804]: The value does not satisfy its annotation
    Cause: equation definition `t` does not match its signature: expected () ->{console} task-result (), got () ->{console@task | e} task-result () (a closed or rigid effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) leaves to the root grant, which a row naming only the effect does not include: write it in the annotation (`Console@task` for `console@task`) or remove the annotation, or handle the effect inside the task or the model; a row the prelude fixes (Case, Prop, WCase, judge.model's model) cannot name it, so there handle the effect inside the task or the model)
    Next step: Change the value or its annotation so the two types agree.
  [1]
  $ cat > open.jac <<'EOF'
  > t : forall | e. () ->{Console | e} TaskResult ()
  > t() = async.scope(fn () -> print("child\n"))
  > EOF
  $ jacquard check open.jac
  open.jac:2:1-45: error[E0804]: The value does not satisfy its annotation
    Cause: equation definition `t` does not match its signature: expected () ->{console | e} task-result (), got () ->{console@task | e} task-result () (a closed or rigid effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) leaves to the root grant, which a row naming only the effect does not include: write it in the annotation (`Console@task` for `console@task`) or remove the annotation, or handle the effect inside the task or the model; a row the prelude fixes (Case, Prop, WCase, judge.model's model) cannot name it, so there handle the effect inside the task or the model)
    Next step: Change the value or its annotation so the two types agree.
  [1]

A written row may name the twin as `Console@task`, so the signature
`--print-sigs` printed for `t` above can be written back as its annotation,
and an annotated caller can name it too.

  $ cat > spelled.jac <<'EOF'
  > t : () ->{Console@task} TaskResult ()
  > t() = async.scope(fn () -> print("child\n"))
  > u : () ->{Console@task} TaskResult ()
  > u() = t()
  > mixed : forall a. () ->{Dist@task, Console, Console@task} TaskResult a
  > mixed() = { print("p"); async.scope(fn () -> { print("c"); sample(Bernoulli(0.5)) }) }
  > EOF
  $ jacquard check spelled.jac --print-sigs
  t : () ->{Console@task} TaskResult ()
  u : () ->{Console@task} TaskResult ()
  mixed : forall a. () ->{Dist@task, Console, Console@task} TaskResult a
  $ jacquard fmt spelled.jac > spelled.fmt
  $ sed -n 1p spelled.fmt
  t : () ->{Console@task} TaskResult ()

Naming the twin discharges nothing: a handler of Console around a call of the
annotated `t` still leaves `Console@task` in the row, so the program needs the
console grant (the direct handler is warned about).

  $ cat > around.jac <<'EOF'
  > t : () ->{Console@task} TaskResult ()
  > t() = async.scope(fn () -> print("child\n"))
  > scripted() = throw.to-result(fn () -> console.scripted(fn () -> t(), Nil))
  > direct() = handle t() {
  > | return v -> v
  > | print(s) resume k -> k(())
  > | read-line() resume k -> k("")
  > }
  > (scripted(), direct())
  > EOF
  $ jacquard check around.jac --print-sigs
  around.jac:4:12-8:2: warning[W0802]: A handler does not handle the operations of a task or an inference model it encloses
    Cause: this handler handles `console`, but a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) in its body also performs `console` and leaves it unhandled; a task or a model runs on a fresh continuation, so those operations go to the root grant, not to this handler, and the row keeps `console@task`
    Next step: Handle the effect inside the thunk passed to async.spawn, async.scope or dist.sample-lw, or grant it at the root.
  t : () ->{Console@task} TaskResult ()
  scripted : () ->{Console@task} Result Text (TaskResult ())
  direct : () ->{Console@task} TaskResult ()
  _ : (Result Text (TaskResult ()), TaskResult ())
  $ jacquard check around.jac --manifest dist
  around.jac:4:12-8:2: warning[W0802]: A handler does not handle the operations of a task or an inference model it encloses
    Cause: this handler handles `console`, but a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) in its body also performs `console` and leaves it unhandled; a task or a model runs on a fresh continuation, so those operations go to the root grant, not to this handler, and the row keeps `console@task`
    Next step: Handle the effect inside the thunk passed to async.spawn, async.scope or dist.sample-lw, or grant it at the root.
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires console [world/low] — talk to the process terminal, which is not granted (performed via `print`).
    Next step: grant it with --allow console, or handle the effect in the program
  [1]
  $ jacquard run around.jac --allow console
  child
  child
  (ok(done(())), done(()))

Only Channel and the root-grantable effects have a twin; `@task` on any other
effect, including a user effect that reuses a built-in name, is refused.

  $ cat > user-twin.jac <<'EOF'
  > effect Clock where {
  >   once tick : () -> Int
  > }
  > t : () ->{Clock@task} ()
  > t() = ()
  > EOF
  $ jacquard check user-twin.jac
  user-twin.jac:4:8-22: error[E0316]: This effect row names a root twin that does not exist.
    Cause: `clock@task` names a root twin, but the effect `clock` it resolves to has none: only Channel and the built-in root-grantable effects (clock, console, dist, eval, fs, infer, net, secret) have one, the label such an effect carries outside a task that leaves it to the root grant.
    Next step: Remove `@task`, or name Channel or a root-grantable effect before it.
  [1]
  $ cat > async-twin.jac <<'EOF'
  > t : () ->{Async@task} ()
  > t() = ()
  > EOF
  $ jacquard check async-twin.jac
  async-twin.jac:1:8-22: error[E0316]: This effect row names a root twin that does not exist.
    Cause: `async@task` names a root twin, but the effect `async` it resolves to has none: only Channel and the built-in root-grantable effects (clock, console, dist, eval, fs, infer, net, secret) have one, the label such an effect carries outside a task that leaves it to the root grant.
    Next step: Remove `@task`, or name Channel or a root-grantable effect before it.
  [1]
  $ cat > channel-twin.jac <<'EOF'
  > t : () ->{Channel@task} ()
  > t() = ()
  > EOF
  $ jacquard check channel-twin.jac --print-sigs
  t : () ->{Channel@task} ()

A behavior review cannot model a task's operations with `--handle`, since
the handler runs around the task, so a case whose task leaves an effect to
the root is refused.

  $ printf 'route : (Int) ->{Console@task} TaskResult ()\nroute(n) = async.scope(fn () -> print("x"))\n' > route.jac
  $ printf 'sizes = [1]\nquiet(t) = ()\nempty() = ""\n' > route-cases.jac
  $ jacquard review run --old route.jac --new route.jac --cases route-cases.jac --entry route --domain sizes --handle print=quiet --handle read-line=empty
  error[E1012]: A behavior review's domain, field or world is invalid
    Cause: the old case runs a task that leaves effect `Console` to the root grant (`Console@task`); a --handle handler runs around the task and never sees its operations, so handle the effect inside the task
    Next step: Declare each domain as a finite List or Distribution of the parameter's type, keep fields and handlers pure, and --handle every operation the entry performs.
  [3]

The twin survives a store and an export: a definition read back from a store
in a fresh process, annotated with the twin or inferred, is still charged
under a handler written around its call, and an exported `.jqd` file prints
the same signatures.

  $ cat > lib.jac <<'EOF'
  > t : () ->{Console@task} TaskResult ()
  > t() = async.scope(fn () -> print("child\n"))
  > r() = async.scope(fn () -> print("raw\n"))
  > EOF
  $ jacquard run lib.jac --store store
  $ cat > importer.jac <<'EOF'
  > v() = throw.to-result(fn () -> console.scripted(fn () -> { let a = t(); r() }, Nil))
  > v()
  > EOF
  $ jacquard run importer.jac --store store
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires console [world/low] — talk to the process terminal, which is not granted (performed via `v`).
    Next step: grant it with --allow console, or handle the effect in the program
  [3]
  $ jacquard run importer.jac --store store --allow console
  child
  raw
  ok(done(()))
  $ jacquard export lib.jac -o lib.jqd
  $ jacquard check lib.jqd --print-sigs
  t : () ->{Console@task} TaskResult ()
  r : () ->{Console@task} TaskResult ()

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
    Cause: argument: expected () ->{check} (), got () ->{console@task | e} () (a closed or rigid effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) leaves to the root grant, which a row naming only the effect does not include: write it in the annotation (`Console@task` for `console@task`) or remove the annotation, or handle the effect inside the task or the model; a row the prelude fixes (Case, Prop, WCase, judge.model's model) cannot name it, so there handle the effect inside the task or the model)
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
    Cause: argument: expected () ->{dist, check} (), got () ->{dist@task | e} () (a closed or rigid effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) leaves to the root grant, which a row naming only the effect does not include: write it in the annotation (`Console@task` for `console@task`) or remove the annotation, or handle the effect inside the task or the model; a row the prelude fixes (Case, Prop, WCase, judge.model's model) cannot name it, so there handle the effect inside the task or the model)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]

A world case keeps its closed row too, so a task inside a WCase may not leave
Console to the root, while a body annotated with exactly the world's effects
checks.

  $ cat > world.jac <<'EOF'
  > w = wcase("prints in a task", fn () -> {
  >     let r = async.scope(fn () -> print("child\n"))
  >     ()
  >   })
  > EOF
  $ jacquard check world.jac
  world.jac:1:31-4:4: error[E0801]: Types do not agree
    Cause: argument: expected () ->{console, fs, clock, net, check} (), got () ->{console@task | e} () (a closed or rigid effect row cannot absorb extra effects; `name@task` marks an effect a task (an async.spawn child or an async.scope body) or an inference model (a dist.sample-lw thunk) leaves to the root grant, which a row naming only the effect does not include: write it in the annotation (`Console@task` for `console@task`) or remove the annotation, or handle the effect inside the task or the model; a row the prelude fixes (Case, Prop, WCase, judge.model's model) cannot name it, so there handle the effect inside the task or the model)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ cat > world-annotated.jac <<'EOF'
  > body : () ->{Check, Fs, Net, Clock, Console} ()
  > body() = check.true(true, "t")
  > w = wcase("annotated body", body)
  > EOF
  $ jacquard check world-annotated.jac
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
  t : () ->{Console@task} Result Text (TaskResult ())
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
  loud : () ->{Console@task} TaskResult ()
  silent : () ->{} Result Text (TaskResult Int)
  pick : (Bool) ->{Console@task} Result Text (TaskResult ())
