open Jacquard

(* INF.1: typed inference outcomes. The prelude's dist.enumerate-v1 and dist.sample-lw-v1 and the
   CLI's Infer_dist drivers share one classification: posterior, impossible, exhausted, or a
   numerical failure (underflow, non-finite, negative mass), with run metadata. *)

let store, ctx = Eval_support.make_prelude_ctx ()

let eval_ok src =
  match Eval_support.eval_with ctx store src with
  | Ok v -> v
  | Error e -> Alcotest.failf "eval failed on %s: %s" src (Runtime_err.to_string e)

(* model bodies, as bootstrap expressions over sample/observe *)
let coin_observed =
  "(let nonrec (pvar c) (app (var sample) (app (var bernoulli) (lit 0.5)))\n\
  \  (let nonrec (pwild) (app (var observe) (app (var bernoulli) (lit 0.7)) (var c)) (var c)))"

let two_coins =
  "(let nonrec (pvar a) (app (var sample) (app (var bernoulli) (lit 0.5)))\n\
  \  (let nonrec (pvar b) (app (var sample) (app (var bernoulli) (lit 0.5)))\n\
  \    (match (var a) (clause (pcon true) (var b)) (clause (pcon false) (var false)))))"

let impossible =
  "(let nonrec (pwild) (app (var observe) (app (var bernoulli) (lit 0.0)) (var true)) (lit 1))"

(* every support weight is zero: each branch has an exact zero factor *)
let all_zero =
  "(app (var sample) (app (var categorical)\n\
  \  (app (var cons) (app (var mk-pair) (lit 1) (lit 0.0))\n\
  \    (app (var cons) (app (var mk-pair) (lit 2) (lit 0.0)) (var nil)))))"

(* positive observation factors whose product underflows: 1e-200 * 1e-200 = 0 in binary64 (both
   drivers multiply observations; only enumeration also multiplies sample weights) *)
let underflow =
  let observe =
    "(app (var observe) (app (var categorical) (app (var cons) (app (var mk-pair) (lit 1) (lit \
     1e-200)) (var nil))) (lit 1))"
  in
  Printf.sprintf "(let nonrec (pwild) %s (let nonrec (pwild) %s (lit 1)))" observe observe

let weight_model w =
  Printf.sprintf
    "(app (var sample) (app (var categorical)\n\
    \  (app (var cons) (app (var mk-pair) (lit 1) %s)\n\
    \    (app (var cons) (app (var mk-pair) (lit 2) (lit 0.5)) (var nil)))))"
    w

let overflow = weight_model "(app (var real.mul) (lit 1e308) (lit 10.0))"

let not_a_number =
  weight_model
    "(app (var real.sub) (app (var real.mul) (lit 1e308) (lit 10.0)) (app (var real.mul) (lit \
     1e308) (lit 10.0)))"

let negative = weight_model "(lit -0.5)"

(* the same weights observed rather than drawn: an observation is not a draw, so its factor (from
   the raw pmf) reaches the shared classification as a non-finite or negative leaf *)
let observed w =
  Printf.sprintf
    "(let nonrec (pwild) (app (var observe) (app (var categorical) (app (var cons) (app (var \
     mk-pair) (lit 1) %s) (var nil))) (lit 1)) (lit 1))"
    w

let observed_overflow = observed "(app (var real.mul) (lit 1e308) (lit 10.0))"

let observed_nan =
  observed
    "(app (var real.sub) (app (var real.mul) (lit 1e308) (lit 10.0)) (app (var real.mul) (lit \
     1e308) (lit 10.0)))"

let observed_negative = observed "(lit -0.5)"

(* two finite leaves whose total overflows: a fair draw, then an observation weighing 1e308 *)
let observed_total_overflow =
  "(let nonrec (pvar x) (app (var sample) (app (var categorical)\n\
  \  (app (var cons) (app (var mk-pair) (lit 1) (lit 1.0))\n\
  \    (app (var cons) (app (var mk-pair) (lit 2) (lit 1.0)) (var nil)))))\n\
  \  (let nonrec (pwild) (app (var observe) (app (var categorical)\n\
  \    (app (var cons) (app (var mk-pair) (var x) (lit 1e308)) (var nil))) (var x)) (var x)))"

(* two finite weights whose sum overflows *)
let total_overflow =
  "(app (var sample) (app (var categorical)\n\
  \  (app (var cons) (app (var mk-pair) (lit 1) (lit 1e308))\n\
  \    (app (var cons) (app (var mk-pair) (lit 2) (lit 1e308)) (var nil)))))"

(* factors whose product is representable only when multiplied in model order: 1e-200 * 3e-124 *
   0.6 is a subnormal, while 0.6 * 3e-124 * 1e-200 rounds to zero *)
let order_sensitive =
  "(let nonrec (pwild) (app (var observe) (app (var bernoulli) (lit 1e-200)) (var true))\n\
  \  (let nonrec (pwild) (app (var observe) (app (var bernoulli) (lit 3e-124)) (var true))\n\
  \    (let nonrec (pwild) (app (var observe) (app (var bernoulli) (lit 0.6)) (var true)) (lit \
   1))))"

let enumerate_v1 ?(budget = 100) body =
  eval_ok (Printf.sprintf "(app (var dist.enumerate-v1) (lam () %s) (lit %d))" body budget)

let lw_v1 ?(samples = 200) ?(seed = 7) body =
  eval_ok
    (Printf.sprintf "(app (var dist.sample-lw-v1) (lam () %s) (lit %d) (lit %d))" body samples seed)

let thunk body = eval_ok (Printf.sprintf "(lam () %s)" body)

(* the library outcome's classification tag and metadata *)
let tag (v : Value.t) =
  match v with
  | VCon { name = "ok"; args = [ VCon { name = "inference-posterior-v1"; _ } ]; _ } -> "posterior"
  | VCon { name = "err"; args = [ VCon { name = "inference-impossible-v1"; _ } ]; _ } ->
      "impossible"
  | VCon { name = "err"; args = [ VCon { name = "inference-exhausted-v1"; _ } ]; _ } -> "exhausted"
  | VCon
      {
        name = "err";
        args = [ VCon { name = "inference-numeric-failure-v1"; args = [ VCon { name; _ }; _ ]; _ } ];
        _;
      } -> (
      match name with
      | "inference-underflow-v1" -> "underflow"
      | "inference-non-finite-v1" -> "non-finite"
      | "inference-negative-mass-v1" -> "negative-mass"
      | other -> Alcotest.failf "unknown numeric reason %s" other)
  | v -> Alcotest.failf "not an inference outcome: %s" (Value.show v)

let metadata (v : Value.t) =
  let rec find = function
    | Value.VCon { name = "inference-metadata-v1"; args; _ } -> Some args
    | VCon { args; _ } -> List.find_map find args
    | _ -> None
  in
  match find v with
  | Some [ VCon { name = meth; _ }; VCon { name = complete; _ }; seed; VInt bound; VInt explored ]
    ->
      (meth, complete = "true", Value.show seed, bound, explored)
  | _ -> Alcotest.failf "no metadata in %s" (Value.show v)

let entries (v : Value.t) =
  match v with
  | VCon { name = "ok"; args = [ VCon { args = [ list; _ ]; _ } ]; _ } ->
      let rec go = function
        | Value.VCon { name = "cons"; args = [ VCon { args = [ x; VReal p ]; _ }; rest ]; _ } ->
            (Value.show x, p) :: go rest
        | _ -> []
      in
      go list
  | v -> Alcotest.failf "not a posterior: %s" (Value.show v)

(* merge by rendering, as the CLI does *)
let merged es =
  let tbl = Hashtbl.create 8 in
  List.iter
    (fun (k, p) -> Hashtbl.replace tbl k (p +. Option.value ~default:0.0 (Hashtbl.find_opt tbl k)))
    es;
  Hashtbl.fold (fun k p acc -> (k, p) :: acc) tbl [] |> List.sort compare

let close a b = Float.abs (a -. b) < 1e-12

let cli_tag (c : Infer_dist.classified) =
  match c.result with
  | Ok _ -> "posterior"
  | Error Infer_dist.Impossible -> "impossible"
  | Error Exhausted -> "exhausted"
  | Error (Numeric Underflow) -> "underflow"
  | Error (Numeric Non_finite) -> "non-finite"
  | Error (Numeric Negative_mass) -> "negative-mass"
  | Error (Invalid_draw Negative_mass) -> "refused negative-mass"
  | Error (Invalid_draw (Non_finite | Underflow)) -> "refused non-finite"

let cli_enumerate ?max_branches body =
  match Infer_dist.enumerate_v1 ?max_branches ctx (Eval.apply_state ctx (thunk body) []) with
  | Ok c -> c
  | Error ds -> Alcotest.failf "driver failed: %s" (Diag.to_cause_string (List.hd ds))

let cli_lw ~samples ~seed body =
  match
    Infer_dist.likelihood_weighting_v1 ctx ~seed ~samples (fun () ->
        Eval.apply_state ctx (thunk body) [])
  with
  | Ok c -> c
  | Error ds -> Alcotest.failf "driver failed: %s" (Diag.to_cause_string (List.hd ds))

let cli_code (c : Infer_dist.classified) ~sampled =
  match Infer_dist.classified_to_result ~sampled c with
  | Ok _ -> "ok"
  | Error [ d ] -> Option.value ~default:"" (Diag.code d)
  | Error _ -> "several"

let test_normalized_posterior () =
  let v = enumerate_v1 coin_observed in
  Alcotest.(check string) "classified" "posterior" (tag v);
  let es = entries v in
  Alcotest.(check bool)
    "sums to one" true
    (close 1.0 (List.fold_left (fun a (_, p) -> a +. p) 0. es));
  Alcotest.(check bool)
    "true is 0.7" true
    (close 0.7 (List.assoc "true" es) && close 0.3 (List.assoc "false" es));
  let meth, complete, seed, bound, explored = metadata v in
  Alcotest.(check string) "method" "inference-exact-enumeration-v1" meth;
  Alcotest.(check bool) "complete" true complete;
  Alcotest.(check string) "no seed" "none" seed;
  Alcotest.(check (pair int int)) "bound and explored" (100, 2) (bound, explored)

let test_impossible_evidence () =
  List.iter
    (fun (label, body) ->
      Alcotest.(check string) (label ^ ": library") "impossible" (tag (enumerate_v1 body));
      let c = cli_enumerate body in
      Alcotest.(check string) (label ^ ": driver") "impossible" (cli_tag c);
      Alcotest.(check string) (label ^ ": CLI code") "E0901" (cli_code c ~sampled:false);
      Alcotest.(check string) (label ^ ": sampled") "impossible" (tag (lw_v1 body));
      Alcotest.(check string)
        (label ^ ": sampled CLI code") "E0901"
        (cli_code (cli_lw ~samples:50 ~seed:3 body) ~sampled:true))
    [ ("observation", impossible); ("all-zero support", all_zero) ]

let test_underflow_is_not_impossible () =
  Alcotest.(check string) "library" "underflow" (tag (enumerate_v1 underflow));
  let c = cli_enumerate underflow in
  Alcotest.(check string) "driver" "underflow" (cli_tag c);
  Alcotest.(check string) "CLI code" "E0917" (cli_code c ~sampled:false);
  Alcotest.(check string) "sampled" "underflow" (tag (lw_v1 underflow));
  (* the legacy CLI path pruned underflowed paths and called this impossible *)
  Alcotest.(check bool)
    "complete" true
    (let _, complete, _, _, _ = metadata (enumerate_v1 underflow) in
     complete)

let test_numeric_failures () =
  List.iter
    (fun (label, body, expected) ->
      Alcotest.(check string) (label ^ ": library") expected (tag (enumerate_v1 body));
      let c = cli_enumerate body in
      Alcotest.(check string) (label ^ ": driver") expected (cli_tag c);
      Alcotest.(check string) (label ^ ": CLI code") "E0917" (cli_code c ~sampled:false))
    [
      ("infinite weight", observed_overflow, "non-finite");
      ("NaN weight", observed_nan, "non-finite");
      ("negative weight", observed_negative, "negative-mass");
      ("overflowing total", observed_total_overflow, "non-finite");
    ]

let test_bounded_exploration () =
  (* two coins: four terminal paths *)
  let within = enumerate_v1 ~budget:4 two_coins in
  Alcotest.(check string) "exactly the budget" "posterior" (tag within);
  let _, complete, _, bound, explored = metadata within in
  Alcotest.(check (triple bool int int))
    "complete at the budget" (true, 4, 4) (complete, bound, explored);
  let over = enumerate_v1 ~budget:3 two_coins in
  Alcotest.(check string) "one path too many" "exhausted" (tag over);
  let _, complete, _, bound, explored = metadata over in
  Alcotest.(check (triple bool int int)) "incomplete" (false, 3, 3) (complete, bound, explored);
  Alcotest.(check string) "zero budget" "exhausted" (tag (enumerate_v1 ~budget:0 two_coins));
  (* a non-positive budget is exhausted before the model runs: no runtime failure, no outcome *)
  let failing = "(app (var div) (lit 1) (lit 0))" in
  List.iter
    (fun budget ->
      let v = enumerate_v1 ~budget failing in
      Alcotest.(check string) (Printf.sprintf "budget %d: exhausted" budget) "exhausted" (tag v);
      let _, complete, _, _, explored = metadata v in
      Alcotest.(check (pair bool int)) "nothing explored" (false, 0) (complete, explored))
    [ 0; -3 ];
  Alcotest.(check string)
    "driver, zero budget" "exhausted"
    (cli_tag (cli_enumerate ~max_branches:0 failing));
  let c = cli_enumerate ~max_branches:3 two_coins in
  Alcotest.(check string) "driver" "exhausted" (cli_tag c);
  Alcotest.(check string) "CLI code" "E0918" (cli_code c ~sampled:false);
  Alcotest.(check (pair bool int))
    "driver metadata" (false, 3)
    (c.metadata.complete, c.metadata.explored);
  (* a pruned (zero-factor) path spends budget too *)
  Alcotest.(check string) "pruned paths count" "exhausted" (tag (enumerate_v1 ~budget:1 all_zero))

let test_seeded_sampling () =
  let a = lw_v1 ~samples:300 ~seed:11 coin_observed in
  let b = lw_v1 ~samples:300 ~seed:11 coin_observed in
  Alcotest.(check string) "same seed, same outcome" (Value.show a) (Value.show b);
  Alcotest.(check bool)
    "another seed differs" true
    (Value.show a <> Value.show (lw_v1 ~samples:300 ~seed:12 coin_observed));
  let meth, complete, seed, bound, explored = metadata a in
  Alcotest.(check string) "method" "inference-likelihood-weighting-v1" meth;
  Alcotest.(check bool) "sampling is never complete" false complete;
  Alcotest.(check string) "seed" "some(11)" seed;
  Alcotest.(check (pair int int)) "bound and runs" (300, 300) (bound, explored);
  (* the posterior agrees with the released dist.sample-lw on the same stream *)
  let legacy =
    match
      eval_ok
        (Printf.sprintf "(app (var dist.sample-lw) (lam () %s) (lit 300) (lit 11))" coin_observed)
    with
    | v ->
        let rec go = function
          | Value.VCon { name = "cons"; args = [ VCon { args = [ x; VReal p ]; _ }; rest ]; _ } ->
              (Value.show x, p) :: go rest
          | _ -> []
        in
        List.sort compare (go v)
  in
  List.iter2
    (fun (k1, p1) (k2, p2) ->
      Alcotest.(check string) "value" k1 k2;
      Alcotest.(check bool) (Printf.sprintf "%s: %g vs %g" k1 p1 p2) true (close p1 p2))
    legacy
    (merged (entries a));
  (* impossible runs are dropped, not weighted zero *)
  let half_impossible =
    "(let nonrec (pvar c) (app (var sample) (app (var bernoulli) (lit 0.5)))\n\
    \  (let nonrec (pwild) (app (var observe) (app (var bernoulli) (lit 1.0)) (var c)) (var c)))"
  in
  let v = lw_v1 ~samples:100 ~seed:5 half_impossible in
  Alcotest.(check bool)
    "only possible runs remain" true
    (List.for_all (fun (x, _) -> x = "true") (entries v))

(* the library and the CLI driver classify every model alike and agree on the posterior *)
let test_library_cli_agreement () =
  List.iter
    (fun (label, body) ->
      let lib = enumerate_v1 body in
      let c = cli_enumerate body in
      Alcotest.(check string) (label ^ ": enumeration") (tag lib) (cli_tag c);
      (match c.result with
      | Ok p ->
          let cli = List.sort compare (List.map (fun (v, p) -> (Value.show v, p)) p.entries) in
          List.iter2
            (fun (k1, p1) (k2, p2) ->
              Alcotest.(check string) (label ^ ": value") k1 k2;
              Alcotest.(check bool) (label ^ ": probability") true (close p1 p2))
            (merged (entries lib))
            cli
      | Error _ -> ());
      let lib = lw_v1 ~samples:64 ~seed:9 body in
      let c = cli_lw ~samples:64 ~seed:9 body in
      Alcotest.(check string) (label ^ ": sampling") (tag lib) (cli_tag c))
    [
      ("observed coin", coin_observed);
      ("two coins", two_coins);
      ("impossible", impossible);
      ("all zero", all_zero);
      ("underflow", underflow);
      ("overflow", observed_overflow);
      ("NaN", observed_nan);
      ("negative", observed_negative);
      ("overflowing total", observed_total_overflow);
      ("factor order", order_sensitive);
    ];
  (* both multiply path factors in model order, so both find the subnormal posterior *)
  Alcotest.(check string) "order-sensitive product" "posterior" (tag (enumerate_v1 order_sensitive))

(* a draw from invalid categorical weights is refused at the draw with E0917 by every enumeration
   and likelihood-weighting driver alike, whatever the run observes afterwards and whichever weight
   comes first; the released dist.sample-lw fails with E0902; a zero-mass draw weighs its legacy run
   zero *)
let neg_nan = "(app (var real.div) (lit 0.0) (lit 0.0))"

let pair_model a b =
  Printf.sprintf
    "(app (var sample) (app (var categorical)\n\
    \  (app (var cons) (app (var mk-pair) (lit 1) %s)\n\
    \    (app (var cons) (app (var mk-pair) (lit 2) %s) (var nil)))))"
    a b

let triple_model a b c =
  Printf.sprintf
    "(app (var sample) (app (var categorical)\n\
    \  (app (var cons) (app (var mk-pair) (lit 1) %s)\n\
    \    (app (var cons) (app (var mk-pair) (lit 2) %s)\n\
    \      (app (var cons) (app (var mk-pair) (lit 3) %s) (var nil))))))"
    a b c

(* an observation of the valid entry after the draw: enumeration would prune the negative branch
   and sampling would follow whichever entry it drew *)
let observe_after first second =
  Printf.sprintf
    "(let nonrec (pvar x) (app (var sample) (app (var categorical)\n\
    \  (app (var cons) (app (var mk-pair) (lit \"%s\") %s)\n\
    \    (app (var cons) (app (var mk-pair) (lit \"%s\") %s) (var nil)))))\n\
    \  (let nonrec (pwild) (app (var observe) (app (var categorical) (app (var cons) (app (var \
     mk-pair) (lit \"b\") (lit 1.0)) (var nil))) (var x)) (var x)))"
    (fst first) (snd first) (fst second) (snd second)

(* a continuation that fails on one entry *)
let divides first second =
  Printf.sprintf "(app (var int.div) (lit 10) %s)"
    (Printf.sprintf
       "(app (var sample) (app (var categorical) (app (var cons) (app (var mk-pair) (lit %d) %s) \
        (app (var cons) (app (var mk-pair) (lit %d) %s) (var nil)))))"
       (fst first) (snd first) (fst second) (snd second))

(* two single-entry negative sites: their path weight is +1 *)
let two_negative_sites =
  let site =
    "(app (var sample) (app (var categorical) (app (var cons) (app (var mk-pair) (lit 1) (lit \
     -1.0)) (var nil))))"
  in
  Printf.sprintf "(let nonrec (pvar a) %s (let nonrec (pvar b) %s (var a)))" site site

let refusal_models =
  [
    ("infinite weight", overflow, "non-finite");
    ("NaN weight", not_a_number, "non-finite");
    ("negative weight", negative, "negative-mass");
    ("overflowing total", total_overflow, "non-finite");
    ("negative then NaN", pair_model "(lit -1.0)" neg_nan, "non-finite");
    ("NaN then negative", pair_model neg_nan "(lit -1.0)", "non-finite");
    ("two huge negatives", pair_model "(lit -1e308)" "(lit -1e308)", "negative-mass");
    ( "overflow then negative",
      triple_model "(lit 1e308)" "(lit 1e308)" "(lit -1.0)",
      "negative-mass" );
    ( "negative then overflow",
      triple_model "(lit -1.0)" "(lit 1e308)" "(lit 1e308)",
      "negative-mass" );
    ( "observed after, negative first",
      observe_after ("a", "(lit -1.0)") ("b", "(lit 2.0)"),
      "negative-mass" );
    ( "observed after, negative second",
      observe_after ("b", "(lit 2.0)") ("a", "(lit -1.0)"),
      "negative-mass" );
    ("divides, negative first", divides (1, "(lit -1.0)") (0, "(lit 2.0)"), "negative-mass");
    ("divides, negative second", divides (0, "(lit 2.0)") (1, "(lit -1.0)"), "negative-mass");
    ("two single-entry negative sites", two_negative_sites, "negative-mass");
  ]

let refusal_text = function
  | "negative-mass" -> Infer_dist.refusal_cause Negative_mass
  | _ -> Infer_dist.refusal_cause Non_finite

let test_refused_draws () =
  List.iter
    (fun (label, body, expected) ->
      (* the in-language drivers stop with the same coded diagnostic *)
      List.iter
        (fun (driver, call) ->
          match Eval_support.eval_with ctx store (Printf.sprintf call body) with
          | Ok v -> Alcotest.failf "%s: %s returned %s" label driver (Value.show v)
          | Error e ->
              let d = Runtime_err.to_diag e in
              Alcotest.(check string)
                (label ^ ": " ^ driver ^ " code")
                "E0917" (Diag.code_or_uncoded d);
              Alcotest.(check string)
                (label ^ ": " ^ driver ^ " cause")
                (refusal_text expected) (Diag.cause d))
        [
          ("dist.enumerate-v1", "(app (var dist.enumerate-v1) (lam () %s) (lit 100))");
          ("dist.enumerate", "(app (var dist.enumerate) (lam () %s))");
          ("dist.sample-lw-v1", "(app (var dist.sample-lw-v1) (lam () %s) (lit 20) (lit 3))");
          ( "dist.sample-lw-weights-v1",
            "(app (var dist.sample-lw-weights-v1) (lam () %s) (lit 20) (lit 3))" );
        ];
      (* the CLI drivers and model documents see a typed refusal *)
      let e = cli_enumerate body and l = cli_lw ~samples:20 ~seed:3 body in
      Alcotest.(check string) (label ^ ": enumeration") ("refused " ^ expected) (cli_tag e);
      Alcotest.(check string) (label ^ ": sampling") ("refused " ^ expected) (cli_tag l);
      Alcotest.(check string) (label ^ ": CLI code") "E0917" (cli_code e ~sampled:false);
      Alcotest.(check string) (label ^ ": sampled CLI code") "E0917" (cli_code l ~sampled:true);
      Alcotest.(check bool) (label ^ ": incomplete") false e.metadata.complete;
      (* the released driver has no numeric channel: a runtime failure *)
      match
        Eval_support.eval_with ctx store
          (Printf.sprintf "(app (var dist.sample-lw) (lam () %s) (lit 5) (lit 1))" body)
      with
      | Ok v -> Alcotest.failf "%s: legacy sampling returned %s" label (Value.show v)
      | Error e ->
          Alcotest.(check string)
            (label ^ ": legacy code") "E0902"
            (Diag.code_or_uncoded (Runtime_err.to_diag e)))
    refusal_models;
  (* a site behind an exact zero factor is never reached by enumeration, so a run that is already
     impossible draws from it and carries on: both drivers agree, alone and beside a valid branch *)
  let dead =
    "(let nonrec (pwild) (app (var observe) (app (var categorical) (app (var cons) (app (var \
     mk-pair) (lit \"b\") (lit 1.0)) (var nil))) (lit \"a\"))\n\
    \  (app (var sample) (app (var categorical) (app (var cons) (app (var mk-pair) (lit \"a\") \
     (lit -1.0)) (var nil)))))"
  in
  let coin_or_dead =
    Printf.sprintf
      "(match (app (var sample) (app (var bernoulli) (lit 0.5))) (clause (pcon true) %s) (clause \
       (pcon false) (lit \"ok\")))"
      dead
  in
  List.iter
    (fun (label, body, expected) ->
      Alcotest.(check string) (label ^ ": enumeration") expected (tag (enumerate_v1 body));
      Alcotest.(check string) (label ^ ": sampling") expected (tag (lw_v1 ~samples:20 body));
      Alcotest.(check string) (label ^ ": CLI enumeration") expected (cli_tag (cli_enumerate body));
      Alcotest.(check string)
        (label ^ ": CLI sampling") expected
        (cli_tag (cli_lw ~samples:20 ~seed:3 body)))
    [ ("dead run", dead, "impossible"); ("coin or dead run", coin_or_dead, "posterior") ];
  (* a legacy zero-mass run weighs zero: alone it is E0901, beside a possible run it is a zero row *)
  (match
     Eval_support.eval_with ctx store
       (Printf.sprintf "(app (var dist.sample-lw) (lam () %s) (lit 5) (lit 1))" all_zero)
   with
  | Ok v -> Alcotest.failf "legacy zero mass returned %s" (Value.show v)
  | Error e ->
      Alcotest.(check string)
        "legacy zero mass" "E0901"
        (Diag.code_or_uncoded (Runtime_err.to_diag e)));
  let mixed =
    Printf.sprintf
      "(match (app (var sample) (app (var bernoulli) (lit 0.5))) (clause (pcon true) (lit 0)) \
       (clause (pcon false) %s))"
      all_zero
  in
  match
    eval_ok (Printf.sprintf "(app (var dist.sample-lw) (lam () %s) (lit 40) (lit 1))" mixed)
  with
  | v ->
      let rec go = function
        | Value.VCon { name = "cons"; args = [ VCon { args = [ x; VReal p ]; _ }; rest ]; _ } ->
            (Value.show x, p) :: go rest
        | _ -> []
      in
      let rows = go v in
      Alcotest.(check (list (pair string (float 0.0))))
        "legacy zero-mass rows weigh zero"
        [ ("0", 1.0); ("2", 0.0) ]
        rows

(* the refusal reason ranks the weights, never their order: non-finite, then negative, then an
   overflowing sum *)
let test_invalid_weights_rank () =
  let e ws = List.mapi (fun i w -> (Value.VInt i, w)) ws in
  let show = function
    | None -> "none"
    | Some Infer_dist.Negative_mass -> "negative"
    | Some Non_finite -> "non-finite"
    | Some Underflow -> "underflow"
  in
  let check label expected ws =
    Alcotest.(check string) label expected (show (Infer_dist.invalid_weights (e ws)))
  in
  check "drawable" "none" [ 0.0; 1.0 ];
  check "zero mass is not refused" "none" [ 0.0; -0.0 ];
  check "NaN" "non-finite" [ Float.nan ];
  check "negative then NaN" "non-finite" [ -1.0; Float.nan ];
  check "infinity then negative" "non-finite" [ Float.infinity; -1.0 ];
  check "negative infinity" "non-finite" [ Float.neg_infinity ];
  check "two huge negatives" "negative" [ -1e308; -1e308 ];
  check "overflow then negative" "negative" [ 1e308; 1e308; -1.0 ];
  check "negative then overflow" "negative" [ -1.0; 1e308; 1e308 ];
  check "overflow only" "non-finite" [ 1e308; 1e308 ];
  (* the largest float plus two quarter-ulps overflows by exactly half an ulp: it stays finite when
     summed in some entry orders, but the ascending sum decides, so every order is refused *)
  let m = Float.max_float and q = Float.ldexp 1.0 969 in
  check "huge first" "non-finite" [ m; q; q ];
  check "huge last" "non-finite" [ q; q; m ];
  check "huge between" "non-finite" [ q; m; q ];
  (* the converse: an in-order sum that overflows where the ascending sum does not is drawable *)
  let below = Float.pred m and u = Float.ldexp 1.0 971 in
  check "ascending sum finite" "none" [ below; 0.6 *. u; 0.5 *. u ];
  (* a NaN renders the same whatever its sign *)
  Alcotest.(check (pair string string))
    "NaN text" ("nan", "nan")
    (Infer_dist.show_weight Float.nan, Infer_dist.show_weight (Float.neg Float.nan));
  Alcotest.(check string)
    "draw failure text" "categorical weight 0 is nan; a draw needs finite, nonnegative weights"
    (Infer_dist.draw_failure_message (Invalid_weight (0, Float.neg Float.nan)))

let prop_invalid_weights_ignore_order =
  let weight =
    QCheck.Gen.oneof_list
      [ 0.0; -0.0; 0.5; 2.0; 1e308; -1.0; -1e308; Float.nan; Float.infinity; Float.neg_infinity ]
  in
  (* finite, nonnegative weights whose sums land within an ulp or two of the largest float, where
     rounding can make one order overflow and another not *)
  let boundary =
    let m = Float.max_float and q = Float.ldexp 1.0 969 in
    QCheck.Gen.oneof_list [ 0.0; q; 2.0 *. q; m /. 2.0; Float.pred m; m ]
  in
  let weights = QCheck.Gen.(oneof [ list_size (1 -- 6) weight; list_size (1 -- 6) boundary ]) in
  (* check_weights names the first offender, whose index depends on the order; its kind does not *)
  let kind ws =
    match Infer_dist.check_weights ws with
    | Ok () -> "ok"
    | Error Infer_dist.No_mass -> "no-mass"
    | Error (Invalid_weight _) -> "invalid"
    | Error (Nonfinite_total _) -> "total"
  in
  QCheck.Test.make ~count:500 ~name:"invalid_weights is independent of entry order"
    QCheck.(make Gen.(pair weights int))
    (fun (weights, seed) ->
      let e ws = List.mapi (fun i w -> (Value.VInt i, w)) ws in
      let shuffled =
        let st = Random.State.make [| seed |] in
        List.map snd (List.sort compare (List.map (fun w -> (Random.State.bits st, w)) weights))
      in
      List.for_all
        (fun other ->
          Infer_dist.invalid_weights (e weights) = Infer_dist.invalid_weights (e other)
          && kind (e weights) = kind (e other))
        [ shuffled; List.rev weights ])

(* the validated draw keeps the stream: for drawable weights it is the unchecked draw, and it leaves
   the generator where the unchecked draw does *)
let prop_draw_checked_keeps_stream =
  QCheck.Test.make ~count:500 ~name:"draw_checked equals draw on drawable weights"
    QCheck.(pair int (list_size Gen.(1 -- 6) (float_range 0.0 10.0)))
    (fun (seed, weights) ->
      QCheck.assume (List.fold_left ( +. ) 0.0 weights > 0.0);
      let entries = List.mapi (fun i w -> (Value.VInt i, w)) weights in
      let a = Infer_dist.Rng.make seed and b = Infer_dist.Rng.make seed in
      match Infer_dist.draw_checked a entries with
      | Error _ -> false
      | Ok x ->
          let y = Infer_dist.draw b entries in
          Value.show x = Value.show y && Infer_dist.Rng.float a = Infer_dist.Rng.float b)

let test_check_weights_order () =
  let e ws = List.mapi (fun i w -> (Value.VInt i, w)) ws in
  let show = function
    | Ok () -> "ok"
    | Error Infer_dist.No_mass -> "no-mass"
    | Error (Invalid_weight (i, w)) -> Printf.sprintf "invalid %d %g" i w
    | Error (Nonfinite_total t) -> Printf.sprintf "total %g" t
  in
  let check label expected ws =
    Alcotest.(check string) label expected (show (Infer_dist.check_weights (e ws)))
  in
  check "drawable" "ok" [ 0.0; 1.0 ];
  check "zero mass" "no-mass" [ 0.0; 0.0 ];
  check "the first bad weight" "invalid 1 -1" [ 0.0; -1.0; Float.infinity ];
  check "invalid before zero mass" "invalid 0 -0.5" [ -0.5; 0.0 ];
  check "a cancelling negative is invalid, not zero mass" "invalid 0 -1" [ -1.0; 1.0 ];
  check "an overflowing sum" "total inf" [ 1e308; 1e308 ];
  let m = Float.max_float and q = Float.ldexp 1.0 969 in
  check "an overflow by half an ulp, huge first" "total inf" [ m; q; q ];
  check "an overflow by half an ulp, huge last" "total inf" [ q; q; m ];
  let below = Float.pred m and u = Float.ldexp 1.0 971 in
  let near = [ below; 0.6 *. u; 0.5 *. u ] in
  check "an in-order overflow the ascending sum avoids" "ok" near;
  (* that draw uses the ascending total, so it never picks past the end on an infinite scale *)
  (match Infer_dist.draw_checked (Infer_dist.Rng.make 5) (e near) with
  | Ok (Value.VInt _) -> ()
  | Ok v -> Alcotest.failf "unexpected draw %s" (Value.show v)
  | Error _ -> Alcotest.fail "the ascending total is finite");
  (* no random draw on failure *)
  let a = Infer_dist.Rng.make 4 and b = Infer_dist.Rng.make 4 in
  ignore (Infer_dist.draw_checked a (e [ 0.0; 0.0 ]));
  Alcotest.(check (float 0.0))
    "failure leaves the stream" (Infer_dist.Rng.float b) (Infer_dist.Rng.float a);
  (* an empty Categorical is refused where it is recognised *)
  match
    Eval_support.eval_with ctx store "(app (var support) (app (var categorical) (var nil)))"
  with
  | Ok v -> Alcotest.failf "support of an empty categorical returned %s" (Value.show v)
  | Error e ->
      Alcotest.(check string)
        "empty categorical" "arithmetic error: categorical support is empty"
        (Runtime_err.to_string e)

(* the released identities keep their behaviour: dist.enumerate still yields NaN weights *)
(* every categorical draw scales its uniform by [Infer_dist.draw_total]: Warp's sampled lane picks
   the index the interpreter draw picks, from the same single uniform. Weights whose entry-order sum
   overflows while their ascending sum does not are drawn by their weights in every order: the heavy
   entry carries all but about 1e-16 of the mass, so it is picked at every seed *)
let test_shared_draw_total () =
  let index_of = function
    | Value.VInt i -> i
    | v -> Alcotest.failf "unexpected draw %s" (Value.show v)
  in
  let same_pick label entries =
    (* Warp picks a position; label the entries by position so the interpreter draw does too *)
    let entries = List.mapi (fun i (_, w) -> (Value.VInt i, w)) entries in
    List.iter
      (fun seed ->
        let a = Infer_dist.Rng.make seed and b = Infer_dist.Rng.make seed in
        let warp = Warp.fresh_index a (Infer_dist.Categorical entries) in
        let interp = index_of (Infer_dist.draw b entries) in
        Alcotest.(check int) (Printf.sprintf "%s, seed %d: same index" label seed) interp warp;
        Alcotest.(check (float 0.0))
          (Printf.sprintf "%s, seed %d: same stream" label seed)
          (Infer_dist.Rng.float b) (Infer_dist.Rng.float a))
      (List.init 20 (fun i -> i + 1))
  in
  let rec permutations = function
    | [] -> [ [] ]
    | xs ->
        List.concat_map
          (fun x -> List.map (fun p -> x :: p) (permutations (List.filter (( != ) x) xs)))
          xs
  in
  let heavy_always label heavy weights =
    List.iter
      (fun order ->
        let entries = List.map (fun (i, w) -> (Value.VInt i, w)) order in
        let label =
          Printf.sprintf "%s [%s]" label
            (String.concat "," (List.map (fun (i, _) -> string_of_int i) order))
        in
        Alcotest.(check bool)
          (label ^ " is drawable") true
          (Infer_dist.check_weights entries = Ok ());
        same_pick label entries;
        let rec position i = function
          | (l, _) :: rest -> if l = heavy then i else position (i + 1) rest
          | [] -> Alcotest.fail "no heavy entry"
        in
        List.iter
          (fun seed ->
            Alcotest.(check int)
              (Printf.sprintf "%s, seed %d: the heavy entry" label seed)
              (position 0 order)
              (Warp.fresh_index (Infer_dist.Rng.make seed) (Infer_dist.Categorical entries)))
          (List.init 20 (fun i -> i + 1)))
      (permutations weights)
  in
  (* pred(max) and 2^970 + 2^918, 2^970: in the order heavy, middle, light the entry-order sum
     overflows; the ascending sum is exactly the largest float *)
  let m = Float.max_float in
  let x = Float.ldexp 1.0 970 +. Float.ldexp 1.0 918 and y = Float.ldexp 1.0 970 in
  heavy_always "pred max" 0 [ (0, Float.pred m); (1, x); (2, y) ];
  (* max - 3 * 2^971 between two weights of 1.5 * 2^971: overflows in entry order y, heavy, y *)
  let b = m -. (3.0 *. Float.ldexp 1.0 971) and y = 1.5 *. Float.ldexp 1.0 971 in
  heavy_always "max - 3 ulp" 1 [ (0, y); (1, b); (2, y) ];
  same_pick "ordinary" [ (Value.VInt 0, 1.0); (Value.VInt 1, 3.0); (Value.VInt 2, 0.0) ]

(* the shared total over drawable weights, ordinary and near the largest float *)
let prop_warp_draw_shares_total =
  let boundary =
    let m = Float.max_float and q = Float.ldexp 1.0 969 and u = Float.ldexp 1.0 971 in
    QCheck.Gen.oneof_list [ 0.0; q; 2.0 *. q; 0.5 *. u; 1.5 *. u; m /. 2.0; Float.pred m; m ]
  in
  let weights =
    QCheck.Gen.(oneof [ list_size (1 -- 6) (float_range 0.0 10.0); list_size (1 -- 4) boundary ])
  in
  QCheck.Test.make ~count:500 ~name:"Warp's sampled draw picks the interpreter draw's index"
    QCheck.(make Gen.(pair int weights))
    (fun (seed, weights) ->
      let entries = List.mapi (fun i w -> (Value.VInt i, w)) weights in
      QCheck.assume (Infer_dist.check_weights entries = Ok ());
      let a = Infer_dist.Rng.make seed and b = Infer_dist.Rng.make seed in
      let warp = Warp.fresh_index a (Infer_dist.Categorical entries) in
      Value.show (Infer_dist.draw b entries) = Value.show (Value.VInt warp)
      && Infer_dist.Rng.float a = Infer_dist.Rng.float b)

let test_legacy_identities_unchanged () =
  match eval_ok (Printf.sprintf "(app (var dist.enumerate) (lam () %s))" impossible) with
  | VCon { name = "cons"; args = [ VCon { args = [ _; VReal p ]; _ }; _ ]; _ } ->
      Alcotest.(check bool) "NaN weight" true (Float.is_nan p)
  | v -> Alcotest.failf "unexpected legacy result %s" (Value.show v)

let suite =
  [
    Alcotest.test_case "a normalized posterior with metadata" `Quick test_normalized_posterior;
    Alcotest.test_case "impossible evidence" `Quick test_impossible_evidence;
    Alcotest.test_case "underflow is not impossibility" `Quick test_underflow_is_not_impossible;
    Alcotest.test_case "non-finite and negative mass" `Quick test_numeric_failures;
    Alcotest.test_case "bounded exploration" `Quick test_bounded_exploration;
    Alcotest.test_case "seeded sampling" `Quick test_seeded_sampling;
    Alcotest.test_case "library and CLI agree" `Quick test_library_cli_agreement;
    Alcotest.test_case "released identities unchanged" `Quick test_legacy_identities_unchanged;
    Alcotest.test_case "every driver refuses invalid categorical weights at the draw" `Quick
      test_refused_draws;
    Alcotest.test_case "categorical weight checks" `Quick test_check_weights_order;
    Alcotest.test_case "refusal reasons rank the weights" `Quick test_invalid_weights_rank;
    Alcotest.test_case "every categorical draw shares one total" `Quick test_shared_draw_total;
    QCheck_alcotest.to_alcotest prop_draw_checked_keeps_stream;
    QCheck_alcotest.to_alcotest prop_warp_draw_shares_total;
    QCheck_alcotest.to_alcotest prop_invalid_weights_ignore_order;
  ]
