The shapes agents most often write on a first draft (DX.8). Each either means what the writer
intended or is refused with the expected form and a fix.

  $ export JACQUARD_PRELUDE=../../prelude

A constructor's positional fields may be declared in parentheses, the way the constructor is
applied and matched. It is the same declaration as the space-separated form, with the same
identity, and the formatter keeps the space-separated spelling.

  $ cat > paren-fields.jac <<'EOF'
  > type World = | World(Bool, Int, List Text)
  > count(w) = match w { | World(_, n, _) -> n }
  > count(World(True, 3, Nil))
  > EOF
  $ cat > space-fields.jac <<'EOF'
  > type World = | World Bool Int (List Text)
  > count(w) = match w { | World(_, n, _) -> n }
  > count(World(True, 3, Nil))
  > EOF
  $ jacquard run paren-fields.jac
  3
  $ jacquard hash paren-fields.jac > paren.hash
  $ jacquard hash space-fields.jac > space.hash
  $ cmp paren.hash space.hash && echo same-identity
  same-identity
  $ jacquard fmt paren-fields.jac > paren-fields.out 2>&1; echo "exit:$?"
  exit:0
  $ head -1 paren-fields.out
  type World = | World Bool Int (List Text)

A first field that prints in parentheses keeps the parenthesized form, since `Log (List Text) Int`
would read back as the field list `(List Text)` followed by a stray `Int`.

  $ printf 'type Log = | Log(List Text, Int)\n' > log.jac
  $ jacquard fmt log.jac
  type Log = | Log(List Text, Int)
  $ jacquard fmt log.jac > log2.jac && jacquard check log2.jac
  ok

Empty parentheses are still refused.

  $ printf 'type U = | U()\n' > empty.jac
  $ jacquard check empty.jac
  empty.jac:1:13-14: error[E1225]: A type or effect declaration is incomplete
    Cause: constructor `U` has empty parentheses; write `U` alone for a constructor without fields
    Next step: Complete the declaration structure shown at this location.
  [1]

`(p)` in a pattern groups, as `(e)` does in an expression; `(p,)` is a one-element tuple. A
return clause written like an operation clause binds the handled result.

  $ cat > return-paren.jac <<'EOF'
  > type Outcome = | Ok | Bad
  > multi effect Pay where {
  >   refund : (Text, Int) -> Outcome
  > }
  > always-ok(thunk) = handle thunk() {
  >   | return(x) -> x
  >   | refund(o, p) resume k -> k(Ok)
  > }
  > main() = always-ok(fn () -> refund("o", 1))
  > first((x,)) = x
  > EOF
  $ jacquard check --print-sigs return-paren.jac
  always-ok : forall a | e. (() ->{Pay | e} a) ->{| e} a
  main : () ->{} Outcome
  first : forall a. ((a,)) ->{} a

An operation clause names its continuation with `resume`, and continues by calling it.

  $ cat > no-resume.jac <<'EOF'
  > multi effect Ask where {
  >   ask : (Text) -> Text
  > }
  > yes(thunk) = handle thunk() {
  >   | return x -> x
  >   | ask(q) k -> k("yes")
  > }
  > EOF
  $ jacquard check no-resume.jac > no-resume.out 2>&1; echo "exit:$?"
  exit:1
  $ head -2 no-resume.out
  no-resume.jac:6:12-13: error[E1220]: Surface syntax is invalid
    Cause: expected `resume` before the continuation binder `k`: write `| op(...) resume k -> body`, then continue with `k(value)`
  $ sed -i 's/| ask(q) k -> k("yes")/| ask(q) resume k -> resume(k, "yes")/' no-resume.jac
  $ jacquard check no-resume.jac > no-resume.out 2>&1; echo "exit:$?"
  exit:1
  $ head -2 no-resume.out
  no-resume.jac:6:24-30: error[E1220]: Surface syntax is invalid
    Cause: `resume` only names the continuation in a handler clause (`| op(x) resume k -> body`); to continue the computation, call the continuation: `k(value)`

Identifier shapes from other languages say what Jacquard expects.

  $ printf 'second(p) = p.1\n' > projection.jac
  $ jacquard check projection.jac > projection.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p projection.out
    Cause: malformed surface identifier `p.1`; tuples have no positional field access: destructure with `let (a, b) = pair` or `match pair { | (a, b) -> ... }`
  $ printf 'totalCount = 1\n' > camel.jac
  $ jacquard check camel.jac > camel.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p camel.out
    Cause: malformed surface identifier `totalCount`; value names are lowercase-kebab (`total-count`, not `totalCount`); types and constructors are PascalCase
  $ printf 'total_count = 1\n' > snake.jac
  $ jacquard check snake.jac > snake.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p snake.out
    Cause: malformed surface identifier `total_count`; value names are lowercase-kebab (`total-count`, not `total_count`)
  $ printf 'f(rec) = 1\n' > reserved.jac
  $ jacquard check reserved.jac > reserved.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p reserved.out
    Cause: expected a pattern, found the reserved word `rec`, which cannot name a value (rename it, or write the escaped name `term:rec` including its backquotes)

Unknown names from other languages suggest the Jacquard function first.

  $ printf 'flip(x) = not(x)\n' > not.jac
  $ jacquard check not.jac > not.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p not.out
    Cause: No name named `not` is in scope; nearby names are `bool.not`, `get`, `int`.
  $ printf 'same(a, b) = int.eq?(a, b)\n' > int-eq.jac
  $ jacquard check int-eq.jac > int-eq.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p int-eq.out
    Cause: No name named `int.eq?` is in scope; nearby names are `eq`, `int.eq`, `int.gt?`.
  $ printf 'size(xs) = len(xs)\n' > len.jac
  $ jacquard check len.jac > len.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p len.out
    Cause: No name named `len` is in scope; nearby names are `list.length`, `eq`, `get`.

A constructor pattern with the wrong number of fields shows the declaration.

  $ cat > arity.jac <<'EOF'
  > type Pair = | Pair(Int, Text)
  > left(p) = match p { | Pair(a) -> a }
  > EOF
  $ jacquard check arity.jac > arity.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p arity.out
    Cause: constructor `Pair` has 2 field(s) but this pattern has 1; it is declared as `Pair : (Int, Text) ->{} Pair`

An operation without a mode is reported once.

  $ cat > mode.jac <<'EOF'
  > effect Pay where {
  >   refund : (Text, Int) -> Int
  > }
  > EOF
  $ jacquard check mode.jac > mode.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c E1236 mode.out
  1

The escaped spelling works where the reserved word cannot.

  $ printf 'f(`term:rec`) = `term:rec`\nf(1)\n' > escaped.jac
  $ jacquard run escaped.jac
  1

Idioms are offered only where a value is expected: an unknown type is not told about
`list.map`.

  $ printf 'x : Map\nx = 1\n' > type-idiom.jac
  $ jacquard check type-idiom.jac > type-idiom.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "list.map" type-idiom.out
  0
  [1]

Comments written inside a parenthesized field list or a grouping pattern survive
formatting, and the result has the same identity.

  $ cat > commented.jac <<'EOF'
  > type T = | C(
  >   -- the count
  >   Int,
  >   List Text -- the names
  > )
  > f(t) = match t {
  >   | C(n, (
  >     -- the names
  >     names)) -> n
  > }
  > EOF
  $ jacquard fmt commented.jac > commented-fmt.jac; echo "exit:$?"
  exit:0
  $ grep -c -- "--" commented-fmt.jac
  3
  $ jacquard hash commented.jac > a.hash; jacquard hash commented-fmt.jac > b.hash; cmp a.hash b.hash && echo same-identity
  same-identity

Two redundant clauses, one nested in the other, are both reported in the recovery report
(the report merges only the parser's and the lowering's report of one missing mode).

  $ cat > nested.jac <<'EOF'
  > f(x) = match x {
  >   | _ -> 0
  >   | n -> match n { | _ -> 1 | m -> m }
  > }
  > g() = ]
  > EOF
  $ jacquard check nested.jac > nested.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c W0801 nested.out
  2
