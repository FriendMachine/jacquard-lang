`explore.all` explores every outcome of every choice point (WARP.1), and `jacquard test` says
how many executions each test explored and whether exploration was complete (TEST.4).

  $ export JACQUARD_PRELUDE=../../prelude

A forwarding handler maps each operation of the user's effect onto `explore.branch`. Two operations
with three outcomes each give nine executions, each with its path.

  $ cat > pay.jac <<'EOF'
  > type Outcome = | Ok | Rejected | Timeout
  > multi effect Pay where {
  >   charge : (Int) -> Outcome
  >   refund : (Int) -> Outcome
  > }
  > checkout() = match charge(5) {
  >   | Ok -> "paid"
  >   | _ -> match refund(5) { | Ok -> "refunded" | _ -> "stuck" }
  > }
  > both() = { let a = charge(1); let b = charge(2); (a, b) }
  > pay-world(body) = handle body() {
  >   | return v -> v
  >   | charge(n) resume k -> k(explore.branch("charge", [Ok, Rejected, Timeout]))
  >   | refund(n) resume k -> k(explore.branch("refund", [Ok, Rejected, Timeout]))
  > }
  > runs(thunk) = explore.all(fn () -> pay-world(thunk))
  > result(run) = match run { | (v, _) -> v }
  > stuck(run) = text.eq?(result(run), "stuck")
  > nine : Test
  > nine = Case("two charges explore nine executions", fn () ->
  >   check.eq(list.length(runs(both)), 9, int.eq, int.show, "executions"))
  > checkout-test : Test
  > checkout-test = Case("checkout can get stuck", fn () ->
  >   check.true(list.any?(runs(checkout), stuck), "some execution is stuck"))
  > capped : Test
  > capped = Case("a capped exploration is incomplete", fn () ->
  >   check.eq(list.length(explore.up-to(5, fn () -> pay-world(both))), 5, int.eq, int.show, "kept"))
  > EOF
  $ jacquard test --cache-dir cache pay.jac; echo "exit:$?"
  INCOMPLETE capped/a capped exploration is incomplete: exploration stopped at its limit (1 check, 5 executions explored, capped)
  PASS checkout-test/checkout can get stuck (1 check, 7 executions explored, complete)
  PASS nine/two charges explore nine executions (1 check, 9 executions explored, complete)
  2 passed, 0 failed, 0 skipped, 0 refused, 1 incomplete
  cache: 0 hit, 3 ran
  exit:2

A cached result repeats the count; the capped test is never cached.

  $ jacquard test --cache-dir cache pay.jac; echo "exit:$?"
  INCOMPLETE capped/a capped exploration is incomplete: exploration stopped at its limit (1 check, 5 executions explored, capped)
  PASS checkout-test/checkout can get stuck (1 check, 7 executions explored, complete) [cached]
  PASS nine/two charges explore nine executions (1 check, 9 executions explored, complete) [cached]
  2 passed, 0 failed, 0 skipped, 0 refused, 1 incomplete
  cache: 2 hit, 1 ran
  exit:2

Each execution carries its path, one `site=index` label per choice made on it, so
executions that stop early have shorter paths.

  $ cat > paths.jac <<'EOF'
  > multi effect Coin where { flip : () -> Bool }
  > coin-world(body) = handle body() {
  >   | return v -> v
  >   | flip() resume k -> k(explore.branch("flip", [False, True]))
  > }
  > explore.all(fn () -> coin-world(fn () -> if flip() then flip() else False))
  > EOF
  $ jacquard run paths.jac
  cons((false, cons("flip=0", nil)), cons((false, cons("flip=1", cons("flip=0", nil))), cons((true, cons("flip=1", cons("flip=1", nil))), nil)))

The runner's report channel is not a public name.

  $ printf 'explore.note-v0(1000, True)\n' > fake.jac
  $ jacquard check fake.jac 2>&1 | sed -n 2p
    Cause: No name named `explore.note-v0` is in scope.
