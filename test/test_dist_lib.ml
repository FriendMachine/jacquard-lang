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

(* uniform-int ranges whose size overflows Int: every non-empty range draws inside its bounds, its
   pmf is 1/size, and enumeration refuses it with the exact size. Ranges that fit draw exactly as
   before. *)
let wide_ranges =
  [ (min_int, max_int); (-1, max_int); (min_int, 0); (min_int, -1); (-3, max_int - 3) ]

let test_uniform_wide_ranges () =
  List.iter
    (fun (lo, hi) ->
      Alcotest.(check bool)
        (Printf.sprintf "%d..%d does not fit" lo hi)
        false (Infer_dist.uniform_fits lo hi);
      let rng = Infer_dist.Rng.make 3 in
      let above_zero = ref 0 in
      for _ = 1 to 400 do
        match Infer_dist.sample_dist ctx rng (Infer_dist.UniformInt (lo, hi)) with
        | Ok (Value.VInt x) ->
            if x > lo + ((hi - lo) lsr 1) then incr above_zero;
            Alcotest.(check bool) (Printf.sprintf "%d in %d..%d" x lo hi) true (x >= lo && x <= hi)
        | Ok v -> Alcotest.failf "not an int: %s" (Value.show v)
        | Error e -> Alcotest.failf "sample failed: %s" (Runtime_err.to_string e)
      done;
      (* both halves of the range are drawn, not one wrapped end *)
      Alcotest.(check bool)
        (Printf.sprintf "%d..%d draws both halves (%d of 400 above the middle)" lo hi !above_zero)
        true
        (!above_zero > 100 && !above_zero < 300))
    wide_ranges;
  let pmf lo hi v =
    match Infer_dist.pmf ctx (Infer_dist.UniformInt (lo, hi)) (Value.VInt v) with
    | Ok p -> p
    | Error e -> Alcotest.failf "pmf failed: %s" (Runtime_err.to_string e)
  in
  Alcotest.(check (float 0.0)) "full range pmf" (ldexp 1.0 (-63)) (pmf min_int max_int 0);
  Alcotest.(check (float 0.0))
    "(-1, max-int) pmf"
    (1.0 /. (ldexp 1.0 62 +. 1.0))
    (pmf (-1) max_int 7);
  Alcotest.(check (float 0.0)) "off support" 0.0 (pmf 0 max_int (-1));
  Alcotest.(check (float 0.0)) "single max" 1.0 (pmf max_int max_int max_int);
  Alcotest.(check (float 0.0)) "single min" 1.0 (pmf min_int min_int min_int);
  Alcotest.(check (float 0.0))
    "large-magnitude narrow" (1.0 /. 6.0)
    (pmf (1 lsl 60) ((1 lsl 60) + 5) ((1 lsl 60) + 2));
  match Infer_dist.support ctx (Infer_dist.UniformInt (min_int, max_int)) with
  | Ok _ -> Alcotest.fail "the full range cannot be enumerated"
  | Error e ->
      Alcotest.(check string)
        "exact count in the cap message"
        "arithmetic error: uniform-int -4611686018427387904..4611686018427387903 has \
         9223372036854775808 outcomes; enumeration caps at 10000"
        (Runtime_err.to_string e)

(* a range above 2^32 values is drawn from the top 63 bits of each RNG output, rejecting bits at or
   above the largest multiple of its size that is at most 2^63: a reference model of that stream,
   checked against [sample_dist] draw for draw, with the number of rejections it saw *)
let test_uniform_exact_draws () =
  let two63_minus_1 = Int64.max_int in
  let offset count r = Infer_dist.uniform_bits_offset count r in
  let full = Infer_dist.uniform_bits_count min_int max_int in
  Alcotest.(check int64) "the full range has 2^63 values" Int64.min_int full;
  Alcotest.(check (option int64))
    "full: every r is accepted" (Some two63_minus_1) (offset full two63_minus_1);
  Alcotest.(check (option int64)) "full: r = 0" (Some 0L) (offset full 0L);
  (* (-1, max-int) has 2^62 + 1 values; 2^63 mod (2^62 + 1) = 2^62 - 1, so bits from 2^62 + 1 on
     are rejected: almost half of them *)
  let to_max = Infer_dist.uniform_bits_count (-1) max_int in
  let two62 = Int64.shift_left 1L 62 in
  Alcotest.(check int64) "(-1, max-int) size" (Int64.add two62 1L) to_max;
  Alcotest.(check (option int64)) "last accepted" (Some two62) (offset to_max two62);
  Alcotest.(check (option int64)) "first rejected" None (offset to_max (Int64.add two62 1L));
  Alcotest.(check (option int64)) "top rejected" None (offset to_max two63_minus_1);
  (* 2^32 + 1 values: offsets wrap modulo the size below the limit *)
  let just_above = Infer_dist.uniform_bits_count 0 (1 lsl 32) in
  let limit = Int64.sub Int64.min_int (Int64.unsigned_rem Int64.min_int just_above) in
  Alcotest.(check (option int64))
    "below the limit"
    (Some (Int64.rem (Int64.pred limit) just_above))
    (offset just_above (Int64.pred limit));
  Alcotest.(check (option int64)) "at the limit" None (offset just_above limit);
  Alcotest.(check bool)
    "2^32 values take the float formula" false
    (Infer_dist.uniform_span_at_least 0 ((1 lsl 32) - 1) Infer_dist.uniform_exact_threshold);
  Alcotest.(check bool)
    "2^32 + 1 values take bits" true
    (Infer_dist.uniform_span_at_least 0 (1 lsl 32) Infer_dist.uniform_exact_threshold);
  Alcotest.(check bool)
    "2^32 values at min-int take the float formula" false
    (Infer_dist.uniform_span_at_least min_int
       (min_int + (1 lsl 32) - 1)
       Infer_dist.uniform_exact_threshold);
  List.iter
    (fun (lo, hi) ->
      let rng = Infer_dist.Rng.make 11 and twin = Infer_dist.Rng.make 11 in
      let count = Infer_dist.uniform_bits_count lo hi in
      let rejected = ref 0 in
      let rec reference () =
        match offset count (Int64.shift_right_logical (Infer_dist.Rng.next_int64 twin) 1) with
        | Some o -> lo + Int64.to_int o
        | None ->
            incr rejected;
            reference ()
      in
      for _ = 1 to 200 do
        match Infer_dist.sample_dist ctx rng (Infer_dist.UniformInt (lo, hi)) with
        | Ok (Value.VInt x) ->
            Alcotest.(check int)
              (Printf.sprintf "%d..%d draws the reference" lo hi)
              (reference ()) x
        | Ok v -> Alcotest.failf "not an int: %s" (Value.show v)
        | Error e -> Alcotest.failf "sample failed: %s" (Runtime_err.to_string e)
      done;
      if Int64.equal count (Int64.add two62 1L) then
        Alcotest.(check bool) (Printf.sprintf "%d..%d rejected some bits" lo hi) true (!rejected > 0);
      if Int64.equal count Int64.min_int then
        Alcotest.(check int) "the full range never rejects" 0 !rejected)
    [
      (min_int, max_int);
      (-1, max_int);
      (min_int, 0);
      (0, 1 lsl 32);
      (max_int - (1 lsl 32), max_int);
      (0, 1 lsl 53);
    ];
  (* the full range reaches odd values and the low bits *)
  let rng = Infer_dist.Rng.make 5 in
  let odd = ref 0 in
  for _ = 1 to 100 do
    match Infer_dist.sample_dist ctx rng (Infer_dist.UniformInt (min_int, max_int)) with
    | Ok (Value.VInt x) -> if x land 1 = 1 then incr odd
    | _ -> Alcotest.fail "draw failed"
  done;
  Alcotest.(check bool) (Printf.sprintf "odd draws (%d of 100)" !odd) true (!odd > 20 && !odd < 80)

(* A range of n <= 2^32 values draws [int_of_float (u *. float n)] for u = k / 2^53, one of the 2^53
   equally likely floats [Rng.float] returns. An exact model of that arithmetic: the floats that draw
   offset j are the k from [first n j] (the least k drawing at least j; the draw is monotone in k)
   up to [first n (j + 1)], so offset j has [first n (j + 1) - first n j] of them. With
   q = floor(2^53/n), every count is in q - 1 .. q + 1: the k drawing j are those whose exact
   product lies in an interval [j - h_j, j + 1 - h_(j+1)] (open or closed at the ends), where
   h_j < n / 2^53 is half the float spacing just below j (products just below j round up to it) and
   h_j <= h_(j+1). Its length is at most 1, so it holds at most q + 1 of the k (spaced n / 2^53
   apart), and more than 1 - n / 2^53, so at least q - 1. For n <= 2^32, q >= 2^21: every offset is
   reachable. Small n are checked at every offset; large n at offsets near both ends, near each
   power of two and spread over the range. n = 10 shows that both q - 1 and q + 1 occur. *)
let test_uniform_float_counts () =
  let two53 = 9007199254740992.0 in
  let draw n k = int_of_float (Int64.to_float k /. two53 *. float_of_int n) in
  let first n j =
    let rec go lo hi =
      if lo >= hi then lo
      else
        let mid = Int64.add lo (Int64.div (Int64.sub hi lo) 2L) in
        if draw n mid >= j then go lo mid else go (Int64.succ mid) hi
    in
    go 0L (Int64.shift_left 1L 53)
  in
  let count n j = Int64.to_int (Int64.sub (first n (j + 1)) (first n j)) in
  let check n offsets =
    let q = (1 lsl 53) / n in
    Alcotest.(check int64)
      (Printf.sprintf "n = %d: no float draws n" n)
      (Int64.shift_left 1L 53) (first n n);
    List.iter
      (fun j ->
        if j >= 0 && j < n then
          let c = count n j in
          if c < q - 1 || c > q + 1 || c <= 0 then
            Alcotest.failf "n = %d, offset %d: %d floats, outside q - 1 .. q + 1 (q = %d)" n j c q)
      offsets
  in
  let q10 = (1 lsl 53) / 10 in
  Alcotest.(check (list int))
    "n = 10: counts"
    [ q10 + 1; q10; q10; q10; q10; q10; q10; q10 + 1; q10 - 1; q10 + 1 ]
    (List.init 10 (count 10));
  List.iter (fun n -> check n (List.init n Fun.id)) [ 1; 2; 3; 6; 7; 10; 97; 1000; 4099 ];
  List.iter
    (fun n ->
      let ends = List.init 64 Fun.id @ List.init 64 (fun i -> n - 1 - i) in
      let powers =
        List.concat_map
          (fun e -> [ (1 lsl e) - 2; (1 lsl e) - 1; 1 lsl e; (1 lsl e) + 1 ])
          (List.init 33 Fun.id)
      in
      let spread = List.init 500 (fun i -> (i * (n / 500)) + (i * 7919 mod max 1 (n / 500))) in
      check n (ends @ powers @ spread))
    [ 65537; 1000003; 2147483647; 2147483649; 3000000019; 4294967291; (1 lsl 32) - 1; 1 lsl 32 ]

(* draws stay in [lo, hi] for every range, including extreme bounds; a range of at most 2^32 values
   draws one uniform float scaled by its size, as every release did *)
let prop_uniform_draw_in_range =
  let extreme =
    QCheck.Gen.oneof_list
      [
        min_int;
        min_int + 1;
        -1;
        0;
        1;
        max_int - 1;
        max_int;
        1 lsl 53;
        (1 lsl 53) - 1;
        (1 lsl 53) + 1;
        -(1 lsl 53);
        1 lsl 32;
        (1 lsl 32) - 1;
        (1 lsl 32) + 1;
        -(1 lsl 32);
        1 lsl 60;
        (1 lsl 61) - 1;
      ]
  in
  let bound = QCheck.Gen.(oneof_weighted [ (2, extreme); (1, int); (1, int_range (-1000) 1000) ]) in
  QCheck.Test.make ~name:"uniform_draw stays in [lo, hi]" ~count:2000
    (QCheck.make
       ~print:(fun (a, b, seed) -> Printf.sprintf "(%d, %d, seed %d)" a b seed)
       QCheck.Gen.(triple bound bound int))
    (fun (a, b, seed) ->
      let lo = min a b and hi = max a b in
      let rng = Infer_dist.Rng.make seed and twin = Infer_dist.Rng.make seed in
      let x = Infer_dist.uniform_draw rng lo hi in
      x >= lo && x <= hi
      && Infer_dist.uniform_count lo hi > 0.0
      && (Infer_dist.uniform_span_at_least lo hi Infer_dist.uniform_exact_threshold
         || x = lo + int_of_float (Infer_dist.Rng.float twin *. float_of_int (hi - lo + 1))))

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
    Alcotest.test_case "uniform-int ranges wider than Int" `Quick test_uniform_wide_ranges;
    Alcotest.test_case "uniform-int ranges above 2^32 values draw exactly" `Quick
      test_uniform_exact_draws;
    Alcotest.test_case "uniform-int ranges of at most 2^32 values: every value gets q-1..q+1 floats"
      `Quick test_uniform_float_counts;
    QCheck_alcotest.to_alcotest prop_uniform_draw_in_range;
    Alcotest.test_case "root sampling handler; observe is a defect" `Quick
      test_root_sampling_handler;
    Alcotest.test_case "inference drivers own Dist under a root grant" `Quick
      test_driver_owns_dist_under_grant;
    Alcotest.test_case "likelihood weighting over uniform-int" `Quick test_lw_uniform_int;
    Alcotest.test_case "dist.sample-lw builtin" `Quick test_sample_lw_builtin;
    Alcotest.test_case "dist.sample-lw unchecked backstop (E0902, E0922)" `Quick
      test_sample_lw_unchecked_backstop;
  ]
