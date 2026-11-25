More of the mistakes agents make on a first Jacquard draft are refused with
the form to use. `eq` applied to Text points to `text.eq?`; a dictionary
applied like a function (`int.eq(a, b)`) explains what a dictionary is and
names `eq`, `text.eq?` and `text.from-int`; `f(x) : Int = x` points to the
signature line; `->` without `{}` shows `(Int) ->{} Int`; `&&`, `!`, `!=` and
`==` name `bool.and`/`bool.and-then`, `bool.not`, `eq` and `text.eq?`. A
function, lambda or let-function parameter named like a constructor (`done`
beside `Done`) no longer raises W1201, since such a parameter binds by intent;
a lowercase pattern in a match arm, a `let` binder or an operation clause (whose
parameters are patterns) still does. `docs/SKILL.md`'s
first-draft list covers these, with a doc-tested example of each correct form.
Evidence: `test/cli/agent-papercuts.t`.
