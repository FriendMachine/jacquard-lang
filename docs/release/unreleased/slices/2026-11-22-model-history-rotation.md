Model history rotation. A result's history no longer stops growing at 64
MiB with W1802 and a request to move it aside: when `jacquard model eval`
is about to write a record and the history with it would exceed 64 MiB, or the
history is already too large to read, the evaluation (under the history's
existing lock) moves the whole file to `<result>.N` beside it, N being one more
than the largest N of any entry of that name, whatever its kind, and starts a
new history with the records `jacquard model explain` reports from (the last
record before the latest key's run, that run's first record and the latest
record, byte for byte) followed by the new record. `explain` therefore reports
the same before and after a rotation, including `evaluated_at` for a refresh
under the same key. Only when those records and the new one would not fit in
64 MiB does the new history keep fewer: the records `explain` reports from once
the new record is appended (which still leaves its report unchanged), or, when
even those would not fit, none. The move is a hard link (never following the history or
replacing an entry) followed by an atomic replacement of the history; an
evaluation stopped between the two is completed by the next evaluation that
writes a record, which finds the newest `<result>.N` to be the history itself
and reuses it. A history too large to read starts unseeded, and a damaged one
is moved aside whole and seeded from the records before the damage.
Evaluations that write no record never rotate. The history format
(`jacquard-model-history format=1`) is unchanged, and histories of another
format are still refused and left in place.

A rotation is reported as the new W1804, naming the file that keeps the old
records; W1802 now covers a history that could not be moved aside (its next
step says to move it aside by hand) and no longer covers an oversized one.
`explain` stays read-only: for a history larger than 64 MiB it says the next
`model eval` that records the result moves it to the `<result>.N` it names.
`Model_eval.evaluate`'s `record` callback now returns a
`Model_eval.history_note` (`Repaired`, W1803, or `Rotated`, W1804), and
`Model_history.append` takes an optional `?limit`, used by tests only. On a
file system without hard links a history cannot be moved aside, so every
record written to a full history is W1802.

Evidence: `test/test_model_history.ml` rotates histories under small limits:
`.1` holds the old bytes byte for byte, the new history is the seed and the
new record and parses, and `explain` text and JSON match the same evaluation
without rotation, for a new key (current with a transition, and stale) and for
a refresh under the same key (whose `evaluated_at` stays the run's first
record); numbering skips a symbolic link to the history, a directory and a
FIFO without changing them and ignores `.0` and `.05`; an interrupted rotation
(history and `.1` one file) completes without a `.2`, at the limit or not; an
oversized unreadable history is moved aside and the new record has no
predecessor; a damaged history at the limit is moved aside whole; two
successive rotations make `.1` and `.2`, leaving `.1` unchanged; the smaller
seeds keep `explain` unchanged or start unseeded; a history that cannot be
moved aside (no number left after the largest) is a failure with a next step
and is left as it was; and two processes (the test executable started again,
both made to wait on the history's lock) rotate once and keep both records.
`test/cli/model-explain.t` shows `explain`'s reason for a 70 MiB history, the
W1804 warning, the moved file and the new one-record history.

Left for later: rotated files accumulate until the user deletes them; nothing
prunes them.
