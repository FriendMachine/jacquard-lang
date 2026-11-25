# Standard Prelude

Part of the Jacquard agent guide: explicit dictionaries, core data functions,
control-effect handlers, and world test fixtures. Start with [the core guide](../SKILL.md).

Jacquard uses explicit dictionaries instead of implicit typeclasses. Operations
that need equality, ordering, rendering, or generic arithmetic receive `Eq`,
`Ord`, `Show`, or `Num` values:

```jacquard doctest=skill-dictionaries mode=run fixture=skill-dictionaries.jac stdout=skill-dictionaries.stdout stderr=empty exit=0
numbers = [3, 1, 2]

names = ["alice", "bob"]

three-numbers() = check.eq(list.length(numbers), 3, int.eq, int.show, "three numbers")

list.sort(numbers, int.ord)

list.contains?(names, "alice", text.eq)

num.add(int.num)(40, 2)
```

`int.num` and `real.num` are the standard numeric dictionaries. Alternate
instances are ordinary `MkNum` values and must be passed explicitly. The
concrete integer family is `int.add`, `int.sub`, `int.mul`, and `int.div`; bare
names remain for compatibility. There is no implicit instance search,
operator overloading, or numeric defaulting.

Core data and common functions:

- `Bool`: `True`, `False`; `bool.and`, `bool.or`, `bool.not`,
  `bool.and-then`, `bool.or-else`; flat conjunctions `bool.all([...])` and
  `bool.any([...])`; `list.all?(xs, p)` and `list.any?(xs, p)` (stop at the
  deciding item); closed intervals `int.between?(v, lo, hi)` and
  `real.between?(v, lo, hi)` (positional)
- `Option a`: `None`, `Some`; `option.map`, `option.then`,
  `option.with-default`, `option.get!`
- `Result e a`: `Err`, `Ok`; `result.map`, `result.map-error`,
  `result.then`, `result.with-default`, `result.get!`
- `List a`: `Nil`, `Cons`; `list.map`, `filter`, `fold`, `each`, `length`,
  `reverse`, `append`, `concat`, `range`, `zip`, `sort`, `find`, `take`
- Numeric: dotted `int.add`/`sub`/`mul`/`div` and `real.add`/`sub`/`mul`/`div`;
  compatibility `add`/`sub`/`mul`/`div`; `mod`, `eq`, and `lt`; `int.*` and
  `real.*` predicates/conversions; generic calls use an explicit `Num` value.
- Text: `text.concat`, `text.join(a, b, ...)` (variadic, no separator; join a
  list with a separator by folding with `text.join(acc, separator, part)`;
  `text.join-list(parts, separator)` still works but is a deprecated
  compatibility binding), `text.split`, `text.contains?`,
  `text.slice(t, start, end)` (codepoint indexes, end exclusive),
  `text.length`, `text.from-int`, `text.to-int` (`Option Int`),
  `text.from-real-fixed(x, decimals)`,
  the singleton-codepoint classes `text.ascii-digit?`/`ascii-letter?`/
  `ascii-space?`, `text.ascii-digit-value`, `text.codepoint` (`Option Int` for
  a one-codepoint text), direct
  predicate `text.eq?`, dictionary `text.eq`, and ordering dictionary
  `text.ord`; `real.from-int` converts directly
- Maps and sets carry their comparison dictionary in the value.
- Absent by design or not yet written: `text.starts-with?`, case conversion,
  codepoint-to-text, and `int.min` (`int.max` exists). Compose them from
  `text.slice`, comparisons, and `if`.

Control effects and handlers:

- `Abort`: `abort.to-option`, `abort.or`
- `Throw`: `throw.catch`, `throw.to-result`
- `State`: `state.run`, `state.eval`
- `Emit`: `emit.collect`, `emit.pipe`
- `Fault`: `fault.none`, `fault.random`, `fault.all`
- Scoped instances: `state.scoped`, `throw.scoped`, and `emit.scoped` pass
  their body a capability (`StateRef`, `ThrowRef`, `EmitRef`) and serve only
  operations made through it (`state.get-at(ref)`, `state.put-at(ref, v)`,
  `throw.throw-at(ref, x)`, `emit.emit-at(ref, w)`), so two stores of one type
  never confuse each other.

World fixtures include `net.scripted`, `net.record`, replay handlers,
`fs.in-memory`, `fs.read-only`, `clock.fixed`, `console.scripted`, and
`console.scripted-input` (one shared line list for both input operations). These
handlers discharge or interpose on effects; they are the testing seam usually
filled by mocks in other systems.

Naming is subject-first and data-first: `list.sort(xs, int.ord)`. Predicates
end in `?`; partial/effectful variants commonly end in `!`. `debug.inspect`
is for debugging output only, not library behavior.
