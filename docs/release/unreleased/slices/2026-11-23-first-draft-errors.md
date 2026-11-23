The shapes agents most often write in a first Jacquard draft now either mean
what was intended or are refused with the expected form. A constructor's
positional fields may be declared in parentheses, `World(List Text, Bool)`:
the same declaration (and identity) as `World (List Text) Bool`, which before
could not be written at all when the first field was compound, because the
parser read its parentheses as a field list. The printer keeps the
space-separated form unless the first field prints in parentheses (or comments
inside the parentheses need them). Signatures print a one-element tuple type as
`(a,)`, the form the type grammar reads back (`(a)` only groups). New hints: a missing `resume` before
an operation clause's continuation, `resume(k, v)` in an expression, `p.0`
tuple projection, camelCase and snake_case names, reserved words named as such, and Python-style names (`not`, `len`, `int.eq?`) that suggest the
Jacquard function first. A constructor-pattern arity error names the
constructor in surface spelling and shows its declaration; an operation
without a mode is reported once instead of twice. Evidence:
`test/cli/agent-first-drafts.t`.
