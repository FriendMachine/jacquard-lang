`jacquard check` warns (W0302) when one source binds a store name in several
kinds, for example an effect operation `charge` beside a type and constructor
`Charge`. Jacquard keeps the kinds apart, but a host that binds a program by
name cannot: jacquard-host's `prepare` refused such programs late, saying
only that a name appeared in several declaration groups. The warning names
both declarations and the other's location. A type and an effect sharing a
name (the prelude's own `Secret` idiom) is not reported, and neither is a
collision with a prelude name, which common words (`result`, `report`) would
make noisy; a host should tell kinds apart itself. Evidence:
`test/cli/name-collisions.t`.
