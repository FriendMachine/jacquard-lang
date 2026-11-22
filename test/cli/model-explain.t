Follow-ups to `jacquard model explain` (docs/designs/model-dependencies.md §3.5).

  $ export JACQUARD_PRELUDE=$PWD/../../prelude

The closure manifest of a result whose declarations all load is unchanged:
these bytes were taken from the binary before callee grouping, body diffs and
the manifest's root check.

  $ mkdir pin && cd pin
  $ cat > m.jac <<'JAC'
  > type Wrap = W Int
  > inc(x) = add(x, 1)
  > go(n) = match W(inc(n)) { | W(x) -> x }
  > JAC
  $ printf 'jacquard-model format=1\nsource m.jac\nresult g entry go args 1 driver run fuel=10000\n' > doc.model
  $ jacquard model eval doc.model
  g: fresh
    value 2
  $ m=$(grep '^entry-closure ' .jacquard/model-cache/history/*/g | cut -d' ' -f2); echo $m; cat ".jacquard/model-cache/snapshots/$m" | head -3; wc -l < ".jacquard/model-cache/snapshots/$m"
  9d892f2b7d4ce4ee12f1085c1a5615162470af01938c5935a83c41a4c62ba728
  jacquard-model-closure format=1
  root b4e1e39c8f180a7d7b457b2d8a627df2af06b80f08f9f11e48f3da4b4d4ceda6
  add term a73fc98649399549a6a9212901dc20df3ed6e765b316ced9bbf39f8fd83c03c0 ba2fefd45d8da8dee427855b668abf2287b0d8bda64f968e81b40e559cffd73c
  10
  $ cd ..

A changed callee is named once per declaration, with its kind: aliases (two
names bound to one declaration) and the members of a group or a type are one
line, each name spelled as the surface spells it, followed by the readable
`jacquard diff` of the two retained bodies.

  $ mkdir callees && cd callees
  $ cat > m.jac <<'JAC'
  > type Wrap = W Int
  > inc(x) = add(x, 1)
  > bump(x) = add(x, 1)
  > even(n) = if eq(n, 0) then True else odd(sub(n, 1))
  > odd(n) = if eq(n, 0) then False else even(sub(n, 1))
  > go(n) = match W(add(inc(n), bump(n))) { | W(x) -> if even(x) then x else 0 | _ -> 0 }
  > JAC
  $ printf 'jacquard-model format=1\nsource m.jac\nresult g entry go args 1 driver run fuel=100000\n' > doc.model
  $ jacquard model eval doc.model
  g: fresh
    value 4
  $ sed -i 's/add(x, 1)/add(x, 3)/; s/then True else/then eq(0, 0) else/' m.jac
  $ cat m.jac
  type Wrap = W Int
  inc(x) = add(x, 3)
  bump(x) = add(x, 3)
  even(n) = if eq(n, 0) then eq(0, 0) else odd(sub(n, 1))
  odd(n) = if eq(n, 0) then False else even(sub(n, 1))
  go(n) = match W(add(inc(n), bump(n))) { | W(x) -> if even(x) then x else 0 | _ -> 0 }
  $ jacquard model explain doc.model > a.out; sed -E 's/[0-9]{4}-[0-9-]+T[0-9:]+Z/TIME/' a.out
  g: stale (last evaluated TIME)
    entry go changed
    callee term bump, inc changed
      body       1  ->  3
    callee term even, odd changed
      clause 1   True  ->  eq(0, 0)
  $ jacquard model explain doc.model --json > a.json; grep -o '"subject":"[^"]*"' a.json; grep -o '"names":\[[^]]*\]' a.json; grep -o '"diff":' a.json | wc -l
  "subject":"go"
  "subject":"bump, inc"
  "subject":"even, odd"
  "names":[{"kind":"term","name":"bump"},{"kind":"term","name":"inc"}]
  "names":[{"kind":"term","name":"even"},{"kind":"term","name":"odd"}]
  2
  $ jacquard model eval doc.model > /dev/null
  $ printf 'type Wrap = W Int | V Int\n' > t.jac; sed -n '2,$p' m.jac >> t.jac; mv t.jac m.jac
  $ jacquard model explain doc.model > b.out; sed -E 's/[0-9]{4}-[0-9-]+T[0-9:]+Z/TIME/' b.out
  g: stale (last evaluated TIME)
    entry go changed
    callee con V added
    callee con W, type Wrap changed
      definition  type Wrap = | W Int  ->  type Wrap = | W Int | V Int
    last change (TIME):
      entry go changed
      callee term bump, inc changed
        body       1  ->  3
      callee term even, odd changed
        clause 1   True  ->  eq(0, 0)
  $ cd ..

A longer change is stacked as `-`/`+` lines.

  $ mkdir stacked && cd stacked
  $ printf 'score(a, b) = add(mul(a, 1000), mul(b, 2000))\ngo(n) = score(n, n)\n' > m.jac
  $ printf 'jacquard-model format=1\nsource m.jac\nresult g entry go args 1 driver run fuel=10000\n' > doc.model
  $ jacquard model eval doc.model > /dev/null
  $ sed -i 's/= add(mul(a, 1000), mul(b, 2000))/= if eq(a, b) then mul(a, 1000) else add(mul(a, 1000), mul(b, 2000))/' m.jac
  $ jacquard model explain doc.model > s.out; sed -E 's/[0-9]{4}-[0-9-]+T[0-9:]+Z/TIME/' s.out
  g: stale (last evaluated TIME)
    entry go changed
    callee con False, True, type Bool added
    callee term eq added
    callee term score changed
      body
        - add(int.mul(a, 1000), int.mul(b, 2000))
        + match eq(a, b) {
            | True -> int.mul(a, 1000)
            | False -> add(int.mul(a, 1000), int.mul(b, 2000))
          }
  $ cd ..

Each side of a body diff names the declarations retained in its own
manifest: when a type gains a variant, the old body still names the old
constructors, as `jacquard diff` does, and so does a change between two
earlier records.

  $ mkdir shapes && cd shapes
  $ cat > m.jac <<'JAC'
  > type Shape = Circle Int | Square Int
  > area(s) = match s { | Circle(r) -> mul(r, r) | Square(w) -> mul(w, w) }
  > go(n) = area(Circle(n))
  > JAC
  $ printf 'jacquard-model format=1\nsource m.jac\nresult g entry go args 1 driver run fuel=10000\n' > doc.model
  $ jacquard model eval doc.model > /dev/null; cp m.jac m0.jac
  $ cat > m.jac <<'JAC'
  > type Shape = Circle Int | Square Int | Tri Int
  > area(s) = match s { | Circle(r) -> mul(r, r) | Square(w) -> mul(w, w) | Tri(t) -> t }
  > go(n) = area(Circle(n))
  > JAC
  $ jacquard model explain doc.model > a.out; sed -E 's/[0-9]{4}-[0-9-]+T[0-9:]+Z/TIME/' a.out
  g: stale (last evaluated TIME)
    entry go changed
    callee term area changed
      body
        - match s {
            | Circle(r) -> int.mul(r, r)
            | Square(w) -> int.mul(w, w)
          }
        + match s {
            | Circle(r) -> int.mul(r, r)
            | Square(w) -> int.mul(w, w)
            | Tri(t) -> t
          }
    callee con Circle, Square, type Shape changed
      definition
        - type Shape = | Circle Int | Square Int
        + type Shape = | Circle Int | Square Int | Tri Int
    callee con Tri added
  $ jacquard diff m0.jac m.jac
  changed  area
    body
      - match s {
          | Circle(r) -> int.mul(r, r)
          | Square(w) -> int.mul(w, w)
        }
      + match s {
          | Circle(r) -> int.mul(r, r)
          | Square(w) -> int.mul(w, w)
          | Tri(t) -> t
        }
    dependents: go
  changed  circle
    definition
      - type Shape = | Circle Int | Square Int
      + type Shape = | Circle Int | Square Int | Tri Int
    dependents: area, go
  changed  go
    body       area#10842461ed7d  ->  area#dd531b4b1863
    body       Circle#9ad4c784c47d  ->  Circle#617e3e25f5e9
  changed  shape
    definition
      - type Shape = | Circle Int | Square Int
      + type Shape = | Circle Int | Square Int | Tri Int
  changed  square
    definition
      - type Shape = | Circle Int | Square Int
      + type Shape = | Circle Int | Square Int | Tri Int
    dependents: area
  added    tri
  $ jacquard model explain doc.model --json > a.json; grep -o '"diff":\[[^]]*\]' a.json > diffs; grep -vc '"diff":\[\]' diffs; grep -c '#' diffs
  2
  0
  [1]
  $ jacquard model eval doc.model > /dev/null
  $ jacquard model explain doc.model > b.out; sed -E 's/[0-9]{4}-[0-9-]+T[0-9:]+Z/TIME/' b.out
  g: current (evaluated TIME)
    last change (TIME):
      entry go changed
      callee term area changed
        body
          - match s {
              | Circle(r) -> int.mul(r, r)
              | Square(w) -> int.mul(w, w)
            }
          + match s {
              | Circle(r) -> int.mul(r, r)
              | Square(w) -> int.mul(w, w)
              | Tri(t) -> t
            }
      callee con Circle, Square, type Shape changed
        definition
          - type Shape = | Circle Int | Square Int
          + type Shape = | Circle Int | Square Int | Tri Int
      callee con Tri added
  $ cd ..

A history larger than 64 MiB is never read, and explain says the next
evaluation moves it aside. That evaluation moves it, whole, to `r.1` beside it
(W1804) and starts a new history with its record. A damaged history is
unavailable to explain until the next evaluation repairs it.

  $ mkdir large && cd large
  $ printf 'f(x) = add(x, 1)\n' > m.jac
  $ printf 'jacquard-model format=1\nsource m.jac\nresult r entry f args 1 driver run fuel=10000\n' > doc.model
  $ jacquard model eval doc.model > /dev/null
  $ h=$(ls .jacquard/model-cache/history/*/r); truncate -s 70M "$h"
  $ jacquard model explain doc.model
  r: history unavailable (larger than 67108864 bytes; the next model eval that records this result moves it to r.1 and starts a new history)
  $ sed -i 's/add(x, 1)/add(x, 2)/' m.jac
  $ jacquard model eval doc.model > big.out 2>&1; echo "exit=$?"; sed -E 's#[^ ]*/history/[0-9a-f]+/r#HISTORY#' big.out
  exit=0
  warning[W1804]: A model result's history was moved aside and a new one started.
    Cause: result r: the history was larger than 67108864 bytes; every earlier record is kept in HISTORY.1, and a new history was started
    Next step: Nothing is needed: the moved file keeps every earlier record; model eval and explain never read it, and it may be deleted.
  r: fresh
    value 3
  $ stat -c %s "$h.1"; grep -c '^entry bytes=' "$h"; grep '^previous ' "$h"
  73400320
  1
  previous none
  $ jacquard model explain doc.model > rotated.out; sed -E 's/[0-9]{4}-[0-9-]+T[0-9:]+Z/TIME/' rotated.out
  r: current (evaluated TIME)
  $ echo junk >> "$h"
  $ jacquard model explain doc.model
  r: history unavailable (bad frame; the next model eval keeps every record before the damage)
  $ jacquard model eval doc.model > /dev/null 2>&1; jacquard model explain doc.model > fixed.out; sed -E 's/[0-9]{4}-[0-9-]+T[0-9:]+Z/TIME/' fixed.out
  r: current (evaluated TIME)
  $ cd ..

Outcomes are kept per build: the key names only the Core release, so another
build of the same release (here, the same binary with one byte appended)
recomputes rather than serving what this build stored.

  $ mkdir builds && cd builds
  $ printf 'f(x) = add(x, 1)\n' > m.jac
  $ printf 'jacquard-model format=1\nsource m.jac\nresult r entry f args 1 driver run fuel=10000\n' > doc.model
  $ jacquard model eval doc.model
  r: fresh
    value 2
  $ jacquard model eval doc.model
  r: cached
    value 2
  $ ls .jacquard/model-cache/outcomes > this-build; grep -cE '^[0-9a-f]{64}$' this-build
  1
  $ cp "$(command -v jacquard)" ./other-build && chmod u+w ./other-build && printf 'x' >> ./other-build
  $ ./other-build model eval doc.model
  r: fresh
    value 2
  $ ./other-build model eval doc.model
  r: cached
    value 2
  $ ls .jacquard/model-cache/outcomes | grep -cE '^[0-9a-f]{64}$'
  2
  $ jacquard model eval doc.model
  r: cached
    value 2
  $ rm other-build

Cache files are never read through a symbolic link: an outcome that is a link
is ignored with W1800 and replaced by a file; a history that is a link is
refused and left as it is.

  $ o=$(ls -d .jacquard/model-cache/outcomes/$(cat this-build)/*); cp "$o" real; rm "$o"; ln -s "$PWD/real" "$o"
  $ jacquard model eval doc.model > link.out 2>&1; echo "exit=$?"; sed -E 's#[^ ]*/outcomes/[0-9a-f]+/[0-9a-f]+#OUTCOME#' link.out
  exit=0
  warning[W1800]: A model cache file was ignored.
    Cause: OUTCOME: a symbolic link
    Next step: Nothing is needed: the result was recomputed and the file replaced.
  r: fresh
    value 2
  $ test -L "$o" || echo "a file again"
  a file again
  $ h=$(ls .jacquard/model-cache/history/*/r); mv "$h" history.real; ln -s "$PWD/history.real" "$h"
  $ sed -i 's/add(x, 1)/add(x, 5)/' m.jac
  $ jacquard model eval doc.model > hlink.out 2>&1; echo "exit=$?"; grep -o 'W1802\|a symbolic link' hlink.out
  exit=0
  W1802
  a symbolic link
  $ jacquard model explain doc.model
  r: history unavailable (a symbolic link)
  $ test -L "$h" && grep -c '^entry bytes=' history.real
  1
  $ cd ..

Existing cache directories that others can reach are made owner-only; the
cache directory itself, which `--cache` may name, is left as it is, and so is
the outcomes directory of the other build, which this build never writes.

  $ cd builds
  $ chmod 755 .jacquard/model-cache .jacquard/model-cache/outcomes .jacquard/model-cache/outcomes/* .jacquard/model-cache/history .jacquard/model-cache/history/* .jacquard/model-cache/snapshots
  $ jacquard model eval doc.model > /dev/null 2>&1
  $ stat -c '%a %n' .jacquard/model-cache .jacquard/model-cache/outcomes .jacquard/model-cache/history .jacquard/model-cache/snapshots
  755 .jacquard/model-cache
  700 .jacquard/model-cache/outcomes
  700 .jacquard/model-cache/history
  700 .jacquard/model-cache/snapshots
  $ stat -c %a .jacquard/model-cache/outcomes/* .jacquard/model-cache/history/* | sort -u
  700
  755

Outcomes are filed under the build that is running, even when the
executable's file is replaced while it runs.

  $ mkdir running && cd running
  $ printf 'f(x) = add(x, 1)\n' > m.jac
  $ printf 'jacquard-model format=1\nsource m.jac\nresult r entry f args 1 driver run fuel=10000\n' > doc.model
  $ jacquard model eval doc.model --cache c0 > /dev/null; ls c0/outcomes > expected
  $ cp "$(command -v jacquard)" ./jq && chmod u+w ./jq && cp ./jq ./other && printf 'x' >> ./other
  $ ./jq model eval doc.model --cache c1 > run.out 2>&1 & p=$!; while kill -0 $p 2>/dev/null && [ "$(readlink /proc/$p/exe)" != "$(pwd -P)/jq" ]; do :; done; mv ./other ./jq; wait $p; echo "exit=$?"; cat run.out
  exit=0
  r: fresh
    value 2
  $ ls c1/outcomes | cmp - expected && echo "this build"
  this build
  $ rm jq
  $ cd ..

A cache directory below the cache root that is a symbolic link (or not a
directory at all) is never read through: nothing is served from it or stored
in it, and explain reads no history or snapshot through it. Explain creates
no cache directory.

  $ mkdir linked && cd linked
  $ printf 'f(x) = add(x, 1)\n' > m.jac
  $ printf 'jacquard-model format=1\nsource m.jac\nresult r entry f args 1 driver run fuel=10000\n' > doc.model
  $ jacquard model explain doc.model --cache c; test -e c || echo "no cache created"
  r: never evaluated
  no cache created
  $ jacquard model eval doc.model --cache c > /dev/null; b=$(ls c/outcomes)
  $ mv c/outcomes/$b elsewhere; ln -s "$PWD/elsewhere" c/outcomes/$b
  $ jacquard model eval doc.model --cache c > l1.out 2>&1; echo "exit=$?"; sed -E 's#[^ ]*/c/#C/#; s#outcomes/[0-9a-f]+#outcomes/BUILD#g; s#/[0-9a-f]{64}:#/KEY:#' l1.out
  exit=0
  warning[W1801]: A model result could not be written to the cache.
    Cause: c/outcomes/BUILD/KEY: c/outcomes/BUILD: not a directory
    Next step: Make each cache path named in the cause a directory of its own, not a symbolic link or another kind of file; the result itself is unaffected.
  r: uncacheable (write-failed)
    value 2
  $ rm c/outcomes/$b; mv elsewhere c/outcomes/$b; mv c/outcomes outs; ln -s "$PWD/outs" c/outcomes
  $ jacquard model eval doc.model --cache c > l2.out 2>&1; echo "exit=$?"; sed -E 's#[^ ]*/c/#C/#; s#outcomes/[0-9a-f]+#outcomes/BUILD#g; s#/[0-9a-f]{64}:#/KEY:#' l2.out
  exit=0
  warning[W1801]: A model result could not be written to the cache.
    Cause: c/outcomes/BUILD/KEY: c/outcomes: not a directory
    Next step: Make each cache path named in the cause a directory of its own, not a symbolic link or another kind of file; the result itself is unaffected.
  r: uncacheable (write-failed)
    value 2
  $ rm c/outcomes; touch c/outcomes
  $ jacquard model eval doc.model --cache c > l3.out 2>&1; echo "exit=$?"; sed -E 's#[^ ]*/c/#C/#; s#outcomes/[0-9a-f]+#outcomes/BUILD#g; s#/[0-9a-f]{64}:#/KEY:#' l3.out
  exit=0
  warning[W1801]: A model result could not be written to the cache.
    Cause: c/outcomes/BUILD/KEY: c/outcomes: not a directory
    Next step: Make each cache path named in the cause a directory of its own, not a symbolic link or another kind of file; the result itself is unaffected.
  r: uncacheable (write-failed)
    value 2
  $ rm c/outcomes; mv outs c/outcomes; jacquard model eval doc.model --cache c
  r: cached
    value 2
  $ h=$(ls -d c/history/*); mv "$h" hdir; ln -s "$PWD/hdir" "$h"
  $ jacquard model explain doc.model --cache c > h.out; sed -E 's#c/history/[0-9a-f]+#c/history/DOC#' h.out
  r: history unavailable (c/history/DOC: not a directory)
  $ rm "$h"; mv hdir "$h"; mv c/snapshots snaps; ln -s "$PWD/snaps" c/snapshots
  $ jacquard model explain doc.model --cache c
  r: unknown (snapshots gone: inline 1, policy, entry f)
  $ jacquard model eval doc.model --cache c > s.out 2>&1; echo "exit=$?"; cat s.out
  exit=0
  warning[W1802]: A model result's history could not be written.
    Cause: result r: c/snapshots: not a directory
    Next step: Make each cache path named in the cause a directory of its own, not a symbolic link or another kind of file; the result itself is unaffected.
  r: cached
    value 2
  $ rm c/snapshots; mv snaps c/snapshots

An outcome path that is a directory cannot be replaced by a file: the result
is not stored, and the warning says what is in the way.

  $ o=$(ls -d c/outcomes/*/*); rm "$o"; mkdir "$o"
  $ jacquard model eval doc.model --cache c > d.out 2>&1; echo "exit=$?"; sed -E 's#outcomes/[0-9a-f]+/[0-9a-f]+#outcomes/BUILD/KEY#' d.out
  exit=0
  warning[W1801]: A model result could not be written to the cache.
    Cause: c/outcomes/BUILD/KEY: a directory is in the way
    Next step: Remove that directory so the result can be stored; the result itself is unaffected.
  r: uncacheable (write-failed)
    value 2
  $ rmdir "$o"; jacquard model eval doc.model --cache c
  r: fresh
    value 2
  $ cd ..
