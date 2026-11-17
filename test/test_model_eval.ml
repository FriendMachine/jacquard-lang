open Jacquard
module E = Model_eval
module T = Observation_transcript

let dependency =
  {
    Model_doc.entry = Hash.of_string "entry";
    signature = Hash.of_string "sig";
    labels = None;
    prelude = "none";
    core = "0.3.0";
    driver = Model_doc.Enumerate { max_branches = 10 };
    fuel = 1000;
    policy = Hash.of_string "policy";
    arguments = [ Model_doc.Assumption (Hash.of_string "a") ];
  }

let cacheable =
  [
    E.Value (Some (T.Data "outcome value\nwith a newline"));
    E.Posterior
      {
        sampled = false;
        explored = 2;
        entries =
          Some
            [
              { E.probability = 0.7; value = T.Data "false#00" };
              { E.probability = 0.30000000000000004; value = T.Data "true#01" };
            ];
      };
    E.Posterior { sampled = true; explored = 5; entries = Some [] };
    E.Inference_failure { sampled = false; explored = 3; failure = "impossible" };
    E.Failure "arithmetic";
  ]

let test_round_trip () =
  List.iter
    (fun outcome ->
      Alcotest.(check (option string)) "cacheable" None (E.uncacheable outcome);
      let bytes = E.serialize dependency outcome in
      match E.parse bytes with
      | Ok (d, o) -> Alcotest.(check string) "re-serializes byte for byte" bytes (E.serialize d o)
      | Error m -> Alcotest.failf "parse failed: %s" m)
    cacheable

let test_uncacheable () =
  let reason label expected outcome =
    Alcotest.(check (option string)) label (Some expected) (E.uncacheable outcome);
    Alcotest.(check bool)
      (label ^ " is never parsed") true
      (Result.is_error (E.parse (E.serialize dependency outcome)))
  in
  reason "incomplete" "fuel" E.Incomplete;
  reason "excluded" "result-excluded" (E.Value None);
  reason "a secret" "secret" (E.Value (Some (T.Unsupported "secret")));
  reason "truncated" "truncated" (E.Value (Some (T.Truncated { total = 9; prefix = "ab" })));
  reason "a closure in a posterior" "closure"
    (E.Posterior
       {
         sampled = false;
         explored = 1;
         entries = Some [ { E.probability = 1.0; value = T.Unsupported "closure" } ];
       })

let test_strict_parse () =
  let bytes = E.serialize dependency (List.nth cacheable 1) in
  let refused label input = Alcotest.(check bool) label true (Result.is_error (E.parse input)) in
  let replace a b = Str.global_replace (Str.regexp_string a) b bytes in
  refused "trailing bytes" (bytes ^ "x");
  refused "truncated" (String.sub bytes 0 (String.length bytes - 1));
  refused "entry count" (replace "entries=2" "entries=3");
  refused "noncanonical probability" (replace "p=0.69999999999999996" "p=0.7");
  refused "payload length" (replace "data bytes=8" "data bytes=9");
  refused "no outcome" (Model_doc.serialize_dependency dependency);
  refused "an overflowing payload length"
    (E.serialize dependency (E.Value (Some (T.Data "x")))
    |> Str.global_replace (Str.regexp_string "data bytes=1") "data bytes=4611686018427387903");
  refused "foreign record" ("x" ^ bytes)

let history_dependency =
  {
    dependency with
    Model_doc.arguments =
      dependency.Model_doc.arguments
      @ [ Model_doc.Term { term = Hash.of_string "t"; signature = Hash.of_string "s" } ];
  }

let record =
  {
    Model_history.time = "2026-10-28T05:56:31Z";
    entry_name = "scale";
    entry_closure = Some (Hash.of_string "closure");
    key = Model_doc.key history_dependency;
    previous = Some (Hash.of_string "older");
    outcome = "fresh value";
    source = Hash.of_string "source";
    interface = Hash.of_string "interface";
    policy_snapshot = Hash.of_string "policy";
    bindings =
      [
        { Model_history.kind = "assumption"; name = "base"; snapshot = Some (Hash.of_string "3") };
        { Model_history.kind = "term"; name = "helper"; snapshot = None };
      ];
    dependency = history_dependency;
  }

let input_dependency =
  {
    history_dependency with
    Model_doc.arguments =
      [
        Model_doc.Input (Hash.of_string "bytes");
        Model_doc.Term { term = Hash.of_string "t"; signature = Hash.of_string "s" };
      ];
  }

let frame r =
  let b = Model_history.serialize_record r in
  Printf.sprintf "entry bytes=%d\n%s\n" (String.length b) b

let test_history_round_trip () =
  let bytes =
    frame record ^ frame { record with Model_history.previous = None; outcome = "cached value" }
  in
  match Model_history.parse_history bytes with
  | Ok [ a; b ] ->
      Alcotest.(check string) "first" (frame record) (frame a);
      Alcotest.(check string) "second" "cached value" b.Model_history.outcome
  | Ok _ -> Alcotest.fail "expected two records"
  | Error m -> Alcotest.failf "parse failed: %s" m

(* a record written before closure manifests existed has no entry-closure line, and still parses *)
let test_history_without_closure () =
  let old = { record with Model_history.entry_closure = None } in
  let bytes = frame old in
  Alcotest.(check bool)
    "no entry-closure line" false
    (Str.string_match (Str.regexp ".*entry-closure") bytes 0);
  match Model_history.parse_history bytes with
  | Ok [ r ] -> Alcotest.(check string) "round trip" bytes (frame r)
  | _ -> Alcotest.fail "a record without a closure did not parse"

let test_history_strict () =
  let bytes = frame record in
  let refused label input =
    Alcotest.(check bool) label true (Result.is_error (Model_history.parse_history input))
  in
  let replace a b = Str.global_replace (Str.regexp_string a) b bytes in
  refused "trailing bytes" (bytes ^ "x");
  refused "frame length" (replace "entry bytes=" "entry bytes=9");
  refused "an overflowing frame length"
    (Str.global_replace (Str.regexp "entry bytes=[0-9]*") "entry bytes=4611686018427387903" bytes);
  refused "binding count" (replace "bindings 2" "bindings 3");
  refused "binding order" (replace "binding 1 term" "binding 0 term");
  let reframe r = frame r in
  refused "a key that is not the dependency record's"
    (reframe { record with Model_history.key = Hash.of_string "another" });
  refused "a binding kind that does not match its argument"
    (reframe
       {
         record with
         Model_history.bindings =
           [
             { Model_history.kind = "input"; name = "base"; snapshot = Some (Hash.of_string "3") };
             { Model_history.kind = "term"; name = "helper"; snapshot = None };
           ];
       });
  refused "an input snapshot that is not its identity"
    (reframe
       {
         record with
         Model_history.bindings =
           [
             {
               Model_history.kind = "input";
               name = "note";
               snapshot = Some (Hash.of_string "other");
             };
             { Model_history.kind = "term"; name = "helper"; snapshot = None };
           ];
         dependency = input_dependency;
         key = Model_doc.key input_dependency;
       });
  refused "a missing binding"
    (reframe { record with Model_history.bindings = [ List.hd record.Model_history.bindings ] });
  Alcotest.(check bool)
    "an empty history is no records" true
    (Model_history.parse_history "" = Ok [])

let hexs s = Hash.to_hex (Hash.of_string s)

let test_parse_closure () =
  let d = hexs "decl" and b = hexs "body" in
  let header = "jacquard-model-closure format=1\n" in
  let good = Printf.sprintf "%sroot %s\nf term %s %s\n- - %s none\n" header d d b b in
  (match Model_history.parse_closure good with
  | Some (root, [ (("f", "term"), d', b'); (("-", "-"), d'', "none") ]) ->
      Alcotest.(check string) "root" d root;
      Alcotest.(check (list string)) "hashes" [ d; b; b ] [ d'; b'; d'' ]
  | _ -> Alcotest.fail "a well-formed manifest did not parse");
  Alcotest.(check bool)
    "a manifest without lines" true
    (Model_history.parse_closure (Printf.sprintf "%sroot %s\n" header d) = Some (d, []));
  let refused label text =
    Alcotest.(check bool) label true (Model_history.parse_closure text = None)
  in
  refused "no root line" (Printf.sprintf "%sf term %s %s\n" header d b);
  refused "a root that is not a hash" (Printf.sprintf "%sroot xyz\n" header);
  refused "an uppercase root" (Printf.sprintf "%sroot %s\n" header (String.uppercase_ascii d));
  refused "another header" (Printf.sprintf "jacquard-model-closure format=2\nroot %s\n" d);
  refused "a short line" (Printf.sprintf "%sroot %s\nf term %s\n" header d d);
  refused "an unknown kind" (Printf.sprintf "%sroot %s\nf thing %s %s\n" header d d b);
  refused "a name without a kind" (Printf.sprintf "%sroot %s\nf - %s %s\n" header d d b);
  refused "a body that is not a hash" (Printf.sprintf "%sroot %s\nf term %s nope\n" header d d);
  refused "no final newline" (Printf.sprintf "%sroot %s\nf term %s %s" header d d b);
  refused "a blank line" (Printf.sprintf "%sroot %s\n\nf term %s %s\n" header d d b)

(* a stored declaration that cannot be loaded is listed with body none, not left out *)
let test_closure_unloadable () =
  let store =
    match Store.open_store (Eval_support.fresh_dir ()) with
    | Ok s -> s
    | Error ds -> Eval_support.fail_diags "open_store" ds
  in
  let g =
    Eval_support.put_src store (Store.names_view store) "(defterm ((binding g () (lit 1))))"
  in
  let f =
    Eval_support.put_src store (Store.names_view store) "(defterm ((binding f () (var g))))"
  in
  let g_decl = Hash.to_hex g.Canon.decl_hash in
  let line_of text =
    match Model_history.parse_closure text with
    | Some (_, lines) -> List.find_opt (fun ((n, _), _, _) -> n = "g") lines
    | None -> Alcotest.fail "the manifest did not parse"
  in
  let before, bodies = Model_history.closure ~store (List.assoc "f" f.Canon.named) in
  Alcotest.(check int) "both bodies retained" 2 (List.length bodies);
  (match line_of before with
  | Some (_, d, b) ->
      Alcotest.(check string) "g's declaration" g_decl d;
      Alcotest.(check bool) "g's body is retained" true (b <> "none")
  | None -> Alcotest.fail "g is not listed");
  (* a store whose object for g is gone: a fresh store state, so nothing is reused *)
  let store' =
    match Store.open_store store.Store.root with
    | Ok s -> s
    | Error ds -> Eval_support.fail_diags "reopen" ds
  in
  Sys.remove (Store.object_path store' g.Canon.decl_hash);
  let after, _ = Model_history.closure ~store:store' (List.assoc "f" f.Canon.named) in
  match line_of after with
  | Some (_, d, b) ->
      Alcotest.(check string) "g's declaration" g_decl d;
      Alcotest.(check string) "g's body" "none" b
  | None -> Alcotest.fail "an unloadable declaration was left out"

(* a stored declaration whose bytes read but do not load is listed with body none, and its bytes
   are not retained *)
let test_closure_unparsable () =
  let store =
    match Store.open_store (Eval_support.fresh_dir ()) with
    | Ok s -> s
    | Error ds -> Eval_support.fail_diags "open_store" ds
  in
  let g =
    Eval_support.put_src store (Store.names_view store) "(defterm ((binding g () (lit 2))))"
  in
  let f =
    Eval_support.put_src store (Store.names_view store) "(defterm ((binding f () (var g))))"
  in
  let store' =
    match Store.open_store store.Store.root with
    | Ok s -> s
    | Error ds -> Eval_support.fail_diags "reopen" ds
  in
  let path = Store.object_path store' g.Canon.decl_hash in
  (try Unix.chmod path 0o600 with Unix.Unix_error _ -> ());
  Out_channel.with_open_bin path (fun oc -> output_string oc "(not a declaration");
  let text, bodies = Model_history.closure ~store:store' (List.assoc "f" f.Canon.named) in
  (match Model_history.parse_closure text with
  | Some (_, lines) -> (
      match List.find_opt (fun ((n, _), _, _) -> n = "g") lines with
      | Some (_, _, b) -> Alcotest.(check string) "g's body" "none" b
      | None -> Alcotest.fail "an unparsable declaration was left out")
  | None -> Alcotest.fail "the manifest did not parse");
  Alcotest.(check int) "only f's body is retained" 1 (List.length bodies);
  Alcotest.(check bool)
    "the unparsable bytes are not retained" false
    (List.exists (fun (_, b) -> b = "(not a declaration") bodies)

let suite =
  [
    Alcotest.test_case "model closure manifests parse strictly" `Quick test_parse_closure;
    Alcotest.test_case "model closure lists unloadable declarations" `Quick test_closure_unloadable;
    Alcotest.test_case "model closure lists unparsable declarations" `Quick test_closure_unparsable;
    Alcotest.test_case "model history round trip" `Quick test_history_round_trip;
    Alcotest.test_case "model history strict parse" `Quick test_history_strict;
    Alcotest.test_case "model history without closures" `Quick test_history_without_closure;
    Alcotest.test_case "model-result round trip" `Quick test_round_trip;
    Alcotest.test_case "model-result refuses uncacheable outcomes" `Quick test_uncacheable;
    Alcotest.test_case "model-result strict parse" `Quick test_strict_parse;
  ]
