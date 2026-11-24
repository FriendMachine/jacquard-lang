Papercuts agents hit when writing Jacquard (DOC.5): each is refused with the form to use, and a
parameter that shares a constructor's name is not flagged.

  $ export JACQUARD_PRELUDE=../../prelude

`eq` compares Ints; Text needs `text.eq?`.

  $ printf 'same(a) = eq(a, "x")\n' > eq-text.jac
  $ jacquard check eq-text.jac > eq-text.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 3p eq-text.out
    Next step: `eq` compares Int values; compare Text with `text.eq?(a, b)`

A dictionary is not a function.

  $ printf 'same(a, b) = int.eq(a, b)\n' > dict.jac
  $ jacquard check dict.jac > dict.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 3p dict.out
    Next step: `int.eq` is a dictionary that generic functions take as an argument (for example `list.contains?(xs, x, int.eq)`), not a function; compare Ints with `eq(a, b)` and Text with `text.eq?(a, b)`, and render an Int with `text.from-int(n)`

A signature is its own line, and an arrow lists its effects.

  $ printf 'f(x) : Int = x\n' > sig.jac
  $ jacquard check sig.jac > sig.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "a type signature goes on its own line before the definition" sig.out
  1
  $ printf 'f : (Int) -> Int\nf(x) = x\n' > arrow.jac
  $ jacquard check arrow.jac > arrow.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p arrow.out
    Cause: expected `{` immediately after `->` (an arrow type always lists its effects: `(Int) ->{} Int` for none), found ident(Int)

Boolean and comparison operators name the functions to use.

  $ printf 'f(a, b) = a && b\n' > and.jac
  $ jacquard check and.jac > and.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p and.out
    Cause: unexpected surface character `&`; there is no `&&`: write `bool.and(a, b)`, or `bool.and-then(a, fn () -> b)` to stop early
  $ printf 'f(a, b) = bool.and(a || b, True)\n' > or.jac
  $ jacquard check or.jac > or.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "there is no \`||\`" or.out
  2
  $ printf 'f(a) = !a\n' > not.jac
  $ jacquard check not.jac > not.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p not.out
    Cause: unexpected surface character `!`; there is no `!` operator: write `bool.not(x)`
  $ printf 'f(a, b) = a == b\n' > eqeq.jac
  $ jacquard check eqeq.jac > eqeq.out 2>&1; echo "exit:$?"
  exit:1
  $ sed -n 2p eqeq.out
    Cause: top-level items require a newline or `;`, found `=` (there is no `==`: compare Ints with `eq(a, b)` and Text with `text.eq?(a, b)`)

A parameter named like a constructor binds by intent; a match arm still warns.

  $ printf 'type Done = | Done\nf(done) = done\ng(x) = match x { | done -> 1 }\n' > case.jac
  $ jacquard check case.jac > case.out 2>&1; echo "exit:$?"
  exit:0
  $ grep -c W1201 case.out
  1
  $ grep -c "case.jac:3:" case.out
  1

Hints stay out of places where their advice would be wrong: a constructor declaration with a stray
`:`, a user's own `add`, and a user type named `Show` get the plain messages; `!=`, `<=` and `//`
get their own.

  $ printf 'type T = | A : Int\n' > colon.jac
  $ jacquard check colon.jac > colon.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "signature goes on its own line" colon.out
  0
  [1]
  $ printf 'add(a, b) = bool.and(a, b)\nx = add("x", True)\n' > own-add.jac
  $ jacquard check own-add.jac > own-add.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "take Int" own-add.out
  0
  [1]
  $ printf 'type Show = | Show(Int)\nh = Show(1)(2)\n' > own-show.jac
  $ jacquard check own-show.jac > own-show.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "dictionary" own-show.out
  0
  [1]
  $ printf 'f(a, b) = a != b\n' > ne.jac
  $ jacquard check ne.jac > ne.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "there is no \`!=\`" ne.out
  1
  $ printf 'x = 1 // note\n' > slash.jac
  $ jacquard check slash.jac > slash.out 2>&1; echo "exit:$?"
  exit:1
  $ grep -c "comments start with" slash.out
  1
