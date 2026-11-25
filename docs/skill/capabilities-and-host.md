# Capabilities And Host Authority

Part of the Jacquard agent guide: the `--allow` vocabulary, root authority
rules, and governed Workspace layers. Start with [the core guide](../SKILL.md).

## Capabilities And Root Authority

The complete `--allow` vocabulary is `clock`, `console`, `dist`, `eval`, `fs`,
`infer`, `net`, and `secret`. `Console`, `Clock`, `Fs`, and `Net` describe the
ordinary external world (`console` also grants `ConsoleInput`, whose `next-line`
returns `Option Text` and reports end of input as `None`, unlike `read-line`); `Eval` is dynamic-code authority, `Infer` delegates to
an unverified model boundary, `Secret` uses the environment adapter, and `Dist`
installs seeded sampling. `Dist` is computationally pure rather than outside-
world authority, but selecting its root sampling handler is still an explicit
grant. These root handlers exist only when granted:

```sh
jac check agent.jac --print-sigs
jac check agent.jac --manifest console,net
jac run agent.jac --allow console --allow net
```

Rules to rely on:

- The checker propagates effects through higher-order functions, returned
  closures, tuples, and polymorphic rows.
- A handler removes only its own effect.
- An ungranted world effect refuses before that effect executes.
- `check --manifest` never runs user code.
- `--dry-run` forwards reads and console/clock observation as documented,
  audits writes and network actions, and performs no audited world mutation.
- `--allow fs` currently grants the whole filesystem. Authority is effect-level,
  not path- or domain-level object capability.
- The interpreter's `--allow net` handler is a deterministic stub. Scripted and
  recording handlers ship, but a real socket/HTTP adapter does not.
- Evaluated code runs with root grants, not under an interposed attenuation
  handler. Audit its inferred requirements and grants accordingly.
- Top-level rows are closed. When an API expects an open-row thunk, eta-expand
  a named computation: `fn () -> model()`.

The world operations each grant enables, with a checked example, are listed in
the core guide's [Effects And Deep Mode-Aware Handlers](../SKILL.md#effects-and-deep-mode-aware-handlers).

Never infer authority from a hand-written manifest or comment; use the checked
row. Never add a grant merely to silence a refusal without reviewing why the
row contains that effect.

`Approval`, `Audit`, `Judge`, `Workspace`, and `Channel` have implemented
language or embedding boundaries but are not ordinary `--allow` root names.
In particular, a governance verdict is evidence consumed by trusted host code;
it does not install ambient authority.

## Governed Workspace Layers

Performing an operation directly in its own handler clause forwards it outward
(see [Effects And Deep Mode-Aware Handlers](../SKILL.md#effects-and-deep-mode-aware-handlers)).

For governed Workspace code, use the shipped
`workspace.forward-layer(sequence, policy, simulators, body)` for that pattern.
It forwards only the exact same once-mode Workspace operation and unchanged
arguments, shares the caller's `AuditSequence`, and retains `Workspace` rather
than introducing raw authority. Put one `workspace.live-layer` outside the
forwarding chain to terminate it in real drivers. Do not create another
sequence owner inside a layer or infer support for argument transforms.
