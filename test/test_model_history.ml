(* Model history rotation (docs/designs/model-dependencies.md §3.5a): a history at its size limit
   is moved to a numbered file beside it and a new history starts with the records explain reports
   from. Small limits stand in for the 64 MiB one. *)

open Jacquard
module H = Model_history
module M = Model_doc
module D = Test_model_doc

let document = Hash.of_string "rotation document"

(* a one-result document over [f(x) = add(x, k)], its assumption spelled [a]; prepared once per
   spelling and [k] (a prepared document is never changed by appending or explaining) *)
let memo = Hashtbl.create 16

let rec prepared ?(a = "3") label k =
  match Hashtbl.find_opt memo (a, k) with
  | Some p -> p
  | None ->
      let p = prepare ~a label k in
      Hashtbl.replace memo (a, k) p;
      p

and prepare ~a label k =
  let dir = D.fresh_dir label in
  D.write dir "m.jac" (Printf.sprintf "f(x) = add(x, %d)\n" k);
  let text =
    Printf.sprintf
      "jacquard-model format=1\n\
       source m.jac\n\
       assumption a = %s\n\n\
       result r entry f args a driver run fuel=1000\n"
      a
  in
  D.write dir "doc.model" text;
  let file = Filename.concat dir "doc.model" in
  let root = Filename.concat (D.fresh_dir (label ^ "-store")) "store" in
  match Result.bind (M.parse ~file text) (M.prepare ~prelude_dir:D.prelude_dir ~root ~file) with
  | Ok p -> p
  | Error ds ->
      Alcotest.failf "prepare failed: %s" (String.concat "; " (List.map Diag.to_string ds))

let resolved (p : M.prepared) = List.hd p.M.resolved
let append ?limit cache p = H.append ?limit ~cache ~document p (resolved p) ~outcome:"fresh value"

let appended ?limit cache p =
  match append ?limit cache p with
  | Ok note -> note
  | Error { Model_eval.reason; _ } -> Alcotest.failf "append failed: %s" reason

let path cache =
  Filename.concat (Filename.concat (Filename.concat cache "history") (Hash.to_hex document)) "r"

let read file = In_channel.with_open_bin file In_channel.input_all
let write file bytes = Out_channel.with_open_bin file (fun oc -> output_string oc bytes)

let records bytes =
  match H.parse_history bytes with
  | Ok rs -> rs
  | Error reason -> Alcotest.failf "the history does not parse: %s" reason

let frame (r : H.record) =
  let b = H.serialize_record r in
  Printf.sprintf "entry bytes=%d\n%s\n" (String.length b) b

let last l = List.nth l (List.length l - 1)
let exists file = match Unix.lstat file with _ -> true | exception Unix.Unix_error _ -> false

let explained cache ps =
  List.map
    (fun p ->
      let es = H.explain ~cache ~document p in
      (String.concat "\n" (List.concat_map H.render_text es), H.to_json es))
    ps

(* removes the snapshot of the latest record's assumption, so an equal respelling refreshes *)
let prune_assumption cache =
  let latest = last (records (read (path cache))) in
  List.iter
    (fun (b : H.binding) ->
      match (b.H.kind, b.H.snapshot) with
      | "assumption", Some h ->
          Sys.remove (Filename.concat (Filename.concat cache "snapshots") (Hash.to_hex h))
      | _ -> ())
    latest.H.bindings

let rotated = function
  | Some (Model_eval.Rotated note) -> note
  | Some (Model_eval.Repaired note) -> Alcotest.failf "expected a rotation, got a repair: %s" note
  | None -> Alcotest.fail "expected a rotation note"

let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0

(* a history of eight records under keys k1, k3, k1, k3, k1, k3, k2, and k2 again as a refresh
   (an equal respelling of its assumption after the old snapshot is pruned), so explain reads the
   record before the run, the run's first record and the latest *)
let build label =
  let cache = D.fresh_dir (label ^ "-cache") in
  let p1 = prepared (label ^ "-1") 1 and p3 = prepared (label ^ "-3") 3 in
  let p2 = prepared (label ^ "-2") 2 and p2' = prepared ~a:"(3)" (label ^ "-2r") 2 in
  List.iter (fun p -> ignore (appended cache p)) [ p1; p3; p1; p3; p1; p3; p2 ];
  prune_assumption cache;
  ignore (appended cache p2');
  let rs = records (read (path cache)) in
  Alcotest.(check int) "eight records" 8 (List.length rs);
  Alcotest.(check bool)
    "the last two share a key" true
    (Hash.equal (List.nth rs 6).H.key (List.nth rs 7).H.key);
  (cache, p1, p2, p3)

(* rotate by appending [next] under a limit just above the history's size, then check: [.1]
   holds the old bytes, the new history is the last three old records and the new one, and explain
   (for each of [views]) is the same as over the old history with the new record appended *)
let check_rotation label cache next views =
  let file = path cache in
  let old = read file in
  let note = rotated (appended ~limit:(String.length old + 1) cache next) in
  Alcotest.(check bool)
    (label ^ ": the note names .1") true
    (contains note ("every earlier record is kept in " ^ file ^ ".1"));
  Alcotest.(check string) (label ^ ": .1 holds the old bytes") old (read (file ^ ".1"));
  Alcotest.(check bool) (label ^ ": no .2") false (exists (file ^ ".2"));
  let now = read file in
  let rs = records now in
  let olds = records old in
  let added = last rs in
  let seed = List.filteri (fun i _ -> i >= List.length olds - 3) olds in
  Alcotest.(check string)
    (label ^ ": seed and the new record")
    (String.concat "" (List.map frame (seed @ [ added ])))
    now;
  let after = explained cache views in
  (* the same evaluation without rotation *)
  write file (old ^ frame added);
  let reference = explained cache views in
  write file now;
  List.iter2
    (fun (t, j) (t', j') ->
      Alcotest.(check string) (label ^ ": explain text") t' t;
      Alcotest.(check string) (label ^ ": explain JSON") j' j)
    after reference;
  (olds, rs)

let test_rotation_new_key () =
  let cache, p1, _, _ = build "rot-new" in
  let p4 = prepared "rot-new-4" 4 in
  let _, rs = check_rotation "new key" cache p4 [ p4; p1 ] in
  match H.explain ~cache ~document p4 with
  | [ { H.freshness = H.Current; transition = Some _; _ } ] ->
      Alcotest.(check int) "four records" 4 (List.length rs)
  | _ -> Alcotest.fail "expected current, with a transition"

let test_rotation_refresh () =
  let cache, p1, p2, _ = build "rot-refresh" in
  let olds = records (read (path cache)) in
  prune_assumption cache;
  let olds', _ = check_rotation "refresh" cache p2 [ p2; p1 ] in
  Alcotest.(check bool) "built as expected" true (olds = olds');
  match H.explain ~cache ~document p2 with
  | [ { H.evaluated_at; previous; transition = Some _; _ } ] ->
      Alcotest.(check (option string))
        "evaluated_at is the run's first record" (Some (List.nth olds 6).H.time) evaluated_at;
      (* the run's first record follows k3, its latest record k2: this tells them apart *)
      Alcotest.(check bool)
        "previous is the run's first record's" true
        (previous = (List.nth olds 6).H.previous && previous <> (List.nth olds 7).H.previous)
  | _ -> Alcotest.fail "expected one explanation with a transition"

(* N is one more than the largest N of any entry, of whatever kind; none of them is followed or
   changed *)
let test_numbering () =
  let cache, _, _, _ = build "numbering" in
  let file = path cache in
  Unix.symlink file (file ^ ".1");
  let old = read file in
  ignore (rotated (appended ~limit:(String.length old + 1) cache (prepared "numbering-5" 5)));
  Alcotest.(check string) ".2, past a link to the history itself" old (read (file ^ ".2"));
  Alcotest.(check string) "the link is unchanged" file (Unix.readlink (file ^ ".1"));
  Unix.mkdir (file ^ ".3") 0o700;
  Unix.mkfifo (file ^ ".4") 0o600;
  write (file ^ ".0") "zero";
  write (file ^ ".05") "padded";
  write (file ^ ".x") "other";
  let old = read file in
  let note = rotated (appended ~limit:(String.length old + 1) cache (prepared "numbering-6" 6)) in
  Alcotest.(check bool) "the note names .5" true (contains note (file ^ ".5"));
  Alcotest.(check string) ".5, past a directory and a FIFO" old (read (file ^ ".5"));
  Alcotest.(check bool)
    "the directory is unchanged" true
    ((Unix.lstat (file ^ ".3")).Unix.st_kind = Unix.S_DIR && Sys.readdir (file ^ ".3") = [||]);
  Alcotest.(check bool)
    "the FIFO is unchanged" true
    ((Unix.lstat (file ^ ".4")).Unix.st_kind = Unix.S_FIFO);
  Alcotest.(check (list string))
    "other names are untouched" [ "zero"; "padded"; "other" ]
    (List.map (fun s -> read (file ^ s)) [ ".0"; ".05"; ".x" ]);
  Alcotest.(check bool) "no .6" false (exists (file ^ ".6"))

(* an evaluation that stopped between the link and the new history: the newest [.N] is the history
   itself, and the next record completes the rotation into it, at the limit or not *)
let test_interrupted () =
  List.iter
    (fun at_limit ->
      let label = if at_limit then "crash-limit" else "crash-small" in
      let cache, _, _, _ = build label in
      let file = path cache in
      let old = read file in
      Unix.link file (file ^ ".1");
      let limit = if at_limit then Some (String.length old + 1) else None in
      let note = rotated (appended ?limit cache (prepared (label ^ "-7") 7)) in
      Alcotest.(check bool) (label ^ ": the note names .1") true (contains note (file ^ ".1"));
      Alcotest.(check bool) (label ^ ": no .2") false (exists (file ^ ".2"));
      Alcotest.(check string) (label ^ ": .1 keeps the old bytes") old (read (file ^ ".1"));
      let olds = records old and rs = records (read file) in
      Alcotest.(check bool)
        (label ^ ": a new history, the last three records and the new one")
        true
        (List.length rs = 4
        && List.filteri (fun i _ -> i < 3) rs
           = List.filteri (fun i _ -> i >= List.length olds - 3) olds);
      Alcotest.(check bool)
        (label ^ ": no longer one file") true
        ((Unix.lstat file).Unix.st_ino <> (Unix.lstat (file ^ ".1")).Unix.st_ino))
    [ true; false ]

(* a history too large to read is moved aside, and the new history starts unseeded *)
let test_oversized () =
  let cache = D.fresh_dir "oversized-cache" in
  let p = prepared "oversized" 1 in
  ignore (appended cache p);
  let file = path cache in
  let junk = String.make 4097 'x' in
  write file junk;
  let note = rotated (appended ~limit:4096 cache p) in
  Alcotest.(check bool) "the note says so" true (contains note "larger than 4096 bytes");
  Alcotest.(check bool) "a new history" true (contains note "a new history was started");
  Alcotest.(check string) ".1 holds the old bytes" junk (read (file ^ ".1"));
  match records (read file) with
  | [ r ] -> Alcotest.(check bool) "no predecessor" true (r.H.previous = None)
  | _ -> Alcotest.fail "expected one record"

(* a damaged history is moved aside whole, and seeded from the records before the damage *)
let test_damaged () =
  let cache, _, _, _ = build "damaged" in
  let file = path cache in
  let kept = read file in
  let old = kept ^ "junk\n" in
  write file old;
  let note = rotated (appended ~limit:(String.length old) cache (prepared "damaged-8" 8)) in
  Alcotest.(check bool) "the note names the damage" true (contains note "damaged (bad frame)");
  Alcotest.(check string) ".1 holds the damaged bytes" old (read (file ^ ".1"));
  let olds = records kept and rs = records (read file) in
  Alcotest.(check bool)
    "seeded from the records before the damage" true
    (List.filteri (fun i _ -> i < 3) rs = List.filteri (fun i _ -> i >= List.length olds - 3) olds)

(* A child process for the concurrency test: the test executable runs it at start-up, before
   any test, when [JACQUARD_TEST_HISTORY_CHILD] is "CACHE LIMIT K"; it appends the record of [k]
   and exits 10 after a rotation, 0 after a plain append, and 1 otherwise. Separate processes
   (rather than [Unix.fork]) because the test executable runs domains. *)
let () =
  match Sys.getenv_opt "JACQUARD_TEST_HISTORY_CHILD" with
  | None -> ()
  | Some spec ->
      let code =
        match String.split_on_char ' ' spec with
        | [ cache; limit; k ] -> (
            match
              append ~limit:(int_of_string limit) cache (prepare ~a:"3" "child" (int_of_string k))
            with
            | Ok (Some (Model_eval.Rotated _)) -> 10
            | Ok None -> 0
            | Ok (Some _) | Error _ -> 1
            | exception _ -> 2)
        | _ -> 3
      in
      Unix._exit code

(* the processes waiting for a lock on the file with inode [ino], from /proc/locks (0 where it
   cannot be read) *)
let waiting ino =
  match In_channel.with_open_text "/proc/locks" In_channel.input_all with
  | text ->
      List.length
        (List.filter
           (fun l ->
             let words = String.split_on_char ' ' l in
             List.mem "->" words
             && List.exists (String.ends_with ~suffix:(":" ^ string_of_int ino)) words)
           (String.split_on_char '\n' text))
  | exception Sys_error _ -> 0

(* two processes evaluating at once at the limit: both wait on the history's lock, which this
   process holds until both are waiting (or 60 s pass); one rotates, both records are kept *)
let test_concurrent () =
  let cache, _, _, _ = build "concurrent" in
  let file = path cache in
  let old = read file in
  let limit = String.length old + 1 in
  let lock = Unix.openfile (file ^ ".lock") [ Unix.O_RDWR; Unix.O_CLOEXEC ] 0 in
  Unix.lockf lock Unix.F_LOCK 0;
  let child k =
    let env =
      Array.append
        [| Printf.sprintf "JACQUARD_TEST_HISTORY_CHILD=%s %d %d" cache limit k |]
        (Unix.environment ())
    in
    Unix.create_process_env Sys.executable_name [| Sys.executable_name |] env Unix.stdin Unix.stdout
      Unix.stderr
  in
  let pids = [ child 9; child 10 ] in
  let ino = (Unix.fstat lock).Unix.st_ino in
  let deadline = Unix.gettimeofday () +. 60. in
  while waiting ino < 2 && Unix.gettimeofday () < deadline do
    Unix.sleepf 0.05
  done;
  Unix.close lock;
  let codes =
    List.map
      (fun pid ->
        match Unix.waitpid [] pid with _, Unix.WEXITED c -> c | _ -> Alcotest.fail "child died")
      pids
  in
  Alcotest.(check (list int)) "one rotation, one plain append" [ 0; 10 ] (List.sort compare codes);
  Alcotest.(check string) ".1 holds the old bytes" old (read (file ^ ".1"));
  Alcotest.(check bool) "no .2" false (exists (file ^ ".2"));
  let rs = records (read file) in
  let key k = M.key (resolved (prepared "concurrent-key" k)).M.dependency in
  Alcotest.(check int) "three seeded and two new records" 5 (List.length rs);
  Alcotest.(check bool)
    "both new records" true
    (List.exists (fun r -> Hash.equal r.H.key (key 9)) rs
    && List.exists (fun r -> Hash.equal r.H.key (key 10)) rs)

(* two successive rotations: [.1] keeps the first history, [.2] the second *)
let test_successive () =
  let cache, _, _, _ = build "successive" in
  let file = path cache in
  let first = read file in
  ignore (rotated (appended ~limit:(String.length first + 1) cache (prepared "successive-4" 4)));
  ignore (appended cache (prepared "successive-5" 5));
  let second = read file in
  ignore (rotated (appended ~limit:(String.length second + 1) cache (prepared "successive-6" 6)));
  Alcotest.(check string) ".1 still holds the first history" first (read (file ^ ".1"));
  Alcotest.(check string) ".2 holds the second" second (read (file ^ ".2"));
  Alcotest.(check bool) "no .3" false (exists (file ^ ".3"))

(* when the records explain reports from and the new one exceed the limit, the new history keeps
   the records explain reports from after the append; when even those exceed it, none *)
let test_smaller_seeds () =
  let cache = D.fresh_dir "fallback-cache" in
  let p3 = prepared "fallback-3" 3 and p2 = prepared "fallback-2" 2 in
  ignore (appended cache p3);
  ignore (appended cache p2);
  prune_assumption cache;
  ignore (appended cache (prepared ~a:"(3)" "fallback-2r" 2));
  let file = path cache in
  let old = read file in
  let olds = records old in
  Alcotest.(check int) "three records, all read by explain" 3 (List.length olds);
  let p4 = prepared "fallback-4" 4 in
  ignore (rotated (appended ~limit:(String.length old) cache p4));
  let now = read file in
  let rs = records now in
  Alcotest.(check int) "the latest record and the new one" 2 (List.length rs);
  Alcotest.(check bool) "the latest record" true (List.hd rs = last olds);
  let views = [ p4; p3 ] in
  let after = explained cache views in
  write file (old ^ frame (last rs));
  Alcotest.(check bool) "explain is unchanged" true (after = explained cache views);
  (* one record, and a limit it alone fills: no seed *)
  let cache = D.fresh_dir "unseeded-cache" in
  ignore (appended cache p3);
  let file = path cache in
  let old = read file in
  let note = rotated (appended ~limit:(String.length old) cache p4) in
  Alcotest.(check bool) "unseeded" true (contains note "a new history was started");
  Alcotest.(check int) "only the new record" 1 (List.length (records (read file)));
  Alcotest.(check string) ".1 holds the old bytes" old (read (file ^ ".1"))

(* a history that cannot be moved aside (here, no number is left after the largest) is left as it
   is, and the failure says to move it aside by hand *)
let test_cannot_move () =
  let cache, _, _, _ = build "cannot-move" in
  let file = path cache in
  let full = Printf.sprintf "%s.%d" file max_int in
  write full "taken";
  let old = read file in
  let entries () = List.sort compare (Array.to_list (Sys.readdir (Filename.dirname file))) in
  let before = entries () in
  (match append ~limit:(String.length old + 1) cache (prepared "cannot-move-4" 4) with
  | Error { Model_eval.next_step = Some step; _ } ->
      Alcotest.(check bool)
        "says to move it aside" true
        (contains step "Move that history file aside")
  | _ -> Alcotest.fail "expected a failure with a next step");
  Alcotest.(check string) "the history is unchanged" old (read file);
  Alcotest.(check (list string)) "no new entry" before (entries ())

let suite =
  [
    Alcotest.test_case "rotation under a new key" `Quick test_rotation_new_key;
    Alcotest.test_case "rotation under a refresh" `Quick test_rotation_refresh;
    Alcotest.test_case "rotation numbering" `Quick test_numbering;
    Alcotest.test_case "an interrupted rotation" `Quick test_interrupted;
    Alcotest.test_case "an oversized history" `Quick test_oversized;
    Alcotest.test_case "a damaged history at the limit" `Quick test_damaged;
    Alcotest.test_case "concurrent rotation" `Quick test_concurrent;
    Alcotest.test_case "successive rotations" `Quick test_successive;
    Alcotest.test_case "smaller seeds" `Quick test_smaller_seeds;
    Alcotest.test_case "a history that cannot be moved" `Quick test_cannot_move;
  ]
