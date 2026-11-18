Distribution element types. The prelude's `Distribution a` declares
`Bernoulli Real` and `UniformInt Int Int`, which do not mention `a`, so the
checker gave them `forall a. (Real) -> Distribution a` and
`forall a. (Int, Int) -> Distribution a` while every eliminator produces a
`Bool` and an `Int`. A draw could therefore be used at any type:
`text.length(sample(Bernoulli(0.5)))` checked and then failed at run time,
`pmf(Bernoulli(0.5), "x")` was silently `0.0`, and
`observe(Bernoulli(0.5), 3)` under `dist.enumerate` gave a `NaN` weight.

The checker now types a construction of the two prelude constructors, in an
expression (applied or first-class) or a host-protocol value, as
`Bernoulli : (Real) -> Distribution Bool` and
`UniformInt : (Int, Int) -> Distribution Int`. The rule is a checker contract
(`src/distribution_contract.ml`, used by `Check.con_scheme`) keyed on the
frozen `distribution` declaration hash and the two constructor hashes, in the
way the `VaryWorld` refinement is keyed on its identities, so a program's own
type with the same names or shape keeps its declared type. Patterns keep the
declared scheme: a match learns nothing about `a`, and exhaustiveness is
unchanged. No declaration, prelude, corpus, effect-taxonomy or native pin
changes; the prelude, binding and corpus hash goldens are byte-identical.

Behavior changes, all at check time or the host boundary:

- Narrowed signatures: a function that builds or samples a Bernoulli or
  UniformInt now prints `Bool`, `Int`, `Distribution Bool` or
  `Distribution Int` where it printed a type variable. In the corpus,
  `die-posterior` in `corpus/sigs/24-ring2.jqd` goes from
  `forall a. (Int, Int) ->{} List (Pair a Real)` to
  `(Int, Int) ->{} List (Pair Int Real)`. The interface-v1 `signature` of a
  user export that samples one of these distributions narrows the same way, so
  its interface identity and `interface diff` change (no tracked interface pin
  involves a distribution).
- New check-time refusals (E0801, or E0804 against an annotation) for a draw,
  `pmf` or `observe` at another element type, and for an annotation that
  claims a draw is polymorphic.
- `jacquard review run` refuses a Bernoulli or UniformInt domain for a
  parameter of another type (E1012): the generated typing declaration already
  unified each Distribution domain's element type with its parameter's.
- Host protocol v0 refuses a `bernoulli` or `uniform-int` value sent for a
  `Distribution T` whose `T` is not `Bool` or `Int` (E1603); host ingress uses
  the construction scheme through `Check.force_constructor`.

Evidence: `test/test_distribution_contract.ml` checks that the frozen hashes
equal the prelude pins, that only the exact declaration and constructor pair
is indexed, the construction and pattern schemes, that user lookalike types
keep their declared schemes, and the host-ingress acceptance and E1603
refusals. `test/cli/dist.t` pins the refusals (the run-time repro included),
printed signatures, an exhaustive polymorphic match, the unchanged E0813 for a
`Distribution Int` match without a Bernoulli arm, and a user type with the
same constructor names. `test/cli/review.t` pins the E1012 domain refusal.
`test/cli/task-root-effects.t`, `test/cli/inference-models.t` and
`corpus/golden/sigs.golden` carry the narrowed signatures; the `mixed` annotation there now says `TaskResult Bool`.
`docs/stdlib.md` (Dist and the implementation errata), `docs/SKILL.md` and the
upgrade notes state the rule.

Left for later: the root sampling handler resumes with `()` for an empty or
zero-mass `Categorical`, which is a separate run-time totality fix. Patterns
do not refine the element type (no GADT-style matching).
