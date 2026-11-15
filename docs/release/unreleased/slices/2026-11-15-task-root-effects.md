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
hash of a tagged prefix and E's raw identity (`Task_twin`, idempotent, with a
twin-to-base table filled at start-up with the twin of Channel and of every
root-grantable effect, so a twin read back from a store or `.jqd` file is
recognized). No handler or declaration names a twin, so none discharges it; it
stays in the row up to the root. `Types.effect_identities` maps twins to their
base, so the manifest (E0814), `--allow`, host preflight, Warp's
`world_required` and tier statistics see E; model documents' world effects map
twins to their base too, and manifest call-chain origins are recorded under the
base. Store reference walks (`Store.ty_refs`, so closures, bundles and host
target validation) follow a twin to its base declaration. Every type printer
shows a twin as `name@task` right after its base (`Console@task` in printed
signatures, `console@task` in diagnostics, `#<base>@task` in interface
signatures, `Console@task` in review diffs); rows without twins print
byte-identically. A written effect row may name the twin: the surface lexer
accepts `Name@task` for a PascalCase effect name, the parser lowers it to the
kernel name `name@task`, and resolution maps it to the twin's hash when the base
is Channel or a root-grantable effect, refusing any other base with E0316; the
formatter and kernel printers spell it back the same way. Canonical bytes and
hashes of source that does not write `@task` are unchanged. The E0837 policy
admits twins, so a nested task passes them outward unchanged. A row a
programmer writes stays exact otherwise: a row naming only E does not admit
`E@task`, and a row mismatch involving a twin appends a sentence that says to
write `E@task` in the annotation, remove the annotation, or handle the effect
inside the task (and, for rows the prelude fixes, to handle it inside the
task). The Warp `Case`, `Prop` and `WCase` constructors keep their closed
rows, so a case whose body runs a task that leaves an effect to the root is
refused, as is a `judge.model` model callback (closed `{Infer}`) that does; a
`WCase` thunk annotated with exactly the world's effects checks as before. The
behavior review refuses a case whose row holds a twin with a specific E1012
(a `--handle` handler runs around the task and never sees its operations). New
warning W0802 (best-effort, after inference) flags a `handle` that discharges
an effect E whose solved body row holds `E@task`; it cannot see through a
wrapper whose handler body is a parameter row.
`test/cli/task-root-effects.t` pins the charged programs (scripted console and
enumerate around a spawning scope, `clock.fixed` directly and nested in a
child, a direct handler with W0802 and the same handler through a wrapper
without it, nested handlers each warned, a parent and child printing under one
handler), the `Console@task` spelling (print-sigs output written back as
annotations on a function and an annotated caller, a handler around an
annotated function still charged and run under `--allow console`, the
formatter, E0316 on a user effect and on Async, a stored and an exported
definition charged in a fresh process, a behavior review refused with E1012),
the refusals (a Console-only
annotation, a Case, Prop or WCase whose task leaves an effect to the root), the
accepted programs (a WCase body annotated with the world's effects, a handler
around the parent's own print with a pure scope or spawn, a handler inside the
child, a polymorphic helper used both ways, an `if` join), and the
`fs.read-only` known limit (the handler re-performs Fs, so the grant is the
same; the signature shows `Fs@task` beside `Fs`, but the child's write
happens);
`test/test_types.ml` pins the twin identity, idempotence, base mapping, the
pre-registered twins, the spellings, display, the outward label (Async kept, a
twin passed through) and the strict closed row; the diagnostic battery gains a
W0802 case. Churn: the printed signature of every function whose task leaves
an effect to the root now shows `E@task` (transcripts and doctests that print
such signatures), and the `manifest.t` alias-launder and `round-robin.t`
async-child-row diagnostics and the `docs/concurrency.md` row-laundering
doctest name `@task` labels and the twin explanation in place of the
eta-expansion hint; the interface identity of a program with a twin in a
signature changes (`relate-policy.t`); and `round-robin.t` proves routed
cancellation with a granted program instead of a WCase, which can no longer
hold a printing task. There is no runtime change.
