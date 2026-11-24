`jacquard check` warns when one source binds a store name in several kinds (DX.7). The
language keeps a term, constructor, operation and type apart, but a host that binds a program
by name cannot, and used to refuse it late without naming the other declaration.

  $ export JACQUARD_PRELUDE=../../prelude
  $ cat > shop.jac <<'EOF'
  > type Charge = | Charge(amount: Int)
  > type Order = | Order(id: Text, charge: Int)
  > multi effect Pay where {
  >   charge : (Int) -> Bool
  > }
  > EOF
  $ jacquard check shop.jac; echo "exit:$?"
  shop.jac:3:1-5:2: warning[W0302]: A public name is bound by more than one declaration.
    Cause: operation `charge` shares the store name `charge` with constructor `Charge` at shop.jac:1:1-36 and type `Charge` at shop.jac:1:1-36; the language keeps the kinds apart, but a host that binds the program by name (such as jacquard-host) refuses it
    Next step: Rename one of the declarations.
  ok
  exit:0

A record field `charge` does not collide: its accessor is `order.charge`. These declarations
raise no W0302 (a host that binds by name alone may still refuse some of them).

  $ cat > fine.jac <<'EOF'
  > type Wrapper = | Wrapper Text
  > type Token = | MintedToken
  > once effect Token where {
  >   token.mint : () -> Token
  > }
  > multi effect Pay where {
  >   pay : (Int) -> Bool
  > }
  > EOF
  $ jacquard check fine.jac; echo "exit:$?"
  ok
  exit:0

A declaration that binds the name twice (a type and its constructor) gets one warning there.

  $ cat > once.jac <<'EOF'
  > multi effect Pay where {
  >   charge : (Int) -> Bool
  > }
  > type Charge = | Charge(amount: Int)
  > EOF
  $ jacquard check once.jac > once.out 2>&1; echo "exit:$?"
  exit:0
  $ grep -c W0302 once.out
  1
  $ sed -n 2p once.out
    Cause: type `Charge` and constructor `Charge` share the store name `charge` with operation `charge` at once.jac:1:1-3:2; the language keeps the kinds apart, but a host that binds the program by name (such as jacquard-host) refuses it
