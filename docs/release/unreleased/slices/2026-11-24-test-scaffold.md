`jacquard test --scaffold FILE.jac` prints an exploration-test skeleton for
the `multi` effects FILE declares (`docs/warp-testing.md`): a forwarding handler
per effect that answers each operation with `explore.branch` over the outcomes
its result type lists (`Bool`, `()`, or a non-opaque type FILE declares whose constructors
take no fields; any other result gets a TODO outcome list that prunes until it
is filled in), an `explore.all` helper, and a `Case` per single-effect entry
point with placeholder arguments and a TODO property. The output is formatted
and checked with FILE as `jacquard test` loads the two files before it is
printed; a file with no `multi` effect, or one that cannot be loaded with its
scaffold, is refused with E1017. No `Prop`
placeholders are generated: a `Case` per entry point carries the property.
Evidence: `test/cli/test-scaffold.t`.
