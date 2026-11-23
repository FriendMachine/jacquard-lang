`jacquard check` warns (W0302) when one source binds a store name in several
kinds, for example an effect operation `charge` beside a type and constructor
`Charge`. Jacquard keeps the kinds apart, but a host that binds a program by
name cannot: jacquard-host's `prepare` refused such programs late, saying
only that a name appeared in several declaration groups. The warning names
both declarations and the other's location, at each later declaration that
binds the name (once per name there). Its scope is narrower than such a host's
refusal rule: a name bound only in one kind, a type and an effect sharing a
name, and names the prelude binds are not reported, so a host should still
bind by kind and name the clash itself. Evidence:
`test/cli/name-collisions.t`.
