Exploration-log hardening. Hashing, resolution and stored-group renumbering now
share one quasiquote traversal, `Kernel.walk_quoted` (with `Kernel.map_quoted`
for rebuilding a payload), used by `Canon.ser_quoted`,
`Resolve.resolve_quote_payload` and `Store.remap_quoted`, so the three cannot
disagree on which `unquote` splices are live. Canonical bytes are unchanged:
the corpus goldens are untouched, and `test/test_canon.ml` pins the hashes of
declarations with live, nested and data unquotes and a group whose members
reach each other through splices, taken from the binary before the change.
`Store.remap_group_refs` returns an option and refuses a live splice that is
not a kernel expression or a group reference the renumbering does not cover,
rather than returning the expression with a reference left as it was.
`Store.in_persisted_order` checks that member hashes are distinct (they are by
construction), refuses a repeated hash in either list, and runs in linear time.

`Exploration_log.parse` checks each step index against a running count and
refuses argument indices that are repeated or not ascending (a recording never
writes them: OBS.1 selections are validated as strictly ascending); selected
argument positions are looked up in an array. When the write of a reserved log
fails, `Exploration_log.write_reserved` empties the file through its descriptor
and removes the path only if it still names the reserved file (same device and
inode), so no partial log is left and a file substituted at the path is never
removed; the E1016 message says whether that cleanup succeeded.
`write_reserved` takes an optional `?write` primitive so tests can fail a write
part way. E1005 for a `--record-policy` with a `--store` source that has
unknown names on its own now says the policy could not be checked and gives a
next step; `test/cli/exploration-log.t` pins the new cause and next step.
`docs/exploration-log.md` describes the cleanup, the argument-index rule and
splice renumbering at any quasiquote depth.

Evidence: `test/cli/exploration-log.t` records a reordered stored group whose
members call each other only through `quote { quote { unquote(unquote(...)) }
}` and checks the log names the current source's sites;
`test/test_exploration_log.ml` pins serving that group in the persisted order,
refusals of repeated, unrelated or differently sized hash lists, renumbering
refusals, repeated and descending argument indices, uppercase hashes in the
program, prelude, policy and operation fields, a long log, a write that fails
part way (the path is removed) and one where another file was put at the path
first (that file is kept and the reserved file is emptied), and a QCheck
property (300 cases, fixed seed) that no payload returned by a secret operation
reaches the log in any field under three policies, with a control showing the
probe detects an unredacted payload. The property found no leak.

Left for later: a recording under a file-size limit cannot be exercised from
the CLI, because the session store writes prelude objects first and
`Store.put_decl` raises an uncaught `Sys_error` when that write fails.
