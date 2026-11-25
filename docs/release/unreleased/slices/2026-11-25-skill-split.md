The agent guide `docs/SKILL.md` is now a core page plus topic pages under
`docs/skill/`, so an agent can write, check, test and explore ordinary
effectful programs from the core page alone. The core keeps install, the
everyday commands and exit codes, the surface syntax with the first-draft
mistakes, effects and handlers with the world operations, the standard prelude
(the names every draft calls), the Warp entry point, the failure modes and the
recommended workflow; it shrinks from 56.8 KB to 39.3 KB. Reference material
moved verbatim to `commands.md`, `code-and-grammar.md`,
`capabilities-and-host.md`, `dist.md`, `warp.md`, `review-and-identity.md` and `native-and-carriers.md`, listed in
order in `docs/skill/INDEX` and linked from a closing Topic Pages section. Every
moved example keeps its fence and fixture and is still doc-tested.
Evidence: the docs doctest.
