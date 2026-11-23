A persistent store keeps the name of every declaration a run installed, even when the run is
killed while it evaluates a later top-level expression (the store writes its name index as each
declaration is installed; only the prelude load and evaluation-free walks coalesce the writes).

  $ export JACQUARD_PRELUDE=../../prelude
  $ cat > spin.jac <<'EOF'
  > helper(x) = int.add(x, 1)
  > spin(n) = spin(int.add(n, 1))
  > spin(0)
  > EOF
  $ timeout -s KILL 5 jacquard run --store st spin.jac > /dev/null 2>&1; echo "exit:$?"
  exit:124
  $ printf 'helper(41)\n' > use.jac
  $ jacquard run --store st use.jac
  42
