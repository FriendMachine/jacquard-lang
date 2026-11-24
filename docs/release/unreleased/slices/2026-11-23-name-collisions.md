`jacquard check` warns (W0302) when a declaration binds a store name that an
earlier declaration of the same source binds in another kind (a type and an
effect sharing a name excepted), for example an
effect operation `charge` after a type and constructor `Charge`. Jacquard
keeps the kinds apart, but a host that binds a program by name cannot:
jacquard-host's `prepare` refuses such programs late, saying only that a name
appears in several declaration groups. The warning names the latest such
declaration of each other kind, with its location. A name-binding host's rule
is broader than this warning, so the warning is a hint, not a guarantee; the
host should still bind by kind and name the clash itself. Evidence:
`test/cli/name-collisions.t`.
