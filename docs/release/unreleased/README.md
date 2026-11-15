# Jacquard Core: Unreleased

This directory carries the work integrated after `jacquard-core-0.3.0` until
the next release. The published 0.3 documents in `../0.3/`, like those in
`../0.2/`, stay byte-identical to their tag; CI refuses any change to them
(`scripts/release/check-frozen-releases.sh`). At the next release this
directory becomes that release's directory, and the inventory printed by
`scripts/release/inventory.sh` is frozen there at the tag.

## Inventory and Slice Entries

The live inventory is not recorded in any document, so parallel changes do not
conflict over it: `scripts/release/inventory.sh` prints it from the build, and
the next release freezes it at its tag. At the last recorded point it was
1246 Alcotest/QCheck cases, 85 cram transcript files and 57 documentation
examples across 9 documents.

[SLICES.md](SLICES.md) holds the slice log up to that point. Each later change
adds its own entry file under [slices/](slices/) instead of appending to a
shared log, and does not record a running inventory.

## Upgrade Notes

Notes for the next release's upgrade section, collected as changes land:

- **E0811 for field types.** A nominal type whose field type names a type
  variable its header does not declare (`type Box = | Box(value: a)`) is
  refused with E0811 (unbound type or row variable). The 0.3 notes summarise
  the nominal-field refusals without naming this code;
  `docs/effect-payload-containment.md` states the rule.
- **Rebound prelude constructors in projects with entries.** A root project
  that runs an entry may declare its own type with a prelude type's name and
  constructors (for example `opaque type Bool = | False | True`); the entry
  check no longer refuses it (E1731). An entry's own constructor that collides
  with a visible one is still E1731, and E1731 now names the root's own
  constructors as `of this project`.
- **E0837 for effects a task leaves to an outer handler.** A spawned child or
  an `async.scope` body runs on a fresh continuation under the scheduler, so a
  handler outside the task never handled its operations: such a program checked
  and then failed at run time with `Failed("unhandled effect ...")`. The
  checker now refuses it with E0837. A task must handle inside its own thunk
  every effect other than Async, Channel and the root-grantable effects; move
  the handler into the thunk passed to `async.spawn` or `async.scope`. Only
  effects the task itself performs count: a handler, an annotation or a
  sibling callback around the spawn or scope call is unaffected (except for a
  thunk the parent both calls and spawns, and for a wrapper signature that
  names one row variable for the task row and the call row, such as
  `(() ->{Async | e} a) ->{| e} TaskResult a`: give it two, as in
  `forall a | e e1. (() ->{Async | e1} a) ->{| e} TaskResult a`), and every
  effect a task performs, granted ones included, still appears in the caller's
  row for `--allow` and manifests. `docs/concurrency.md` states the rule.
- **Effects a task leaves to the root are charged to the root.** A
  root-grantable effect (such as `console` or `dist`) or Channel that a task
  performs under an in-language handler written around the task (such as
  `console.scripted`, `dist.enumerate`, `clock.fixed` or a user Console
  handler) is no longer discharged by that handler, which never sees the
  task's operations. Previously such a program checked as pure and its
  child's operation went to the root grant anyway, or failed without it. Now
  a root-grantable effect needs its root grant (`--allow`, E0814 in manifests,
  host preflight and Warp world grants): grant it or handle it inside the
  task. Channel needs no grant; the scheduler manages it. Outside the task
  such an effect carries a separate label, its root twin, which printed
  signatures, interfaces and diagnostics show as `Console@task` (signatures)
  or `console@task` (diagnostics). So the printed signature of a function
  whose task leaves an effect to the root changes, for example from
  `() ->{Console} TaskResult ()` to `() ->{Console@task} TaskResult ()`;
  signatures of other functions are unchanged. An effect row written in the
  program may name the twin (`Console@task`; only Channel and the
  root-grantable effects have one, E0316 otherwise), so printed signatures can
  be written back as annotations. An annotation that names only `Console` on
  such a function, open or closed, is now a mismatch: write `Console@task`,
  remove the annotation, or handle the effect inside the task. A row the
  prelude fixes cannot name the twin, so a Warp `Case`, `Prop` or `WCase` whose
  body runs a task that leaves an effect to the root, and a `judge.model`
  model callback (closed `{Infer}`) that does, are now refused: handle the
  effect inside the task. A host-protocol target may carry the twin in its
  closed annotation; its pinned interface lists the base effect. A handler
  written directly around such a task gets warning W0802, and a behavior
  review refuses a case whose task leaves an effect to the root (E1012).
