Inference drivers own Dist under a root grant. With `--allow dist` (or
`--dry-run`, which installs the dist grant with seed 0), the evaluator
consulted the root handlers before an inference driver's capture, so the root
sampler answered every `sample` and the root `observe` stub every `observe`
inside an OCaml- or C-implemented driver. `dist.sample-lw`,
`dist.sample-lw-weights-v1` and `dist.sample-lw-v1` ignored their seed and
failed with E0902 on any `observe`; a model document's `enumerate` result
explored one path and was labeled complete, and its `lw` result ignored
`seed=`; `posterior.run-exact-v1` produced wrong exact risk weights and
`posterior.sample-evidence-v1` ignored its configured seed; Warp reported
unreplayable counterexamples and a false exhaustive proof, which its cache
then served without the grant. Native `dist.sample-lw` binaries had the same
ordering. In-language handler drivers (`dist.enumerate`,
`dist.enumerate-v1`) and `jacquard infer` were unaffected.

The checked type already discharges Dist at the driver, so the driver now
owns it. The evaluator context carries `driver_ops`, the operations the
capturing driver owns; every capture assigns it for its own duration and
restores the outer value (`Eval.run_state_capturing ?driver_ops`,
`Eval.run_validated_state_capturing ?driver_ops`). While a driver capture is
active, an operation in the set is captured before any root handler. The
inference drivers (`Infer_dist.driver_ops`) and both Warp drivers pass the
prelude's `sample` and `observe` by their frozen identities. Scheduler and
host captures pass none, so a task's `Dist@task` draw still goes to the root
grant, and every other root grant still reaches a model. In the native
runtime, `jq_perform` intercepts `sample` and `observe` for a weighted run
before the grant lookup, and the dist `observe` grant no longer carries an
in-driver branch. `Warp.version` moves from `warp-v2` to `warp-v3` because a
cached verdict could have been computed under the old rule.

This is an erratum: no kernel form, prelude term, signature or operation
identity changes, and the prelude and corpus hash goldens are byte-identical.

Behavior changes: programs that combine a dist grant with one of these
drivers now print the grant-free result; a root draw after a driver call
follows `--seed` as if the driver were absent; `jacquard run --record` with
the grant records a driver's draws as captured steps (`result missing`); every
cached Warp verdict is recomputed once.

Evidence: `test/cli/driver-dist-grant.t` compares granted and grant-free runs
of `dist.sample-lw`, `-v1` and their observing models at two root seeds,
`--dry-run`, a root draw beside a driver, a non-Dist grant inside a model,
nested drivers, `--record`, a task's root draw beside a driver in another
task, model-document `enumerate` and `lw` results, both posterior builtins,
and Warp sampled, exhaustive and cached runs, and checks native
`dist.sample-lw` binaries against the interpreter at the same seeds.
`test/test_dist_lib.ml` runs `Infer_dist.enumerate`,
`likelihood_weighting` and nested drivers on a granted context against a
grant-free one. `test/test_warp.ml` pins the `warp-v3` epoch and that
`warp-v1` and `warp-v2` entries are not reused. `docs/stdlib.md` (errata),
`docs/errors.md` (E0904), `docs/native-plan.md`, `docs/warp-testing.md`
and the upgrade notes state the rule.

Left for later: drivers still capture at the evaluator root rather than
installing a handler frame on the model's fresh continuation, which would
make the ordering structural.
