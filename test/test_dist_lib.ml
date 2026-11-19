open Jacquard

(* SL.7: uniform-int, the dictionary-honest dist.pmf, enumerate/tally, and the
   sampling root handler. *)

let store, ctx = Eval_support.make_prelude_ctx ()

let eval_ok src =
  match Eval_support.eval_with ctx store src with
  | Ok v -> v
  | Error e -> Alcotest.failf "eval failed on %s: %s" src (Runtime_err.to_string e)

let show src = Value.show (eval_ok src)

let real_of src =
  match eval_ok src with
  | Value.VReal r -> r
  | v -> Alcotest.failf "expected a real, got %s" (Value.show v)

let close a b = Float.abs (a -. b) < 1e-9

let test_uniform_int_support_pmf () =
  Alcotest.(check string)
    "support of 1..4"
    "cons(mk-pair(1, 0.25), cons(mk-pair(2, 0.25), cons(mk-pair(3, 0.25), cons(mk-pair(4, 0.25), \
     nil))))"
    (show "(app (var support) (app (var uniform-int) (lit 1) (lit 4)))");
  Alcotest.(check bool)
    "native pmf in range" true
    (close (real_of "(app (var pmf) (app (var uniform-int) (lit 1) (lit 6)) (lit 3))") (1. /. 6.));
  Alcotest.(check bool)
    "native pmf off range" true
    (close (real_of "(app (var pmf) (app (var uniform-int) (lit 1) (lit 6)) (lit 9))") 0.0);
  (* huge ranges: pmf works directly, support refuses with the enumeration cap *)
  Alcotest.(check bool)
    "pmf on a huge range" true
    (close (real_of "(app (var pmf) (app (var uniform-int) (lit 1) (lit 1000000)) (lit 5))") 1e-6);
  (match
     Eval_support.eval_with ctx store
       "(app (var support) (app (var uniform-int) (lit 1) (lit 1000000)))"
   with
  | Error (Runtime_err.Arithmetic m) ->
      Alcotest.(check bool)
        ("cap message: " ^ m) true
        (String.length m > 0 && String.sub m 0 11 = "uniform-int")
  | Ok v -> Alcotest.failf "expected the cap error, got %s" (Value.show v)
  | Error e -> Alcotest.failf "wrong error: %s" (Runtime_err.to_string e));
  match
    Eval_support.eval_with ctx store "(app (var support) (app (var uniform-int) (lit 4) (lit 1)))"
  with
  | Error (Runtime_err.Arithmetic _) -> ()
  | r ->
      Alcotest.failf "empty range must be an arithmetic error, got %s"
        (match r with Ok v -> Value.show v | Error e -> Runtime_err.to_string e)

let test_dist_pmf_agrees_with_native () =
  List.iter
    (fun (dist, x) ->
      let native = real_of (Printf.sprintf "(app (var pmf) %s %s)" dist x) in
      let dict = real_of (Printf.sprintf "(app (var dist.pmf) %s %s (var int.eq))" dist x) in
      Alcotest.(check bool)
        (Printf.sprintf "%s at %s: %g = %g" dist x native dict)
        true (close native dict))
    [
      ("(app (var uniform-int) (lit 1) (lit 6))", "(lit 3)");
      ("(app (var uniform-int) (lit 1) (lit 6))", "(lit 7)");
      ( "(app (var categorical) (app (var cons) (app (var mk-pair) (lit 1) (lit 0.25)) (app (var \
         cons) (app (var mk-pair) (lit 2) (lit 0.5)) (app (var cons) (app (var mk-pair) (lit 1) \
         (lit 0.25)) (var nil)))))",
        "(lit 1)" (* duplicate support entries must sum: 0.5 *) );
    ]

(* two-coins: dist.enumerate (normalized, unmerged) then dist.tally (explicit eq) must
   equal the OCaml driver's merged posterior *)
let test_enumerate_tally_vs_native () =
  let model =
    "(lam () (let nonrec (pvar a) (app (var sample) (app (var bernoulli) (lit 0.5))) (let nonrec \
     (pvar b) (app (var sample) (app (var bernoulli) (lit 0.5))) (match (tuple (var a) (var b)) \
     (clause (ptuple (pcon true) (pcon true)) (lit 2)) (clause (ptuple (pcon true) (pcon false)) \
     (lit 1)) (clause (ptuple (pcon false) (pcon true)) (lit 1)) (clause (ptuple (pcon false) \
     (pcon false)) (lit 0))))))"
  in
  (* in-language: enumerate then tally with int.eq *)
  let tallied =
    eval_ok
      (Printf.sprintf "(app (var dist.tally) (app (var dist.enumerate) %s) (var int.eq))" model)
  in
  let rec entries_of = function
    | Value.VCon { name = "nil"; _ } -> []
    | Value.VCon
        {
          name = "cons";
          args = [ Value.VCon { name = "mk-pair"; args = [ v; Value.VReal p ]; _ }; rest ];
          _;
        } ->
        (Value.show v, p) :: entries_of rest
    | v -> Alcotest.failf "not a weighted list: %s" (Value.show v)
  in
  let in_language = entries_of tallied in
  (* the OCaml driver's merged posterior over the same model expression *)
  let state =
    match Reader.parse_one ~file:"m.jqd" (Printf.sprintf "(app %s)" model) with
    | Error ds -> Eval_support.fail_diags "parse" ds
    | Ok f -> (
        match
          Result.bind (Kernel.expr_of_form f) (Resolve.resolve_expr (Store.names_view store))
        with
        | Error ds -> Eval_support.fail_diags "resolve" ds
        | Ok e -> Eval.expr_state e)
  in
  let native =
    match Infer_dist.enumerate ctx state with
    | Ok p -> List.map (fun (v, pr) -> (Value.show v, pr)) p.Infer_dist.entries
    | Error ds -> Eval_support.fail_diags "enumerate" ds
  in
  Alcotest.(check int) "same support size" (List.length native) (List.length in_language);
  List.iter
    (fun (key, p) ->
      match List.assoc_opt key in_language with
      | Some p' ->
          Alcotest.(check bool) (Printf.sprintf "P(%s): %g = %g" key p p') true (close p p')
      | None -> Alcotest.failf "in-language posterior missing %s" key)
    native

(* enumerate is normalized but UNMERGED: the two (true,false)/(false,true) leaves both
   render value 1 and stay separate entries until tally merges them *)
let test_enumerate_unmerged () =
  let entries =
    show
      "(app (var dist.enumerate) (lam () (let nonrec (pvar a) (app (var sample) (app (var \
       bernoulli) (lit 0.5))) (let nonrec (pvar b) (app (var sample) (app (var bernoulli) (lit \
       0.5))) (match (tuple (var a) (var b)) (clause (ptuple (pcon true) (pcon true)) (lit 2)) \
       (clause (pwild) (lit 1)))))))"
  in
  Alcotest.(check string)
    "four leaves, three ones"
    "cons(mk-pair(2, 0.25), cons(mk-pair(1, 0.25), cons(mk-pair(1, 0.25), cons(mk-pair(1, 0.25), \
     nil))))"
    entries

let test_sampling_bounds_and_determinism () =
  let rng = Infer_dist.Rng.make 7 in
  let seen = Array.make 6 false in
  for _ = 1 to 1000 do
    match Infer_dist.sample_dist ctx rng (Infer_dist.UniformInt (1, 6)) with
    | Ok (Value.VInt x) ->
        Alcotest.(check bool) (Printf.sprintf "%d in 1..6" x) true (x >= 1 && x <= 6);
        seen.(x - 1) <- true
    | Ok v -> Alcotest.failf "not an int: %s" (Value.show v)
    | Error e -> Alcotest.failf "sample failed: %s" (Runtime_err.to_string e)
  done;
  Alcotest.(check bool) "all six faces hit in 1000 draws" true (Array.for_all Fun.id seen);
  (* same seed, same stream *)
  let draws seed =
    let rng = Infer_dist.Rng.make seed in
    List.init 20 (fun _ ->
        match Infer_dist.sample_dist ctx rng (Infer_dist.UniformInt (1, 6)) with
        | Ok (Value.VInt x) -> x
        | _ -> -1)
  in
  Alcotest.(check (list int)) "seeded determinism" (draws 42) (draws 42)

(* the sampling grant end to end: sample resumes with a drawn value; observe is a defect *)
let test_root_sampling_handler () =
  let store2, ctx2 = Eval_support.make_prelude_ctx () in
  (match Prelude.grant ctx2 "dist" ~out:ignore ~seed:42 ~infer_cache:None with
  | Ok () -> ()
  | Error ds -> Eval_support.fail_diags "grant dist" ds);
  (match
     Eval_support.eval_with ctx2 store2 "(app (var sample) (app (var uniform-int) (lit 1) (lit 6)))"
   with
  | Ok (Value.VInt x) -> Alcotest.(check bool) "die in range" true (x >= 1 && x <= 6)
  | r ->
      Alcotest.failf "sampling failed: %s"
        (match r with Ok v -> Value.show v | Error e -> Runtime_err.to_string e));
  match
    Eval_support.eval_with ctx2 store2
      "(app (var observe) (app (var bernoulli) (lit 0.5)) (var true))"
  with
  | Error Runtime_err.Observe_at_root -> ()
  | r ->
      Alcotest.failf "observe at root must be the D7 defect, got %s"
        (match r with Ok v -> Value.show v | Error e -> Runtime_err.to_string e)

(* An inference driver owns its model's sample and observe: with the root dist grant installed, a
   driver gives exactly the grant-free result, its own seed decides, and a nested driver composes.
   Before the correction the root sampler answered every draw (one enumerated path, the root
   stream instead of the driver's seed) and the root observe stub failed the run. *)
let test_driver_owns_dist_under_grant () =
  let plain_store, plain = Eval_support.make_prelude_ctx () in
  let granted_store, granted = Eval_support.make_prelude_ctx () in
  (match Prelude.grant granted "dist" ~out:ignore ~seed:1 ~infer_cache:None with
  | Ok () -> ()
  | Error ds -> Eval_support.fail_diags "grant dist" ds);
  let state store src () =
    match Reader.parse_one ~file:"model.jqd" src with
    | Error ds -> Eval_support.fail_diags "parse" ds
    | Ok f -> (
        match
          Result.bind (Kernel.expr_of_form f) (Resolve.resolve_expr (Store.names_view store))
        with
        | Error ds -> Eval_support.fail_diags "resolve" ds
        | Ok e -> Eval.expr_state e)
  in
  let render (p : Infer_dist.posterior) =
    String.concat "; "
      (List.map (fun (v, pr) -> Printf.sprintf "%s %.17g" (Value.show v) pr) p.Infer_dist.entries)
  in
  let coin = "(app (var sample) (app (var bernoulli) (lit 0.5)))" in
  let enumerate ctx store =
    match Infer_dist.enumerate ctx (state store coin ()) with
    | Ok p -> render p
    | Error ds -> Eval_support.fail_diags "enumerate" ds
  in
  Alcotest.(check string)
    "enumerate under the grant explores both paths" "false 0.5; true 0.5"
    (enumerate granted granted_store);
  Alcotest.(check string)
    "enumerate is unchanged by the grant" (enumerate plain plain_store)
    (enumerate granted granted_store);
  let observed =
    "(let nonrec (pvar c) (app (var sample) (app (var bernoulli) (lit 0.5))) (let nonrec (pwild) \
     (app (var observe) (app (var bernoulli) (match (var c) (clause (pcon true) (lit 0.9)) (clause \
     (pcon false) (lit 0.1)))) (var true)) (var c)))"
  in
  let lw ctx store seed =
    match Infer_dist.likelihood_weighting ctx ~seed ~samples:50 (state store observed) with
    | Ok p -> render p
    | Error ds -> Eval_support.fail_diags "likelihood weighting" ds
  in
  Alcotest.(check string)
    "likelihood weighting is unchanged by the grant" (lw plain plain_store 42)
    (lw granted granted_store 42);
  Alcotest.(check bool)
    "the driver's seed decides" false
    (String.equal (lw granted granted_store 42) (lw granted granted_store 7));
  let nested =
    "(app (var dist.sample-lw) (lam () (let nonrec (pvar i) (app (var dist.sample-lw) (lam () (app \
     (var sample) (app (var uniform-int) (lit 1) (lit 6)))) (lit 3) (lit 7)) (tuple (var i) (app \
     (var sample) (app (var bernoulli) (lit 0.5)))))) (lit 4) (lit 42))"
  in
  let run ctx store =
    match Eval_support.eval_with ctx store nested with
    | Ok v -> Value.show v
    | Error e -> Alcotest.failf "nested drivers failed: %s" (Runtime_err.to_string e)
  in
  Alcotest.(check string)
    "nested drivers are unchanged by the grant" (run plain plain_store) (run granted granted_store);
  (* outside a driver the grant still answers: a root draw is a seeded sample *)
  match Eval_support.eval_with granted granted_store coin with
  | Ok v when List.mem (Value.show v) [ "true"; "false" ] -> ()
  | r ->
      Alcotest.failf "a root draw must still reach the grant, got %s"
        (match r with Ok v -> Value.show v | Error e -> Runtime_err.to_string e)

let test_lw_uniform_int () =
  (* LW over a uniform-int model stays in bounds and roughly uniform *)
  let state () =
    match
      Reader.parse_one ~file:"lw.jqd" "(app (var sample) (app (var uniform-int) (lit 1) (lit 3)))"
    with
    | Error ds -> Eval_support.fail_diags "parse" ds
    | Ok f -> (
        match
          Result.bind (Kernel.expr_of_form f) (Resolve.resolve_expr (Store.names_view store))
        with
        | Error ds -> Eval_support.fail_diags "resolve" ds
        | Ok e -> Eval.expr_state e)
  in
  match Infer_dist.likelihood_weighting ctx ~seed:11 ~samples:3000 state with
  | Error ds -> Eval_support.fail_diags "lw" ds
  | Ok p ->
      List.iter
        (fun (v, pr) ->
          Alcotest.(check bool)
            (Printf.sprintf "P(%s)=%.3f near 1/3" (Value.show v) pr)
            true
            (Float.abs (pr -. (1. /. 3.)) < 0.05))
        p.Infer_dist.entries;
      Alcotest.(check int) "three outcomes" 3 (List.length p.Infer_dist.entries)

(* the LW builtin: seeded and count-bounded; the thunk's dist row is discharged *)
let test_sample_lw_builtin () =
  let out seed =
    show
      (Printf.sprintf
         "(app (var dist.sample-lw) (lam () (app (var sample) (app (var uniform-int) (lit 1) (lit \
          3)))) (lit 2000) (lit %d))"
         seed)
  in
  Alcotest.(check string) "seeded determinism" (out 11) (out 11);
  (match
     Eval_support.eval_with ctx store "(app (var dist.sample-lw) (lam () (lit 1)) (lit 0) (lit 1))"
   with
  | Error (Runtime_err.Arithmetic _) -> ()
  | r ->
      Alcotest.failf "non-positive count must fail, got %s"
        (match r with Ok v -> Value.show v | Error e -> Runtime_err.to_string e));
  (* observed model: conditioning works through the builtin *)
  let posterior =
    eval_ok
      "(app (var dist.sample-lw) (lam () (let nonrec (pvar c) (app (var sample) (app (var \
       bernoulli) (lit 0.5))) (let nonrec (pwild) (app (var observe) (app (var bernoulli) (match \
       (var c) (clause (pcon true) (lit 0.9)) (clause (pcon false) (lit 0.1)))) (var true)) (var \
       c)))) (lit 4000) (lit 3))"
  in
  let rec find = function
    | Value.VCon
        {
          name = "cons";
          args = [ Value.VCon { name = "mk-pair"; args = [ v; Value.VReal p ]; _ }; rest ];
          _;
        } ->
        if Value.show v = "true" then Some p else find rest
    | _ -> None
  in
  match find posterior with
  | Some p ->
      Alcotest.(check bool)
        (Printf.sprintf "P(true)=%.3f near 0.9" p)
        true
        (Float.abs (p -. 0.9) < 0.05)
  | None -> Alcotest.fail "posterior missing true"

(* The runtime backstop for paths the checker never saw (moved from native-effects.t, whose
   program the checker now refuses with E0838): a model operation that only an outer handler
   could handle stops the driver with E0902, and a model that opens async.scope stops it with
   E0922, since no driver has a scheduler. *)
let test_sample_lw_unchecked_backstop () =
  let failure src =
    match Eval_support.eval_with ctx store src with
    | Error (Runtime_err.Diagnostic d) -> (Diag.code d, Diag.to_cause_string d)
    | Error e -> Alcotest.failf "expected a driver diagnostic, got %s" (Runtime_err.to_string e)
    | Ok v -> Alcotest.failf "expected a driver failure, got %s" (Value.show v)
  in
  let contains needle text =
    let n = String.length needle in
    let rec go i = i + n <= String.length text && (String.sub text i n = needle || go (i + 1)) in
    go 0
  in
  let code, cause =
    failure
      "(handle (app (var dist.sample-lw) (lam () (app (var emit) (lit 1))) (lit 3) (lit 42)) (ret \
       (pvar x) (var x)) (opclause emit ((pvar v)) k (app (var k) (tuple))))"
  in
  Alcotest.(check (option string)) "an outer-handled model operation is E0902" (Some "E0902") code;
  Alcotest.(check bool)
    "naming the pseudo-effect and the operation" true
    (contains "not handled during inference" cause && contains "`emit`" cause);
  let code, _ =
    failure
      "(app (var dist.sample-lw) (lam () (app (var async.scope) (lam () (lit 1)))) (lit 2) (lit 1))"
  in
  Alcotest.(check (option string)) "a scope in a model is E0922" (Some "E0922") code

let suite =
  [
    Alcotest.test_case "uniform-int support and pmf" `Quick test_uniform_int_support_pmf;
    Alcotest.test_case "dist.pmf agrees with the native pmf" `Quick test_dist_pmf_agrees_with_native;
    Alcotest.test_case "enumerate+tally equals the native posterior" `Quick
      test_enumerate_tally_vs_native;
    Alcotest.test_case "enumerate is normalized but unmerged" `Quick test_enumerate_unmerged;
    Alcotest.test_case "sampling bounds and determinism" `Quick test_sampling_bounds_and_determinism;
    Alcotest.test_case "root sampling handler; observe is a defect" `Quick
      test_root_sampling_handler;
    Alcotest.test_case "inference drivers own Dist under a root grant" `Quick
      test_driver_owns_dist_under_grant;
    Alcotest.test_case "likelihood weighting over uniform-int" `Quick test_lw_uniform_int;
    Alcotest.test_case "dist.sample-lw builtin" `Quick test_sample_lw_builtin;
    Alcotest.test_case "dist.sample-lw unchecked backstop (E0902, E0922)" `Quick
      test_sample_lw_unchecked_backstop;
  ]
