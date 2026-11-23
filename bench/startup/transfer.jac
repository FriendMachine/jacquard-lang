-- Start-up benchmark input: a small transfer state machine and three tests that
-- explore every bank answer with a multi-shot handler (129 executions each).
-- scripts/startup-bench.sh times `jacquard check` and `jacquard test` on it.

type Outcome = | Ok | Rejected | Timeout

multi effect Bank where {
  debit : (Text, Int) -> Outcome
  credit : (Text, Int) -> Outcome
  journal : (Text) -> ()
}

credit-up-to(account, amount, tries) =
  if eq(tries, 0) then False
  else match credit(account, amount) {
    | Ok -> True
    | _ -> credit-up-to(account, amount, int.sub(tries, 1))
  }

transfer(src, dst, amount) =
  match debit(src, amount) {
    | Ok ->
      if credit-up-to(dst, amount, 3) then { journal("done"); "done" }
      else if credit-up-to(src, amount, 3) then { journal("refunded"); "refunded" }
      else { journal("stuck"); "stuck" }
    | _ -> { journal("debit-failed"); "failed" }
  }

-- Every answer of every operation, collecting (result, journal) per execution.
explore(body) =
  handle body() {
    | return v -> fn (log) -> [(v, log)]
    | debit(a, n) resume k -> fn (log) ->
        list.concat([k(Ok)(log), k(Rejected)(log), k(Timeout)(log)])
    | credit(a, n) resume k -> fn (log) ->
        list.concat([k(Ok)(log), k(Rejected)(log), k(Timeout)(log)])
    | journal(t) resume k -> fn (log) -> k(())(Cons(t, log))
  }

runs() = explore(fn () -> transfer("S", "D", 5))(Nil)

result-of(run) = match run { | (v, _) -> v }

count(rs, v) = list.length(list.filter(rs, fn (r) -> text.eq?(result-of(r), v)))

total-test : Test
total-test = Case("every execution is explored", fn () ->
  check.eq(list.length(runs()), 129, int.eq, int.show, "executions"))

journal-test : Test
journal-test = Case("every execution journals once", fn () ->
  check.true(list.all?(runs(), fn (r) -> match r { | (_, log) -> eq(list.length(log), 1) }), "one entry"))

outcome-test : Test
outcome-test = Case("each outcome is reachable", fn () ->
  check.true(bool.all([
    int.gt?(count(runs(), "done"), 0),
    int.gt?(count(runs(), "refunded"), 0),
    int.gt?(count(runs(), "stuck"), 0),
    int.gt?(count(runs(), "failed"), 0)
  ]), "all four outcomes"))
