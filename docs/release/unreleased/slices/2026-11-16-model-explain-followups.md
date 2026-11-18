Model explain follow-ups. `jacquard model explain` now prints, under each
changed callee, the readable `jacquard diff` of its two retained bodies
(`Diff.form_divergences` and `Diff.render_readable` over the parsed bodies,
each side naming its own members first, then the declarations retained in its
own manifest that the current store no longer holds, so an old body still
names the constructors of a type that has since gained a variant). Callees
are named once per declaration with their kinds, as the surface spells them,
grouped by kind: a declaration's aliases and the members of a group or type
are one change (`callee term bump, inc changed`, `callee con W, type Wrap
changed`); the JSON change keeps
`subject` as the plain names (several, comma-separated, for a grouped change)
and adds `names` (each `{kind, name}`) and `diff`. A declaration
whose stored bytes exceed the 16 MiB retention limit adds a `note:` line (JSON
`notes`) saying why its result stays unknown.

Closure manifests are unchanged for declarations that load: a stored
declaration that cannot be loaded is now listed with body `none` rather than
left out, and `Model_history.parse_closure` accepts a manifest only when its
header, `root` line and every line are well formed. Each process computes a
manifest once per entry or term against one store state, reads each stored
declaration once (retained, hashed and parsed for references, without
`Store.locate_internal`), compares callees through hash tables, and does not
re-read a snapshot it already wrote or verified while it is the same file.

The result cache keeps outcomes per build (`outcomes/<build>/<key>`, the build
being HASH_V0 of the executable image the process is running, read through
`/proc/self/exe`, and the Core version), so a development build never serves
an outcome another build stored, even when the executable's file is replaced
while it runs; keys are unchanged. Where `/proc/self/exe` is unavailable
(macOS, say) or unreadable, or names the dynamic loader (a build started as
`ld.so ./jacquard`), results are `uncacheable (no-build-identity)`: on such a
system the outcome cache is off, while history and `explain` still work. Below the cache
directory, cache files (outcomes, histories, locks, snapshots) and cache
directories (`outcomes`, `outcomes/<build>`, `history`, `history/<doc>`,
`snapshots`) are never read or written through a symbolic link: a linked
outcomes directory serves and stores nothing (W1801), a linked history
directory refuses the record (W1802) and makes the history unavailable to
`explain`, and both warnings then say to make the path a directory of its
own; an outcome path that is a directory is W1801 saying to remove it. Two
evaluations creating a result's history lock at once both use it. Existing
`outcomes`, `history` and `snapshots` directories of the user's are made
owner-only, even one the owner cannot read (the cache directory itself is left as it is).
W1802 now carries a next step: move aside a history larger than 64 MiB
(histories are never compacted), or, for a history holding a record of
another format (named as `format=N`), evaluate with the version that wrote it
or move it aside; `explain` gives the same next steps. `explain` stays
read-only, creates nothing, and says that the next `model eval` repairs a
damaged history.

Test scratch stores made by `Eval_support.fresh_dir` (under `TMPDIR`) are
removed when the test process exits.

Evidence: `test/cli/model-explain.t` pins the manifest bytes of a small
program as the binary wrote them before this change, callee grouping and body
diffs (text and JSON, including a callee matching on a type that gained a
variant, beside `jacquard diff` of the same files), an oversized and a
damaged history, a second build that recomputes rather than serving, the
executable's file replaced while it runs, symbolic links in place of an
outcome, a history and each cache directory, a directory in place of an
outcome, and loosened cache directories made owner-only; `test/cli/model-eval.t` shows the new callee lines, the
explain reasons (including a history of another format) and the retention
note; `test/test_model_eval.ml` pins strict manifest parsing, unreadable
and unparsable declarations listed as `none`, the refusal of a link, FIFO or
directory in place of a cache file, a lock created by another process
between the check and the create, an owner-unreadable directory made
owner-only, and loader names.

Left for later: compacting histories (a choice of what to keep);
`Store.locate_internal` still scans the index linearly for other callers.
