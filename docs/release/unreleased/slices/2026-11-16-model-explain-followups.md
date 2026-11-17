Model explain follow-ups. `jacquard model explain` now prints, under each
changed callee, the readable `jacquard diff` of its two retained bodies
(`Diff.form_divergences` and `Diff.render_readable` over the parsed bodies,
each side naming its own members first). Callees are named once per
declaration with their kinds, as the surface spells them: a declaration's
aliases and the members of a group or type are one change (`callee term bump,
inc changed`, `callee con W, type Wrap changed`); the JSON change keeps
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
being HASH_V0 of the running executable and the Core version), so a
development build never serves an outcome another build stored; keys are
unchanged. Cache files (outcomes, histories, locks, snapshots) are never read
or appended through a symbolic link, and existing `outcomes`, `history` and
`snapshots` directories of the user's are made owner-only (the cache
directory itself is left as it is). W1802 now carries a next step: move aside
a history larger than 64 MiB (histories are never compacted), or use the
version that wrote a history of another format. `explain` stays read-only and
says that the next `model eval` repairs a damaged history.

Test scratch stores made by `Eval_support.fresh_dir` (under `TMPDIR`) are
removed when the test process exits.

Evidence: `test/cli/model-explain.t` pins the manifest bytes of a small
program as the binary wrote them before this change, callee grouping and body
diffs (text and JSON), an oversized and a damaged history, a second build
that recomputes rather than serving, symbolic links in place of an outcome and
a history, and loosened cache directories made owner-only;
`test/cli/model-eval.t` shows the new callee lines, the explain reasons and
the retention note; `test/test_model_eval.ml` pins strict manifest parsing and
an unloadable declaration listed as `none`.

Left for later: compacting histories (a choice of what to keep);
`Store.locate_internal` still scans the index linearly for other callers.
