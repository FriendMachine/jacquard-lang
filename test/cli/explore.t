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
  > capped = Case("a capped exploration fails", fn () ->
  >   check.eq(list.length(explore.up-to(5, fn () -> pay-world(both))), 5, int.eq, int.show, "kept"))
  > exact : Test
  > exact = Case("a tree of exactly the limit is complete", fn () ->
  >   check.eq(list.length(explore.up-to(9, fn () -> pay-world(both))), 9, int.eq, int.show, "all"))
  > EOF
  $ jacquard test --cache-dir cache pay.jac; echo "exit:$?"
  FAIL capped/a capped exploration fails (5 executions explored, incomplete)
    ! runtime error: E0905: An exploration stopped at its execution limit. (explore stopped after 5 executions, before every outcome was explored)
  PASS checkout-test/checkout can get stuck (1 check, 7 executions explored, complete)
  PASS exact/a tree of exactly the limit is complete (1 check, 9 executions explored, complete)
  PASS nine/two charges explore nine executions (1 check, 9 executions explored, complete)
  3 passed, 1 failed, 0 skipped, 0 refused
  cache: 0 hit, 4 ran
  FAIL 1 exploration stopped at the execution limit during this run (E0905)
  exit:1

A cached result repeats the count; a test that hit its limit is never cached.

  $ jacquard test --cache-dir cache pay.jac; echo "exit:$?"
  FAIL capped/a capped exploration fails (5 executions explored, incomplete)
    ! runtime error: E0905: An exploration stopped at its execution limit. (explore stopped after 5 executions, before every outcome was explored)
  PASS checkout-test/checkout can get stuck (1 check, 7 executions explored, complete) [cached]
  PASS exact/a tree of exactly the limit is complete (1 check, 9 executions explored, complete) [cached]
  PASS nine/two charges explore nine executions (1 check, 9 executions explored, complete) [cached]
  3 passed, 1 failed, 0 skipped, 0 refused
  cache: 3 hit, 1 ran
  FAIL 1 exploration stopped at the execution limit during this run (E0905)
  exit:1

An exploration that reaches its limit fails wherever it runs, even in a top-level value that
several tests read, so no test can pass on executions it skipped.

  $ cat > shared.jac <<'EOF'
  > multi effect Coin where { flip : () -> Bool }
  > coin-world(body) = handle body() {
  >   | return v -> v
  >   | flip() resume k -> k(explore.branch("flip", [False, True]))
  > }
  > runs = explore.up-to(1, fn () -> coin-world(fn () -> flip()))
  > first : Test
  > first = Case("reads the capped value", fn () -> check.true(list.empty?(runs), "never reached"))
  > EOF
  $ jacquard test shared.jac > shared.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "E0905" shared.out
  2

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
  $ jacquard check fake.jac > fake.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p fake.out
    Cause: No name named `explore.note-v0` is in scope.

`explore.all` explores the same executions as a hand-written exploring handler: on the start-up
benchmark's transfer machine both find 129.

  $ sed -n '/^type Outcome/,/^count(rs, v)/p' ../../bench/startup/transfer.jac > transfer.jac
  $ cat >> transfer.jac <<'EOF'
  > bank-world(body) = handle body() {
  >   | return v -> v
  >   | debit(a, n) resume k -> k(explore.branch("debit", [Ok, Rejected, Timeout]))
  >   | credit(a, n) resume k -> k(explore.branch("credit", [Ok, Rejected, Timeout]))
  >   | journal(t) resume k -> k(())
  > }
  > list.length(runs())
  > list.length(explore.all(fn () -> bank-world(fn () -> transfer("S", "D", 5))))
  > EOF
  $ jacquard run transfer.jac
  129
  129

A tree whose last branch is dead completes exactly at its limit.

  $ cat > dead.jac <<'EOF'
  > multi effect Coin where { flip : () -> Bool }
  > coin-world(body) = handle body() {
  >   | return v -> v
  >   | flip() resume k -> k(explore.branch("flip", [False, True]))
  > }
  > list.length(explore.up-to(1, fn () -> coin-world(fn () -> if flip() then explore.branch("dead", []) else 1)))
  > EOF
  $ jacquard run dead.jac
  1

A program that catches the failure still fails: the test that saw the capped exploration fails
and is not cached, and so does the run.

  $ cat > caught.jac <<'EOF'
  > multi effect Coin where { flip : () -> Bool }
  > coin-world(body) = handle body() {
  >   | return v -> v
  >   | flip() resume k -> k(explore.branch("flip", [False, True]))
  > }
  > caught : Test
  > caught = Case("a task swallows the cap", fn () -> {
  >   let ignored = async.scope(fn () -> list.length(explore.up-to(1, fn () -> coin-world(fn () -> flip()))))
  >   check.true(True, "after")
  > })
  > EOF
  $ jacquard test --cache-dir cache2 caught.jac; echo "exit:$?"
  FAIL caught/a task swallows the cap (1 execution explored, incomplete)
    ! an exploration stopped at its execution limit while this test ran (E0905); a caught failure still fails the test
  0 passed, 1 failed, 0 skipped, 0 refused
  cache: 0 hit, 1 ran
  FAIL 1 exploration stopped at the execution limit during this run (E0905)
  exit:1
  $ jacquard test --cache-dir cache2 caught.jac > again.out; echo "exit:$?"
  exit:1
  $ grep -c cached again.out
  0
  [1]

The failure belongs to the case that caught the cap: its siblings in a group are not failed, and
it stays failed when a later sibling runs out of fuel.

  $ cat > group.jac <<'EOF'
  > multi effect Coin where { flip : () -> Bool }
  > coin-world(body) = handle body() {
  >   | return v -> v
  >   | flip() resume k -> k(explore.branch("flip", [False, True]))
  > }
  > spin(n) = if eq(n, 0) then 0 else spin(int.sub(n, 1))
  > suite : Test
  > suite = Group("g", [
  >   Case("a caught cap", fn () -> {
  >     let ignored = async.scope(fn () -> list.length(explore.up-to(1, fn () -> coin-world(fn () -> flip()))))
  >     check.true(True, "after")
  >   }),
  >   Case("b unrelated", fn () -> check.true(True, "fine")),
  >   Case("c burns fuel", fn () -> check.eq(spin(100000), 0, int.eq, int.show, "spun"))
  > ])
  > EOF
  $ jacquard test group.jac > group.out; echo "exit:$?"
  exit:1
  $ grep -c "PASS suite/g/b unrelated" group.out
  1
  $ grep -c "FAIL suite/g/a caught cap" group.out
  1
  $ jacquard test --fuel 200000 group.jac > fuel.out; echo "exit:$?"
  exit:1
  $ grep -c "PASS suite/g/a caught cap" fuel.out
  0
  [1]
