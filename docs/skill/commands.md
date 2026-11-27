# Command Reference

Part of the Jacquard agent guide: the command reference, and what `tiers`, `relate`,
`audit`, and `governance` report; `jac --help` and `jac COMMAND --help` list every
command and option. Exit codes and everyday use are in [the core guide](../SKILL.md).

```sh
# Check without executing.
jac check PROGRAM.jac
jac check PROGRAM.jac --print-sigs
jac check PROGRAM.jac --manifest fs,net,console

# Run, granting only named root effects.
jac run PROGRAM.jac
jac run PROGRAM.jac --allow console --allow net
jac run PROGRAM.jac --dry-run
jac run PROGRAM.jac --fuel 1000000   # bounded: running out is E0919, exit 2

# Local projects (project.jqd): compose several files, pin dependencies,
# bundle; see docs/designs/project-structure.md.
jac project check --project DIR
jac project run --project DIR ENTRY --allow console
jac project test --project DIR --seed 42 --no-cache
jac project build --project DIR ENTRY -o OUT
jac project pin --project DIR

# Public API identity: emit a source's interface-v1 manifest, verify a store
# against one, or classify a change between two manifests.
jac interface emit LIB.jac
jac interface verify LIB.jqi STORE
jac interface diff OLD.jqi NEW.jqi

# Since 0.3.0: compare two checked versions of an entry point over declared
# cases and report where behavior differs (docs/behavior-review.md).
jac review run --old OLD.jac --new NEW.jac --cases CASES.jac --entry NAME --domain NAME

# Compare complete transcripts under schedule/Secret variation, or only result
# values under one live grant versus the dry world.
jac relate PROGRAM.jac --vary schedule=8 --seed 42
jac relate PROGRAM.jac --vary schedule=8 --seed 42 --allow console
jac relate PROGRAM.jac --vary secret=deploy-token --seed 42 --allow secret
jac relate PROGRAM.jac --vary grant=net --seed 42

# Format and identify code.
jac fmt PROGRAM.jac
jac fmt PROGRAM.jac --write
jac hash PROGRAM.jac

# Discrete probabilistic inference.
jac infer enumerate MODEL.jac
jac infer lw MODEL.jac --seed 42 --samples 100000
jac dist-diff MODEL_A.jac MODEL_B.jac

# Warp tests.
jac test TESTS.jac --seed 42
jac test TESTS.jac --seed 42 --exhaustive --budget 10000
jac test TESTS.jac --cache-dir .jacquard-test-cache
jac test TESTS.jac --allow fs --allow net --allow clock --allow console

# Content store, canonical-structure diff, traces, and tiers. A store keeps the
# prelude and every installed declaration and records which prelude files
# (names and bytes) it was created with: reopening with that prelude is a
# no-op, so separate entry points can run against one installed model, and
# reopening with a different prelude is refused (E0705) without changes. A
# `store add` that refuses any declaration leaves the store exactly as it was.
jac run MODEL.jac --store STORE
jac run ENTRY.jac --store STORE
jac store add STORE PROGRAM.jac
jac store rename STORE old-name new-name
jac diff STORE_A STORE_B
jac replay TRACE.jqd PROGRAM.jqd --to 12
jac replay TRACE.jqd PROGRAM.jqd --fork '4=(response 503 "down")'
jac tiers PROGRAM.jac

# Audit-chain and governed Workspace review tools.
jac audit genesis
jac audit append AUDIT_LOG.audit AUDIT_ENTRY.jqd --previous HASH
jac governance check WORKSPACE.jac --output-format json-v1
jac governance verify-log AUDIT_LOG.audit --head HASH
jac governance verify-run RUN_BUNDLE.jqd
jac governance reconcile RECONCILIATION_BUNDLE.jqd
jac governance explain PROPOSAL_ID --bundle RECONCILIATION_BUNDLE.jqd
jac host worker --store DIR
jac why-effect Net --source WORKSPACE.jac --output-format json-v1

# Native AOT accepts public surface input directly.
jac build PROGRAM.jac -o program
jac export PROGRAM.jac -o PROGRAM.jqd  # explicit evidence/debug carrier only
./program --allow console
```

`tiers` reports handler syntax and native lowering as separate tables. A
tail-resumptive source shape is tokenless only for a `multi` operation; every
`once` clause materializes the shared affine resume token, including a
syntactically tail-resumptive clause.

`relate` success stdout is one verdict line; constituent values and Console
output are captured rather than printed. Console input is read from the process
only during run 1, captured by call ordinal, and replayed from a fresh cursor in
every later run; calls beyond the captured list receive EOF (`""`). A completed
transcript difference is Warp diagnostic E1003 and status 1. Constituent
diagnostic, runtime, and authority failures retain statuses 1, 2, and 3.
Secret variation runs exactly twice with distinct deterministic latest-version
payloads for the named Secret while holding the scheduler and Dist seed fixed.
It compares the raw transcripts, then redacts either derived payload from all
text, JSON, runtime, and unexpected-error output. This exact-byte scrubber is
not taint tracking and does not detect transformed or fragmented payloads. Use
`jacquard relate FILE --vary secret=NAME --seed S --allow secret` only as
bounded evidence for that selected program, name, and seed.
Grant variation runs exactly twice with no extra `--allow`: one live
`net`, `infer`, or nonzero-seeded `dist` grant, then the released dry world.
It compares only ordered rendered result values, not routed events, Console
output, audits, calls, costs, latency, or external consequences. Forwarded,
mixed read/write, unsupported, and unknown effects are usage errors.
The `audit` commands append canonical hash-chained entries and publish their
heads. The `governance` and `why-effect` commands verify frozen Workspace v0
artifacts or conservatively analyze declaration-only source; they do not
execute that source or turn review evidence into host authorization.
