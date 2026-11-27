# Code Values And Grammar

Part of the Jacquard agent guide: quoted code as `Code` values, `eval`, and the
compact grammar of public `.jac` source. Start with [the core guide](../SKILL.md).

## Quote, Unquote, And Code

`quote` captures unresolved surface structure as a `Code` value. `unquote`
splices a `Code` value while inside a quote.

```jacquard doctest=skill-quote mode=check fixture=skill-quote.jac stdout=skill-quote.stdout stderr=empty exit=0
make-call(argument) = quote { add(unquote(argument), 1) }

candidate = quote { fn (x) -> add(x, 1) }

run-candidate() = {
  let function = `op:eval-code`(candidate)
  function(41)
}
```

Evaluation is authority: `eval-code` adds `Eval` to the row and requires
`--allow eval`. Granting `Eval` does not grant `Net`, `Fs`, or any other world
effect used by evaluated code. Constructed resolved hash references are
validated rather than trusted as a capability bypass.

Useful structural operations include:

- `code.eq?(a, b)`: metadata-erased structural equality
- `code.diff(a, b)`: text describing the smallest disagreeing subtrees
- `code.form(head, children)` and `code.un-form(code)`
- `code.of-int`, `code.to-int`, `code.of-text`, `code.to-text`

`unquote` outside `quote` is invalid. A splice must produce `Code`. Nested
quote levels are significant. `(expression : Type)` is a type annotation.
Named calls are rejected with E1238 anywhere inside a surface quote, including
inside a live `unquote`, because labels have no durable quoted carrier. Use a
positional call in quoted code. Labeled constructor patterns are independently
rejected there with E1237.

`jqd { (bootstrap form) }` is the surface escape for a kernel form that cannot
be represented without preserving an internal grouping. It is not general
mixed-syntax authoring.

## Compact Grammar

This practical grammar covers ordinary public source:

```text
file        := top-item*
top-item    := signature | definition | type-decl | effect-decl | expression
signature   := name ":" type
definition  := name ["(" ([label ":"] pattern ("," [label ":"] pattern)*)? ")"] "=" expression
type-decl   := ["opaque"] "type" Type type-vars? "=" ["|"] constructor ("|" constructor)*
effect-decl := mode "effect" Effect type-vars? "where" "{" uniform-op-signature+ "}"
| "effect" Effect type-vars? "where" "{" mode-op-signature+ "}"
uniform-op-signature := name ":" "(" ([label ":"] type ("," [label ":"] type)*)? ")" "->" type
mode-op-signature := mode name ":" "(" ([label ":"] type ("," [label ":"] type)*)? ")" "->" type
mode        := "once" | "multi"

expression  := call ("|>" call)*
call        := primary ("(" call-items? ")")*
call-items  := [label ":"] expression ("," [label ":"] expression)*
             | expression "with" label ":" expression ("," label ":" expression)*
primary     := literal | marked-text | name | tuple | list | block | fn | match | if
             | handle | quote | unquote | annotation
marked-text := '$"' ("{{" | "{" expression "}" | character-or-escape)* '"'
block       := "{" (let-item | try-item | expression)* expression "}"
let-item    := "let" ["rec"] pattern ["(" patterns? ")"] "=" expression
try-item    := ["let" pattern "="] "try" expression
fn          := "fn" "(" patterns? ")" "->" expression
match       := "match" expression "{" ("|" pattern "->" expression)+ "}"
if          := "if" expression "then" expression "else" expression
handle      := "handle" (atomic | block) "{" return-clause op-clause* "}"
quote       := "quote" "{" expression "}"
unquote     := "unquote" "(" expression ")"
annotation  := "(" expression ":" type ")"

pattern     := "_" | name | literal | Constructor ["(" (patterns | labeled-patterns)? ")"]
             | "(" patterns? ")" | pattern "as" name
labeled-patterns := label ":" pattern ("," label ":" pattern)* [","]
type        := type-application | tuple-type | function-type | forall-type
function-type := "(" types? ")" "->{" effects? ["|" row-var] "}" type
```

Indentation never determines structure. Calls, lists, tuples, and braced forms
allow line breaks. After `=`, `:`, `->`, `then`, `else`, and `|>`, a newline is
continuation rather than item separation.
