# Native Compilation And Carriers

Part of the Jacquard agent guide: native AOT builds, licensing of compiled
output, and the `.jqd` bootstrap carrier. Start with [the core guide](../SKILL.md).

## Native Compilation

`jac build` accepts `.jac` surface input directly as well as retained `.jqd`
kernel input. It uses the same parse/lower/resolution path as check and hash,
emits C for the reachable program, links the Jacquard runtime, and asks clang
or gcc to compile with optimization and LTO. It does not generate a persistent
bootstrap twin. For programs within the documented native subset, native and
interpreted behavior are expected to be byte-identical for stdout, stderr, and
exit status.

```sh
# Installed releases discover the runtime automatically. In a checkout only:
export JACQUARD_RUNTIME=/path/to/jacquard/runtime
jac build program.jac -o program
./program --allow console --seed 42
```

`jac export INPUT.jac -o OUTPUT.jqd` is the explicit conformance/debug escape
hatch. Under the same prelude context, repeated exports are byte-identical and
reparse to the same semantic top/member hashes; quoted constructor and
operation intent remains encoded with `surface-ref-v0`. Publication is atomic
and refuses an existing destination. The canonical bootstrap output erases
comments, formatting, spans, documentation, and provenance metadata by design.
It also contains only positional kernel applications and carries no
`call-abi-v1` companion, so an exported `.jqd` declaration cannot by itself
teach another surface source file its labels. The store companion is the
cross-file named-call boundary.
Export validates parsing, resolution, and canonical identity, but does not
typecheck; use `jac check`, `jac run`, or `jac build` for that guarantee.
Materialize stdin or other non-seekable input before export.

The backend supports deep handlers with both reusable `multi` continuations and
affine `once` resumptions, including the E0906 repeated-resume backstop. It also
supports Dist, quotes, splices, and structural Code operations. Its implemented
root grants are `console`, `clock`, `fs`, `dist`, and `infer`. Dynamic `eval`,
interpreter root Task scheduling, and typed Channels do not compile as native
execution features; `eval` reports E1102, while unsupported native grants are
refused with E1103. `--dry-run` and `--infer-cache` are interpreter tooling and
compiled binaries refuse them. A C toolchain is required. Deep non-tail
recursion uses the configured program stack; set `JACQUARD_STACK_MB` if needed.
Compiled units cache under `.jacquard-native/` by content hash.

Native binaries do not count `--fuel`; bound execution with the interpreter.
This is an AOT research backend, not a production optimizer, VM, or JIT. Do
not infer broad performance claims from a single benchmark.

## Licensing User Programs And Output

Jacquard itself is Apache-2.0. Jacquard claims no copyright in source
merely because it is written, checked, interpreted, or compiled with Jacquard.
Native executables link Jacquard runtime material, so the Jacquard Runtime and
Generated Output Permission explicitly permits user programs and compiled
output to use any license their authors choose, including proprietary terms.

The permission supplements Apache-2.0 for Runtime Material embedded in compiled
programs and generated output; the compiler and separately distributed runtime
source remain under Apache-2.0. See `RUNTIME-EXCEPTION.md`, `LICENSE`, and
`NOTICE`. This summarizes project licensing intent and is not legal advice.

## Bootstrap Carrier

`.jqd` is the permanent kernel/debug carrier used by the prelude, replay,
explicit export, and implementation fixtures. It is an s-expression encoding
of 27 fixed kernel forms. Native build also accepts `.jqd`, but ordinary users
should write and build `.jac` directly. Bootstrap calls are always positional;
there is no named-argument grammar in `.jqd`.

The expression heads are `lit`, `var`, `ref`, `lam`, `app`, `let`, `match`,
`tuple`, `handle`, `quote`, `unquote`, and `ann`; pattern heads are `pwild`,
`pvar`, `plit`, `pcon`, `ptuple`, and `pas`; declarations are `defterm`,
`deftype`, and `defeffect`. `;` starts a bootstrap comment.

```lisp
; add(1, 2)
(app (var add) (lit 1) (lit 2))

; fn (x) -> mul(x, x)
(lam ((pvar x)) (app (var mul) (var x) (var x)))
```

When both carriers exist, surface and bootstrap twins lower to the same kernel
and must hash equally. Ordinary programs and demos should not maintain a
hand-written `.jqd` twin; paired carriers are curated conformance fixtures.
Do not invent new kernel forms for surface sugar.
