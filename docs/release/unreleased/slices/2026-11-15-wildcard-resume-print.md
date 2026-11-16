Wildcard-continuation printing, second part. Diff output now prints a
fragment at the quote depth where the differ found it: `Surface_print.print_fragment`
takes `?quote_depth` (default 0), and `Diff` counts the enclosing `quote`s
minus live `unquote`s along its walk and records the depth with each subtree
divergence. Before, a fragment of a quoted handler showed `resume _`, which
lowering refuses inside a quote (E1245) if the text is pasted back; now it
keeps the continuation's name, as the whole-declaration printer already did.
`docs/surface-syntax.md` and the earlier slice entry now say that the printer
decides by spelling alone, so `jacquard fmt` also rewrites a hand-written,
unreferenced `resume unused-resume` to `resume _` (identity unchanged), and that
a clause inside a live `unquote` in a quote prints `_`.
`test/test_diff.ml` pins the depth and rendering of a divergent handler that is
plain, quoted, inside a live splice, and inside a splice under two quotes;
`test/test_surface_handlers_quote.ml` pins `print_fragment` at depth 0 and 1
and the printer for `quote { quote { unquote(...) } }`, where the clause keeps
its name (lowering was already pinned by `test/cli/warp.t`). No other output
changes.
