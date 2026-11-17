Named-choice follow-ups. Only the `sample` that a `dist.named` body performs is
now tagged as a named choice: the evaluator reads the name from that body's
scope when the `sample` is performed, and keeps only the `dist.named` call site
between the application and the draw, set after the application has bound its
arguments and cleared by any perform or failed run. Before, the name and site
were held from the application until the next perform of any operation, so an
application cut short by a per-branch fuel cap (`Eval.with_fuel_scope`) handed
its name and site to whatever operation ran next, and a state built by
`Eval.apply_state` on `dist.named` named the next operation performed rather
than its own draw. A `dist.named` applied by a host or native caller, which
has no call site, is now sited at the `sample` in `dist.named`'s own
declaration instead of `site unknown`. Values, output, fuel and plain runs are
unchanged, and the prelude is untouched.

`Exploration_log.parse` now matches the `choice-name` and `argument` keywords
explicitly; the lines it accepts are unchanged (the line was already re-read
exactly when its payload was framed).

`docs/exploration-log.md` §2a corrects which drivers record named draws
(`dist.sample-lw`'s are steps; `dist.enumerate`'s are not), says that k counts
across a native driver's runs, that two names that redact to the same text can
show the same `(name, k)`, where a host-applied draw is sited, and what a draw
through `dist.named` costs: the same as any two-parameter function performing
`sample`, with tagging free and the default policy's projections the only
recording cost.

Evidence: `test/test_invocation.ml` sweeps per-branch fuel caps around a
`dist.named` application and checks that the following `print` and `sample`
are untagged and keep their own sites, and that a host-built `dist.named`
state names its own draw (both cases fail on the previous evaluator, which
named the `print`). `test/cli/exploration-log.t` checks that Warp falsifies a
property with the same case and shrunk choices for `dist.named` and `sample`
under one seed and differently under another, that `dist.named` costs the
same fuel as a user wrapper and a recording under an empty policy costs the
same as the plain run, the `(name, k)` numbering across `dist.sample-lw` runs,
two names that redact alike, and that each parity command's own exit status is
visible. `test/test_exploration_log.ml` refuses near-miss `choice-name` and
`argument` lines.

Left for later: whether k should restart in each branch of an inference driver
(which would repeat addresses within one log) is an open design choice, as is
how a fork engine should address a redacted name.
