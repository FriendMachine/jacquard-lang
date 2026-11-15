Effects a task leaves to the root are charged to the root. After E0837 a task
may still leave Async, Channel and the root-grantable effects unhandled, and
the scheduler or the root grant handles them; but an in-language handler of
such an effect written around the task (`console.scripted`, `dist.enumerate`,
`clock.fixed`, a user Console handler) still subtracted the effect from the
row, because the task's effects reached the spawn or scope call's row as
themselves. Such a program checked as pure (`console.scripted` around a scope
whose child prints had the row `{}` and printed through the root console under
`--allow console`; `dist.enumerate` around a sampling scope was Dist-free and
ignored the child's sample). Now the outward push from a task tail, and the
frozen spawn operation's outward row, map every admitted effect except Async to
a root twin `E@task`: a synthetic label whose identity is the deterministic
hash of a tagged prefix and E's raw identity (`Types.task_twin`, idempotent,
with a twin-to-base table). No handler, declaration or source spelling names a
twin, so none discharges it; it stays in the row up to the root.
`Types.effect_identities` maps twins to their base, so the manifest (E0814),
`--allow`, host preflight, Warp's `world_required`, tier statistics and
interface rendering see E; the behavior review's modeled-operation check and
model documents' world effects map twins to their base too, and manifest
call-chain origins are recorded under the base. Printed signatures and
interfaces are byte-identical (a twin renders as its base, once); diagnostics
render it as `name@task` (`Types.show ~mark_task_effects`, used by the
checker's diagnostic renderer). The E0837 policy admits twins, so a nested
task passes them outward unchanged. Rows a programmer writes stay strict: a
closed or rigid row naming E does not admit `E@task`, and a row mismatch
involving a twin appends a sentence explaining the label. The Warp `WCase`
constructor's closed field row admits the twins of its root-grantable effects;
`Case` and `Prop` stay closed, so a `Prop` whose body runs a sampling task is
now refused. New warning W0802 (best-effort, after inference) flags a
`handle` that discharges an effect E whose solved body row holds `E@task`; it
cannot see through a wrapper whose handler body is a parameter row.
`test/cli/task-root-effects.t` pins the charged programs (scripted console and
enumerate around a spawning scope, `clock.fixed` directly and nested in a
child, a direct handler with W0802 and the same handler through a wrapper
without it, a parent and child printing under one handler), the refusals (a
closed Console annotation, a Case whose task prints, a Prop whose task
samples), the accepted programs (a WCase whose task prints, a handler around
the parent's own print with a pure scope or spawn, a handler inside the child,
a polymorphic helper used both ways, an `if` join), and the `fs.read-only`
known limit (the handler re-performs Fs, so the charge cannot show that the
child's write bypasses it; the write happens); `test/test_types.ml` pins the
twin identity, idempotence, base mapping, display with and without marking,
the outward label (Async kept, a twin passed through) and the strict closed
row; the diagnostic battery gains a W0802 case. Churn: the `manifest.t`
alias-launder and `round-robin.t` async-child-row diagnostics, and the
`docs/concurrency.md` row-laundering doctest, name `@task` labels and the twin
explanation in place of the eta-expansion hint. There is no runtime change.
