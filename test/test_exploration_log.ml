open Jacquard
module L = Exploration_log

let entry index kind ?site ?choice ?result ?output arguments =
  {
    L.e_index = index;
    e_kind = kind;
    e_operation = Hash.of_string ("op-" ^ string_of_int index);
    e_name = "op " ^ string_of_int index;
    e_site = site;
    e_choice = choice;
    e_arguments = arguments;
    e_result = result;
    e_output = output;
  }

let sample_log =
  {
    L.program =
      "program source="
      ^ Hash.to_hex (Hash.of_string "src")
      ^ " core=0.3.0 prelude=none engine=interpreter";
    seed = 7;
    grants = "console,Odd Name";
    policy_identity = Hash.of_string "policy";
    output_recorded = true;
    entries =
      [
        entry 0 L.Choice_step ~site:"m.jac:1:10-1:32" ~choice:("rain\nodd name", 2)
          ~result:(Observation_transcript.Data "true")
          [ (0, Observation_transcript.Data "bernoulli(0.5)") ];
        entry 1 L.Operation_step
          ~output:(Observation_transcript.Truncated { total = 99; prefix = "line\nwith newline" })
          ~result:(Observation_transcript.Failure "E0901")
          [
            (0, Observation_transcript.Truncated { total = 9000; prefix = "abc\ndef" });
            (2, Observation_transcript.Unsupported "secret");
            (3, Observation_transcript.Missing);
            (4, Observation_transcript.Unfinished);
          ];
        entry 2 L.Observe_step [];
      ];
    ending = L.Exit 0;
  }

let test_round_trip () =
  let bytes = L.serialize sample_log in
  (match L.parse bytes with
  | Ok log -> Alcotest.(check string) "re-serializes byte for byte" bytes (L.serialize log)
  | Error m -> Alcotest.failf "parse failed: %s" m);
  let bounded = L.serialize { sample_log with ending = L.Bounded "steps" } in
  match L.parse bounded with
  | Ok { L.ending = L.Bounded "steps"; _ } -> ()
  | _ -> Alcotest.fail "bounded ending did not round-trip"

let test_strict_parse () =
  let bytes = L.serialize sample_log in
  let refused label input = Alcotest.(check bool) label true (Result.is_error (L.parse input)) in
  refused "trailing bytes" (bytes ^ "x");
  refused "truncated" (String.sub bytes 0 (String.length bytes - 2));
  refused "other format"
    ("jacquard-exploration-log format=2" ^ String.sub bytes 33 (String.length bytes - 33));
  refused "step count" (Str.global_replace (Str.regexp_string "end steps=3") "end steps=4" bytes);
  refused "negative argument count"
    (Str.global_replace (Str.regexp_string "kind=observe") "kind=observe" bytes
    |> Str.global_replace (Str.regexp "arguments=0") "arguments=-1");
  refused "bad program source"
    (Str.global_replace (Str.regexp "program source=[0-9a-f]*") "program source=garbage" bytes);
  refused "bad seed" (Str.global_replace (Str.regexp_string "seed 7") "seed nonsense" bytes);
  refused "bad grants frame"
    (Str.global_replace (Str.regexp_string "grants bytes=16") "grants bytes=99" bytes);
  refused "bad bound"
    (Str.global_replace (Str.regexp_string "end steps=3 exit=0") "end steps=3 bounded=nope" bytes);
  refused "negative argument index"
    (Str.global_replace (Str.regexp_string "argument index=2") "argument index=-2" bytes);
  refused "truncated total within prefix"
    (Str.global_replace (Str.regexp_string "truncated total=9000") "truncated total=3" bytes);
  refused "negative draw"
    (Str.global_replace (Str.regexp_string "choice-name draw=2") "choice-name draw=-2" bytes);
  refused "a choice name on an operation step"
    (L.serialize
       {
         sample_log with
         entries =
           List.map
             (fun (e : L.entry) ->
               if e.L.e_index = 1 then { e with L.e_choice = Some ("n", 0) } else e)
             sample_log.entries;
       });
  refused "oversized frame"
    (Str.global_replace (Str.regexp_string "name bytes=4") "name bytes=4611686018427387903" bytes);
  (* argument positions are strictly ascending, as a recording writes them *)
  refused "repeated argument index"
    (Str.global_replace (Str.regexp_string "argument index=3") "argument index=2" bytes);
  refused "descending argument index"
    (Str.global_replace (Str.regexp_string "argument index=2") "argument index=5" bytes);
  (* hashes are spelled in canonical lowercase hex everywhere *)
  let upper_hex h = String.uppercase_ascii (Hash.to_hex h) in
  refused "uppercase program source"
    (Str.global_replace
       (Str.regexp_string (Hash.to_hex (Hash.of_string "src")))
       (upper_hex (Hash.of_string "src"))
       bytes);
  refused "uppercase policy identity"
    (Str.global_replace
       (Str.regexp_string (Hash.to_hex (Hash.of_string "policy")))
       (upper_hex (Hash.of_string "policy"))
       bytes);
  refused "uppercase operation"
    (Str.global_replace
       (Str.regexp_string (Hash.to_hex (Hash.of_string "op-0")))
       (upper_hex (Hash.of_string "op-0"))
       bytes);
  let prelude = Hash.to_hex (Hash.of_string "prelude") in
  let with_prelude =
    L.serialize
      {
        sample_log with
        L.program =
          Str.global_replace
            (Str.regexp_string "prelude=none")
            ("prelude=" ^ prelude) sample_log.L.program;
      }
  in
  (match L.parse with_prelude with
  | Ok _ -> ()
  | Error m -> Alcotest.failf "a lowercase prelude identity is refused: %s" m);
  refused "uppercase prelude identity"
    (Str.global_replace (Str.regexp_string prelude) (String.uppercase_ascii prelude) with_prelude)

(* parsing checks each step's index against a running count rather than the length of the steps
   read so far, so a long log parses in linear time; this pins that a long log round-trips (it
   does not time the parse) *)
let test_long_log () =
  let steps =
    List.init 20_000 (fun i ->
        entry i L.Operation_step ~result:(Observation_transcript.Data "1")
          [ (0, Observation_transcript.Data "x"); (3, Observation_transcript.Missing) ])
  in
  let bytes = L.serialize { sample_log with entries = steps } in
  match L.parse bytes with
  | Ok log -> Alcotest.(check int) "every step" 20_000 (List.length log.L.entries)
  | Error m -> Alcotest.failf "long log refused: %s" m

(* --- redaction under a wide payload generator --- *)

let expose = Hash.of_string "test secret.expose"
let print_op = Hash.of_string "test print"
let sample_op = Hash.of_string "test sample"

let policy ~field_bytes ~result =
  match
    Observation_policy.make ~result:Observation_policy.Compare ~field_bytes
      ~unlisted:
        (Some
           {
             Observation_policy.arguments = Observation_policy.All_arguments;
             result;
             output = Observation_policy.Compare;
           })
      ~interface:None []
  with
  | Ok p -> p
  | Error _ -> Alcotest.fail "test policy refused"

(* fragments data-v1 escapes or that are easy to mishandle: quotes, backslashes and escape-like
   text, every escaped control character, DEL, multi-byte and invalid UTF-8, the redaction marker
   itself and log keywords *)
let fragments =
  [|
    "\"";
    "\\";
    "\\n";
    "\\x01";
    "\n";
    "\t";
    "\r";
    "\x00";
    "\x01";
    "\x1b";
    "\x1f";
    "\x7f";
    " ";
    "<";
    ">";
    "é";
    "✓";
    "𝄞";
    "\xc3";
    "\xff";
    "a";
    "Z";
    "0";
    "<secret redacted>";
    "bytes=4";
    "\nend steps=0 exit=0\n";
    "data";
    "#";
  |]

(* a payload is fragments around a marker of letters no hex digest or log keyword spells, so a
   leak of the plaintext in any spelling shows up as the marker. The probe is the marker's first
   six bytes, short enough to fit in the bounded fields of the narrowest policy below. *)
let gen_payload =
  let open QCheck.Gen in
  let piece =
    oneof
      [
        map (fun i -> fragments.(i)) (int_bound (Array.length fragments - 1));
        map (String.make 1) char;
      ]
  in
  let pieces = map (String.concat "") (list_size (int_bound 6) piece) in
  let marker =
    map
      (fun cs -> "M" ^ String.concat "" (List.map (String.make 1) cs))
      (list_size (return 10) (char_range 'g' 'z'))
  in
  triple pieces marker pieces

let probe marker = String.sub marker 0 6

let record_with ?(expose = Some expose) policy (before, marker, after) =
  let plaintext = before ^ marker ^ after in
  let t =
    L.create ~policy ~record_output:true ~max_steps:100 ~max_bytes:1_000_000
      ~sample:(Some sample_op) ~observe:None ~expose
  in
  let operation call operation name ?choice arguments =
    L.on_event t
      (Observation.Operation
         { call; operation; name; arguments = Lazy.from_val arguments; site = None; choice })
  in
  let result call operation value =
    L.on_event t (Observation.Result { call; operation; result = Lazy.from_val (Ok value) })
  in
  let expose = Option.value expose ~default:(Hash.of_string "test not a secret") in
  operation 1 expose "secret.expose" [ Observation.Opaque "secret" ];
  result 1 expose (Observation.Text plaintext);
  operation 2 print_op "print"
    [
      Observation.Text ("bearer " ^ plaintext);
      Observation.Tuple [ Observation.Text plaintext; Observation.Int 1 ];
      Observation.Constructor
        {
          identity = Hash.of_string "Some";
          name = "Some";
          arguments = [ Observation.Text plaintext ];
        };
    ];
  L.on_event t (Observation.Output { call = 2; operation = print_op; bytes = plaintext ^ "\n" });
  result 2 print_op (Observation.Text (plaintext ^ "!"));
  operation 3 sample_op "sample" ~choice:("pick-" ^ plaintext) [ Observation.Text plaintext ];
  result 3 sample_op (Observation.Text plaintext);
  L.serialize (L.finish t ~program:"program" ~seed:0 ~grants:"secret" ~exit_status:0)

let contains ~sub s =
  let n = String.length sub and m = String.length s in
  let rec at i = i + n <= m && (String.sub s i n = sub || at (i + 1)) in
  at 0

let redaction_policies =
  [
    L.default_policy;
    (* results ignored: redaction still learns the plaintext *)
    policy ~field_bytes:4096 ~result:Observation_policy.Ignore;
    (* fields shorter than the payload: redacted before they are bounded *)
    policy ~field_bytes:9 ~result:Observation_policy.Compare;
  ]

(* the property can fail: without a secret operation the same recording shows the probe under
   every policy *)
let test_redaction_probe_detects () =
  let payload = ("", "Mghijklmnop", "") in
  List.iteri
    (fun i policy ->
      Alcotest.(check bool)
        (Printf.sprintf "policy %d shows an unexposed payload" i)
        true
        (contains ~sub:(probe "Mghijklmnop") (record_with ~expose:None policy payload)))
    redaction_policies

let prop_wide_redaction =
  QCheck.Test.make ~count:300 ~name:"no exposed plaintext reaches a log, in any spelling"
    (QCheck.make ~print:(fun (b, m, a) -> Printf.sprintf "%S" (b ^ m ^ a)) gen_payload)
    (fun payload ->
      let _, marker, _ = payload in
      List.for_all
        (fun policy -> not (contains ~sub:(probe marker) (record_with policy payload)))
        redaction_policies)

(* --- serving a stored group in the persisted member order --- *)

let group_decl what src =
  match Reader.parse_string ~file:what src with
  | Ok [ form ] -> (
      match Result.bind (Kernel.of_form form) (Resolve.resolve Corpus_support.stub_names) with
      | Ok (Kernel.Decl d) -> d
      | Ok (Kernel.Expr _) -> Alcotest.failf "%s: not a declaration" what
      | Error ds -> Alcotest.failf "%s: %s" what (String.concat "; " (List.map Diag.to_string ds)))
  | _ -> Alcotest.failf "%s: parse failed" what

let member_hashes d =
  match Canon.hash_decl d with
  | Ok hs -> hs
  | Error ds -> Alcotest.failf "hash: %s" (String.concat "; " (List.map Diag.to_string ds))

(* each member reaches the other through a live splice two quasiquote levels down
   (quote { quote { unquote(unquote(...)) } }) and through a level-0 splice *)
let ping =
  {|(binding ping () (lam ((pvar n)) (quote (quote (unquote (unquote (app (var pong) (var n))))))))|}

let pong = {|(binding pong () (lam ((pvar n)) (quote (unquote (app (var ping) (var n))))))|}

let test_persisted_order () =
  let stored = group_decl "stored" ("(defterm (" ^ ping ^ " " ^ pong ^ "))") in
  let source = group_decl "source" ("(defterm (" ^ pong ^ " " ^ ping ^ "))") in
  let stored_hs = member_hashes stored and source_hs = member_hashes source in
  let names hs = List.map snd hs.Canon.named in
  Alcotest.(check bool)
    "the source lists the members in another order" false
    (List.equal Hash.equal (names stored_hs) (names source_hs));
  (match
     Store.in_persisted_order source ~incoming:(names source_hs) ~persisted:(names stored_hs)
   with
  | None -> Alcotest.fail "a reordered group with nested live splices is not served"
  | Some served ->
      let served_hs = member_hashes served in
      Alcotest.(check string)
        "served group hash"
        (Hash.to_hex stored_hs.Canon.decl_hash)
        (Hash.to_hex served_hs.Canon.decl_hash);
      Alcotest.(check (list string))
        "served member order"
        (List.map Hash.to_hex (names stored_hs))
        (List.map Hash.to_hex (names served_hs)));
  (* member hashes are distinct by construction; a list that repeats one is never served *)
  let a, b = match names source_hs with [ a; b ] -> (a, b) | _ -> Alcotest.fail "two members" in
  let refused label ~incoming ~persisted =
    Alcotest.(check bool)
      label true
      (Option.is_none (Store.in_persisted_order source ~incoming ~persisted))
  in
  refused "repeated incoming hash" ~incoming:[ a; a ] ~persisted:[ b; a ];
  refused "repeated persisted hash" ~incoming:[ a; b ] ~persisted:[ b; b ];
  refused "not a permutation" ~incoming:[ a; b ] ~persisted:[ b; Hash.of_string "other" ];
  refused "another size" ~incoming:[ a; b ] ~persisted:[ b ]

let test_remap_refuses_unrenumberable () =
  let expr it = { Kernel.it; meta = Meta.empty } in
  let splice body = Form.form "unquote" [ Form.F body ] in
  let quoted payload = expr (Kernel.Quote payload) in
  let live_ref = quoted (splice (Kernel.expr_to_form (expr (Kernel.GroupRef 1)))) in
  (match Store.remap_group_refs (fun i -> Some (1 - i)) live_ref with
  | Some { Kernel.it = Kernel.Quote payload; _ } ->
      Alcotest.(check string)
        "a live reference is renumbered"
        (Form.to_string (splice (Kernel.expr_to_form (expr (Kernel.GroupRef 0)))))
        (Form.to_string payload)
  | _ -> Alcotest.fail "a live reference is not renumbered");
  (* under a nested quote the same unquote is data and keeps its number *)
  let data_ref =
    quoted (Form.form "quote" [ Form.F (splice (Form.form "groupref" [ Form.Int 1 ])) ])
  in
  (match Store.remap_group_refs (fun i -> Some (1 - i)) data_ref with
  | Some e ->
      Alcotest.(check bool)
        "data is unchanged" true
        (Form.equal_ignoring_meta (Kernel.expr_to_form e) (Kernel.expr_to_form data_ref))
  | None -> Alcotest.fail "data refused");
  Alcotest.(check bool)
    "a live splice that is not a kernel expression" true
    (Option.is_none
       (Store.remap_group_refs (fun i -> Some i) (quoted (splice (Form.form "not-a-form" [])))));
  Alcotest.(check bool)
    "a reference the renumbering does not cover" true
    (Option.is_none (Store.remap_group_refs (fun _ -> None) live_ref))

(* --- a log write that fails part way leaves no partial log --- *)

let with_dir f =
  let dir = Filename.temp_dir "jacquard-explog-" "" in
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun n -> Sys.remove (Filename.concat dir n)) (Sys.readdir dir);
      Sys.rmdir dir)
    (fun () -> f dir)

let reserved path =
  match L.reserve ~path with Ok r -> r | Error m -> Alcotest.failf "reserve: %s" m

(* writes the first chunk partly, then fails as a full file system would *)
let failing_write ?(before_failing = ignore) () =
  let calls = ref 0 in
  fun fd bytes off len ->
    incr calls;
    if !calls = 1 then Unix.write fd bytes off (min len 10)
    else begin
      before_failing ();
      raise (Unix.Unix_error (Unix.EFBIG, "write", ""))
    end

let file_contents path = In_channel.with_open_bin path In_channel.input_all

let test_failed_write_removes_log () =
  with_dir (fun dir ->
      let path = Filename.concat dir "run.log" in
      let r = reserved path in
      match L.write_reserved ~write:(failing_write ()) r (L.serialize sample_log) with
      | Ok () -> Alcotest.fail "the failing write succeeded"
      | Error m ->
          Alcotest.(check bool)
            ("cleanup reported: " ^ m) true
            (contains ~sub:"no partial log was left" m);
          Alcotest.(check bool) "the log path is gone" false (Sys.file_exists path))

let test_failed_write_keeps_substitute () =
  with_dir (fun dir ->
      let path = Filename.concat dir "run.log" and moved = Filename.concat dir "moved.log" in
      let r = reserved path in
      (* between the reservation and the failure, the reserved file is renamed away and another
         file is put at its path: that file is not the log's to remove *)
      let substitute () =
        Unix.rename path moved;
        Out_channel.with_open_bin path (fun oc -> output_string oc "someone else's")
      in
      match
        L.write_reserved
          ~write:(failing_write ~before_failing:substitute ())
          r (L.serialize sample_log)
      with
      | Ok () -> Alcotest.fail "the failing write succeeded"
      | Error m ->
          Alcotest.(check bool)
            ("cleanup reported: " ^ m) true
            (contains ~sub:"no partial log was left" m);
          Alcotest.(check string)
            "the substitute is untouched" "someone else's" (file_contents path);
          Alcotest.(check string) "the reserved file is emptied" "" (file_contents moved))

let suite =
  [
    Alcotest.test_case "exploration-log round trip" `Quick test_round_trip;
    Alcotest.test_case "exploration-log strict parse" `Quick test_strict_parse;
    Alcotest.test_case "exploration-log long log" `Quick test_long_log;
    Alcotest.test_case "redaction probe detects an unexposed payload" `Quick
      test_redaction_probe_detects;
    QCheck_alcotest.to_alcotest ~rand:(Random.State.make [| 0xE1; 0x0C |]) prop_wide_redaction;
    Alcotest.test_case "stored group served in persisted order" `Quick test_persisted_order;
    Alcotest.test_case "failed log write removes the partial log" `Quick
      test_failed_write_removes_log;
    Alcotest.test_case "failed log write leaves a substituted file alone" `Quick
      test_failed_write_keeps_substitute;
    Alcotest.test_case "group renumbering refuses what it cannot renumber" `Quick
      test_remap_refuses_unrenumberable;
  ]
