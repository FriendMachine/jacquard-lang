Inference drivers that run a model on a fresh continuation are now sound about
the model's effects. The likelihood-weighting drivers (`dist.sample-lw`,
`dist.sample-lw-weights-v1` and so `dist.sample-lw-v1`) run their thunk on a
fresh state with an empty handler stack: only Dist (the driver) and the root
grants reach it. Their signature shared one row tail between the thunk and the
call, so a handler around the call appeared to discharge an effect the model
performed: `emit.collect` around a model that emits checked as `{}` and failed
at run time with E0902, `console.scripted` around a model that prints checked
as pure and printed through the root console, and a model that performed
`async.yield` checked and failed. The signature is now built like
`async.scope`'s: the call's row has its own tail, and the thunk's tail carries
the task-row flag with a new kind, `Types.Driver` (the `task_row` field is now a
`task_kind option`; kinds merge to the stricter one, Driver over Task), and the
call's row as its outward row. The Driver policy admits only the
root-grantable effects and root twins; any other effect, Async and Channel
included, is refused with the new checker code E0838. A root-grantable effect
the model leaves unhandled reaches the call as its root twin `E@task`, so it is
charged to the root, a closed `{Console}` annotation no longer accepts it, and
W0802 warns about a handler of it written around the call. A parent effect
performed beside the call (`emit.collect(fn () -> { let p =
dist.sample-lw(m, 4, 1); emit(1); p })`) is still handled around it. The W0802
summary, cause and next step, the twin-mismatch explanation and the
closed-outward-row message now speak of "a task or an inference model"; E0837
stays the task refusal. A refusal that names the scheduler's Async now names it
`async` rather than qualifying it as a user effect.
The top-level drivers read the model's raw row: `jacquard infer enumerate|lw`
refuses a root twin with E0838 before the manifest check (a scope child's
sample goes to the root, so inference never saw it), and the posterior model
gate (`posterior.run-exact-v1`, `posterior.sample-evidence-v1`) requires
exactly the closed `{Dist}` row, refusing `{Dist@task}` and `{Dist, Dist@task}`
with a twin-specific E1543 cause; both previously mapped twins to their base and
accepted such models. No driver has a scheduler, so every driver
(likelihood weighting, enumeration, exact risk enumeration, model documents)
now recognizes the `async.scope` control operation and stops with the new
runtime code E0922 instead of an E0902 "unhandled effect" or "type error"; the
posterior builtins report it inside E1544 or E1547. The runtime E0902 for any other
operation that reaches a driver stays as the backstop for unchecked paths.
`test/cli/inference-models.t` pins the refusals (emit, throw and `-v1` models,
`async.yield` and a channel send in a model, a twin model under `infer
enumerate|lw`, twin-annotated posterior models under both builtins), the
charged programs (a printing model, under `console.scripted` and under a
direct handler with W0802, a scope child's sample in a model, a model
document whose entry leaves Dist to the root from a scope child, which keeps
it in the world and needs the grant), E0922 under every driver including
`dist-diff`, and the accepted programs (the parent-effect shape, a handler
inside the model, a nested driver, a driver inside a scope body, the typed
outcome, an unannotated wrapper, a one-variable annotated wrapper refused at
use, `dist.enumerate` around an emitting model, a plain `{Dist}` posterior
model). `test/test_types.ml` pins the Driver policy, kind merging and the kind
through instantiation and cloning; the `native-effects.t` runtime check of an
outer-handled model operation moves to an OCaml unit test that calls the
builtin without the checker, since the program is now refused at check time.
Churn: the printed signatures of `dist.sample-lw`, `dist.sample-lw-v1` and
their unannotated wrappers gain a second row variable (`forall a | e e1. (() ->{Dist
| e1} a, Int, Int) ->{| e} ...`); the W0802 and twin-mismatch wording in `task-root-effects.t`,
`manifest.t`, `round-robin.t`, the `docs/concurrency.md` row-laundering doctest
and `diags.golden`, which also gains an E0838 case; prelude and corpus hashes
(including the prelude binding goldens) are unchanged. Native builds refuse
`async.scope` already, so the native runtime has no E0922 path.
