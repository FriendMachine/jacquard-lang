CLI start-up is about ten times faster. `jacquard check`, `run` and `test`
spent about 0.6 s seeding the prelude into their scratch store before reading
user code: the store rewrote its whole name index after each of the prelude's
declarations. A test run also reread and reparsed a stored object file on every
lookup of a declaration. `Store.batch_names` now coalesces index writes into
one write when a prelude load or source walk ends (flushing on an exception
and before a transaction's snapshot). A store handle keeps the declarations it
has parsed, and finds index entries through a hash table. A trivial `check`
takes 0.05 s of CPU instead of 0.58 s; a test that explores 129 executions
takes 0.07 s instead of 0.93 s. Store files and command output are unchanged.
Evidence: `docs/benchmarks.md` ("CLI start-up") and
`sh scripts/startup-bench.sh`.
