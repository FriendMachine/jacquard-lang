Granting dist installs the SAMPLING handler (stdlib SL.7): sample draws one
value; the seed makes runs reproducible.

  $ export JACQUARD_PRELUDE=../../prelude

  $ cat > die.jqd <<'JACQUARD'
  > (app (var sample) (app (var uniform-int) (lit 1) (lit 6)))
  > JACQUARD

  $ jacquard run die.jqd --allow dist --seed 42
  5
  $ jacquard run die.jqd --allow dist --seed 42
  5
  $ jacquard run die.jqd --allow dist --seed 7
  3

Without the grant, the manifest refuses to start (exit 3):

  $ jacquard run die.jqd
  error[E0814]: The program requires an effect that was not granted
    Cause: This program requires dist [uncertainty/none] — denote and condition finite possibilities, which is not granted (performed via `sample`).
    Next step: grant it with --allow dist, or handle the effect in the program
  [3]

Observe reaching the sampling root is a defect (decision D7's default): jacquard
run cannot condition, only jacquard infer can.

  $ cat > obs.jqd <<'JACQUARD'
  > (app (var observe) (app (var bernoulli) (lit 0.5)) (var true))
  > JACQUARD

  $ jacquard run obs.jqd --allow dist --seed 1
  error[E0904]: Observation is invalid at the sampling root
    Cause: observe reached the sampling root handler; observation requires an inference driver (use jacquard infer)
    Next step: Move the observation under an inference handler.
  [2]

The die model runs unchanged under exact enumeration — same program, different
handler (the M3 thesis):

  $ jacquard infer enumerate die.jqd
  0.166667  1
  0.166667  2
  0.166667  3
  0.166667  4
  0.166667  5
  0.166667  6

Bernoulli and UniformInt build distributions over Bool and Int. Their
declaration does not mention the element type, so the checker types a
construction by what every eliminator produces: Bernoulli(p) is a
Distribution Bool and UniformInt(lo, hi) a Distribution Int. A draw used at
another type is refused before anything runs, instead of failing at run time
(or silently giving a zero probability or a NaN weight).

  $ cat > coin-text.jac <<'EOF'
  > text.length(sample(Bernoulli(0.5)))
  > EOF
  $ jacquard check coin-text.jac
  coin-text.jac:1:13-35: error[E0801]: Types do not agree
    Cause: argument: expected text, got bool (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ jacquard run coin-text.jac --allow dist --seed 1
  coin-text.jac:1:13-35: error[E0801]: Types do not agree
    Cause: argument: expected text, got bool (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ printf 'int.add(sample(Bernoulli(0.5)), 1)\n' > coin-int.jac
  $ jacquard check coin-int.jac
  coin-int.jac:1:9-31: error[E0801]: Types do not agree
    Cause: argument: expected int, got bool (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ printf 'text.length(sample(UniformInt(1, 6)))\n' > die-text.jac
  $ jacquard check die-text.jac
  die-text.jac:1:13-37: error[E0801]: Types do not agree
    Cause: argument: expected text, got int (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ printf 'pmf(Bernoulli(0.5), "x")\n' > pmf-text.jac
  $ jacquard check pmf-text.jac
  pmf-text.jac:1:21-24: error[E0801]: Types do not agree
    Cause: argument: expected bool, got text (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ printf 'dist.enumerate(fn () -> { observe(Bernoulli(0.5), 3); 1 })\n' > observe-int.jac
  $ jacquard check observe-int.jac
  observe-int.jac:1:51-52: error[E0801]: Types do not agree
    Cause: argument: expected bool, got int (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ printf 'text.length(dist.named("d", UniformInt(1, 2)))\n' > named-text.jac
  $ jacquard check named-text.jac
  named-text.jac:1:13-46: error[E0801]: Types do not agree
    Cause: argument: expected text, got int (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]
  $ cat > annotated.jac <<'EOF'
  > coins : () ->{} Distribution Text
  > coins() = Bernoulli(0.5)
  > EOF
  $ jacquard check annotated.jac
  annotated.jac:2:1-25: error[E0804]: The value does not satisfy its annotation
    Cause: equation definition `coins` does not match its signature: expected () ->{} distribution text, got () ->{} distribution bool (type mismatch)
    Next step: Change the value or its annotation so the two types agree.
  [1]
  $ cat > anything.jac <<'EOF'
  > anything : forall a. () ->{Dist} a
  > anything() = sample(Bernoulli(0.5))
  > EOF
  $ jacquard check anything.jac
  anything.jac:2:1-36: error[E0804]: The value does not satisfy its annotation
    Cause: equation definition `anything` does not match its signature: expected () ->{dist} a, got () ->{dist} bool (type mismatch)
    Next step: Change the value or its annotation so the two types agree.
  [1]
  $ cat > first-class.jac <<'EOF'
  > ranges : (List Real) ->{} List (Distribution Int)
  > ranges(ps) = list.map(ps, Bernoulli)
  > EOF
  $ jacquard check first-class.jac
  first-class.jac:2:1-37: error[E0804]: The value does not satisfy its annotation
    Cause: equation definition `ranges` does not match its signature: expected (list real) ->{} list (distribution int), got (list real) ->{} list (distribution bool) (type mismatch)
    Next step: Change the value or its annotation so the two types agree.
  [1]
  $ cat > vary.jac <<'EOF'
  > v() = VaryValue(Bernoulli(0.5), fn (pair) -> pair)
  > EOF
  $ jacquard check vary.jac
  vary.jac:1:17-31: error[E0801]: Types do not agree
    Cause: argument: expected distribution (a, a), got distribution bool (type mismatch)
    Next step: the expected side comes from the surrounding context; make both sides agree
  [1]

The printed signatures name the element type; Categorical keeps its entries'
type, and an empty Categorical stays polymorphic:

  $ cat > sigs.jac <<'EOF'
  > coin() = sample(Bernoulli(0.5))
  > die() = sample(UniformInt(1, 6))
  > fair() = Bernoulli(0.5)
  > range() = UniformInt(1, 6)
  > names() = Categorical([MkPair("a", 1.0)])
  > nothing() = Categorical([])
  > coins(ps) = list.map(ps, Bernoulli)
  > EOF
  $ jacquard check sigs.jac --print-sigs
  coin : () ->{Dist} Bool
  die : () ->{Dist} Int
  fair : () ->{} Distribution Bool
  range : () ->{} Distribution Int
  names : () ->{} Distribution Text
  nothing : forall a. () ->{} Distribution a
  coins : (List Real) ->{} List (Distribution Bool)

Patterns keep the declared type: a match over every constructor still checks
at any element type, and exhaustiveness still lists all three constructors,
so a match on a Distribution Int without a Bernoulli arm needs a wildcard.

  $ cat > shapes.jac <<'EOF'
  > shape(d) = match d { | Bernoulli(p) -> 1 | Categorical(xs) -> 2 | UniformInt(lo, hi) -> 3 }
  > int-shape : (Distribution Int) ->{} Int
  > int-shape(d) = shape(d)
  > EOF
  $ jacquard check shapes.jac --print-sigs
  shape : forall a. (Distribution a) ->{} Int
  int-shape : (Distribution Int) ->{} Int
  $ cat > partial.jac <<'EOF'
  > width : (Distribution Int) ->{} Int
  > width(d) = match d { | UniformInt(lo, hi) -> int.sub(hi, lo) | Categorical(xs) -> 0 }
  > EOF
  $ jacquard check partial.jac
  partial.jac:2:18-19: error[E0813]: This match is not exhaustive
    Cause: this match is not exhaustive: it misses bernoulli(_)
    Next step: Add a clause matching the witness or a wildcard default.
  [1]

The rule is keyed on the prelude's identities: a program's own type with the
same constructor names keeps its declared, polymorphic type.

  $ cat > lookalike.jac <<'EOF'
  > type Coin a = | Bernoulli Real | UniformInt Int Int
  > mine() = Bernoulli(0.5)
  > EOF
  $ jacquard check lookalike.jac --print-sigs
  mine : forall a. () ->{} Coin a
