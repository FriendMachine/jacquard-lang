# Identity, Formatting, And Review

Part of the Jacquard agent guide: canonical hashes, formatter ordering,
canonical diffs, and record/replay. Start with [the core guide](../SKILL.md).

`jac hash` computes `HASH_V0` over canonical structure. It erases metadata,
alpha-normalizes local binders, and hashes recursive definition groups as
units. Consequently:

- Formatting and comments do not change identity.
- Alpha-equivalent local names hash equally.
- Reordering members of a recursive SCC is stable.
- Renaming a top-level display name changes the name index, not its object.
- Provenance can change without changing the approved content hash.
- Explicit term/operation call labels are a versioned, hash-bound companion
  ABI. Binder and callable renames preserve it; a conflicting relabel is
  E0612 rather than an identity-silent API change.

Use `jac fmt --write` for canonical layout. Within each uninterrupted run of
term definitions, the formatter orders definitions so each one follows the
definitions it uses (members of one mutually recursive group keep their relative
order), so adding a call to a later definition can move the caller. A term
cannot refer forward across a `type` or `effect` declaration or a bare top-level
expression (E0301); keep terms that use each other in one run. Use stores and
`jac diff` when you need rename classification, changed canonical subtrees, or
affected dependents. `jac diff` accepts two stores or two declaration-only
source files; a source file with a bare top-level expression is refused (E0610),
so diff a program without its entry call. Its output names the changed region
(authority, signature, body, clause N) and callees by name; `--paths` prints
kernel paths and content hashes for tools. Hash or diff equality establishes canonical structural identity, not
general behavioral equivalence.

Record/replay logs contain operation, argument, and result triples. Strict
replay fails closed on operation or argument drift. Counterfactual `--fork`
specifications replace an effect result at a trace index; malformed specs are
diagnostics, not permissive fallbacks.
