`explore.all` explores every outcome of a program's own effects, and
`jacquard test` reports how many executions each test explored. The prelude's
new `multi effect Explore { explore.branch : (Text, List a) -> a }` carries every
choice point: a forwarding handler answers each operation of the user's effect
with `explore.branch(site, outcomes)`, and `explore.all(thunk)` resumes once per
outcome, depth first, returning `(value, path)` per completed execution.
`explore.up-to(limit, thunk)` bounds it (default 10,000). A `Case` or `WCase`
reports `N executions explored, complete`; an exploration that reaches its
limit before exploring every outcome is a runtime failure (E0905) wherever it
runs, never a partial result; even when a program catches it, the test that
saw it fails uncached and the run exits 1. The count
travels through a hidden builtin, so a test's effect row is unchanged and user
code cannot report counts itself. The Warp cache tag moves to `warp-v7`
(entries carry the count). The prelude change re-pins the demo projects.
Evidence: `test/cli/explore.t`.
