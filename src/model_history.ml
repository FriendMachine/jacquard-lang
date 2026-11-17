(* MODEL.1 history, snapshots and explanations (docs/designs/model-dependencies.md §3.5). *)

let ( let* ) = Result.bind
let hex = Hash.to_hex

let document_identity file =
  let path =
    try Unix.realpath file
    with Unix.Unix_error _ ->
      if Filename.is_relative file then Filename.concat (Sys.getcwd ()) file else file
  in
  Hash.of_string ("jacquard-model-document-v1\000" ^ path)

type binding = { kind : string; name : string; snapshot : Hash.t option }

type record = {
  time : string;
  entry_name : string;
  entry_closure : Hash.t option;
  key : Hash.t;
  previous : Hash.t option;
  outcome : string;
  source : Hash.t;
  interface : Hash.t;
  policy_snapshot : Hash.t;
  bindings : binding list;
  dependency : Model_doc.dependency;
}

let header = "jacquard-model-history format=1"
let opt_hex = function Some h -> hex h | None -> "none"

let serialize_record r =
  let buf = Buffer.create 512 in
  let line fmt = Printf.ksprintf (fun s -> Buffer.add_string buf (s ^ "\n")) fmt in
  line "%s" header;
  line "time %s" r.time;
  line "entry-name %s" r.entry_name;
  (* records written before closures existed have no entry-closure line, and still parse *)
  Option.iter (fun h -> line "entry-closure %s" (hex h)) r.entry_closure;
  line "key %s" (hex r.key);
  line "previous %s" (opt_hex r.previous);
  line "outcome %s" r.outcome;
  line "source %s interface %s" (hex r.source) (hex r.interface);
  line "policy-snapshot %s" (hex r.policy_snapshot);
  line "bindings %d" (List.length r.bindings);
  List.iteri
    (fun i b -> line "binding %d %s %s snapshot %s" i b.kind b.name (opt_hex b.snapshot))
    r.bindings;
  Buffer.add_string buf (Model_doc.serialize_dependency r.dependency);
  Buffer.contents buf

let natural s =
  if s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s && (s = "0" || s.[0] <> '0') then
    int_of_string_opt s
  else None

let parse_record bytes =
  let fail fmt = Printf.ksprintf (fun m -> Error m) fmt in
  let hash s = match Hash.of_canonical_hex s with Some h -> Ok h | None -> fail "bad hash" in
  let opt s = if s = "none" then Ok None else Result.map Option.some (hash s) in
  let lines = String.split_on_char '\n' bytes in
  let after prefix l =
    if String.starts_with ~prefix l then
      Ok (String.sub l (String.length prefix) (String.length l - String.length prefix))
    else fail "expected %S" prefix
  in
  let closure, lines =
    match lines with
    | h :: t :: e :: c :: rest when String.starts_with ~prefix:"entry-closure " c ->
        (Some c, h :: t :: e :: rest)
    | _ -> (None, lines)
  in
  match lines with
  | h :: time :: entry :: key :: previous :: outcome :: provenance :: policy :: count :: rest
    when h = header ->
      let* time = after "time " time in
      let* entry_name = after "entry-name " entry in
      let* entry_closure =
        match closure with
        | None -> Ok None
        | Some c ->
            Result.bind (after "entry-closure " c) (fun s -> Result.map Option.some (hash s))
      in
      let* key = Result.bind (after "key " key) hash in
      let* previous = Result.bind (after "previous " previous) opt in
      let* outcome = after "outcome " outcome in
      let* source, interface =
        match String.split_on_char ' ' provenance with
        | [ "source"; s; "interface"; i ] ->
            let* s = hash s in
            let* i = hash i in
            Ok (s, i)
        | _ -> fail "bad provenance line"
      in
      let* policy_snapshot = Result.bind (after "policy-snapshot " policy) hash in
      let* n =
        Result.bind (after "bindings " count) (fun s ->
            Option.to_result ~none:"bad count" (natural s))
      in
      if List.length rest < n then fail "missing bindings"
      else
        let binding_lines = List.filteri (fun i _ -> i < n) rest in
        let* bindings =
          List.fold_right
            (fun (i, l) acc ->
              let* acc = acc in
              match String.split_on_char ' ' l with
              | [ "binding"; j; kind; name; "snapshot"; s ] when j = string_of_int i ->
                  let* snapshot = opt s in
                  Ok ({ kind; name; snapshot } :: acc)
              | _ -> fail "bad binding line")
            (List.mapi (fun i l -> (i, l)) binding_lines)
            (Ok [])
        in
        let dependency_text = String.concat "\n" (List.filteri (fun i _ -> i >= n) rest) in
        let* dependency = Model_doc.parse_dependency dependency_text in
        let r =
          {
            time;
            entry_name;
            entry_closure;
            key;
            previous;
            outcome;
            source;
            interface;
            policy_snapshot;
            bindings;
            dependency;
          }
        in
        let consistent (b : binding) (a : Model_doc.argument_identity) =
          match (b.kind, a) with
          | ("assumption" | "inline"), Model_doc.Assumption _ -> b.snapshot <> None
          | "input", Model_doc.Input h -> (
              match b.snapshot with Some s -> Hash.equal s h | None -> false)
          | "term", Model_doc.Term _ -> true
          | _ -> false
        in
        if serialize_record r <> bytes then fail "noncanonical record"
        else if not (Hash.equal key (Model_doc.key dependency)) then
          fail "the record's key does not match its dependency record"
        else if
          List.length bindings <> List.length dependency.Model_doc.arguments
          || not (List.for_all2 consistent bindings dependency.Model_doc.arguments)
        then fail "the record's bindings do not match its arguments"
        else Ok r
  | _ -> fail "not a history record"

(* the records before the first bad frame, and that frame's offset and the reason *)
let parse_prefix bytes =
  let n = String.length bytes in
  let rec go pos acc =
    let stop reason = (List.rev acc, Some (pos, reason)) in
    if pos = n then (List.rev acc, None)
    else
      match String.index_from_opt bytes pos '\n' with
      | None -> stop "truncated frame"
      | Some j -> (
          let l = String.sub bytes pos (j - pos) in
          match String.split_on_char '=' l with
          | [ "entry bytes"; k ] -> (
              match natural k with
              | Some k when k < n - j - 1 && bytes.[j + 1 + k] = '\n' -> (
                  match parse_record (String.sub bytes (j + 1) k) with
                  | Ok r -> go (j + 2 + k) (r :: acc)
                  | Error reason -> stop reason)
              | _ -> stop "bad frame length")
          | _ -> stop "bad frame")
  in
  go 0 []

let parse_history bytes =
  match parse_prefix bytes with records, None -> Ok records | _, Some (_, reason) -> Error reason

(* a history longer than this is not read; a snapshot or retained body larger than this is not
   retained *)
let history_limit = 64 * 1024 * 1024
let retention_limit = 16 * 1024 * 1024

let history_path ~cache ~document name =
  Filename.concat (Filename.concat (Filename.concat cache "history") (hex document)) name

let snapshot_path ~cache h = Filename.concat (Filename.concat cache "snapshots") (hex h)

(* another format version: the marker followed by a complete version line other than 1 *)
let other_format bytes =
  let marker = "\njacquard-model-history format=" in
  let m = String.length marker and n = String.length bytes in
  let rec scan i =
    if i + m > n then false
    else if String.sub bytes i m = marker then
      match String.index_from_opt bytes (i + m) '\n' with
      | Some e ->
          let v = String.sub bytes (i + m) (e - i - m) in
          (v <> "1" && v <> "" && String.for_all (fun c -> c >= '0' && c <= '9') v) || scan (i + 1)
      | None -> false
    else scan (i + 1)
  in
  scan 0

(* explain never writes: each reason says what the user, or the next evaluation, can do *)
let read_history ~cache ~document name =
  match Model_eval.read_private ~limit:history_limit (history_path ~cache ~document name) with
  | Error `Absent -> Ok []
  | Error (`Too_large limit) ->
      Error
        (Printf.sprintf "larger than %d bytes; move it aside to start a new history for this result"
           limit)
  | Error (`Unreadable reason) -> Error reason
  | Ok bytes -> (
      match parse_history bytes with
      | Ok records -> Ok records
      | Error _ when other_format bytes ->
          Error "it holds a record of another format; it is left as it is"
      | Error reason -> Error (reason ^ "; the next model eval keeps every record before the damage")
      )

let read_snapshot ~cache h =
  match Model_eval.read_private ~limit:retention_limit (snapshot_path ~cache h) with
  | Ok bytes when Hash.equal (Hash.of_string bytes) h -> Some bytes
  | _ -> None

(* snapshots this process wrote or found intact, by path, with the file's identity then: one that
   is still the same file is not read and hashed again *)
let intact : (string, int * int * float) Hashtbl.t = Hashtbl.create 256

let file_stamp path =
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_REG; st_ino; st_size; st_mtime; _ } -> Some (st_ino, st_size, st_mtime)
  | _ -> None
  | exception Unix.Unix_error _ -> None

let remember path = Option.iter (Hashtbl.replace intact path) (file_stamp path)

let snapshot_present ~cache h =
  let path = snapshot_path ~cache h in
  match file_stamp path with
  | None -> false
  | Some stamp when Hashtbl.find_opt intact path = Some stamp -> true
  | Some _ ->
      read_snapshot ~cache h <> None
      &&
      (remember path;
       true)

let now () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (t.Unix.tm_year + 1900) (t.Unix.tm_mon + 1)
    t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let write_snapshot ~cache content =
  let h = Hash.of_string content in
  let path = snapshot_path ~cache h in
  (* an existing snapshot is kept only when it still holds its content *)
  if snapshot_present ~cache h then Ok h
  else
    Result.map
      (fun () ->
        remember path;
        h)
      (Model_eval.write_atomic path content)

(* the path must not be a symbolic link or anything but a regular file, before and after the open *)
let not_regular path =
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_REG; _ } -> false
  | _ -> true
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> false

let same_file fd path =
  match (Unix.fstat fd, Unix.lstat path) with
  | a, b ->
      a.Unix.st_kind = Unix.S_REG && a.Unix.st_dev = b.Unix.st_dev && a.Unix.st_ino = b.Unix.st_ino

let append_frame path bytes =
  try
    if not_regular path then Error (path ^ ": not a regular file")
    else
      let fd =
        Unix.openfile path [ Unix.O_WRONLY; Unix.O_APPEND; Unix.O_CREAT; Unix.O_CLOEXEC ] 0o600
      in
      Fun.protect
        ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
        (fun () ->
          if not (same_file fd path) then Error (path ^ ": replaced while it was opened")
          else (
            (* a history another tool left readable by others is made owner-only *)
            if (Unix.fstat fd).Unix.st_perm land 0o077 <> 0 then Unix.fchmod fd 0o600;
            let frame = Printf.sprintf "entry bytes=%d\n%s\n" (String.length bytes) bytes in
            let b = Bytes.unsafe_of_string frame in
            let rec go off =
              if off < Bytes.length b then go (off + Unix.write fd b off (Bytes.length b - off))
            in
            go 0;
            Unix.fsync fd;
            Ok ()))
  with (Unix.Unix_error _ | Sys_error _) as e -> Error (Printexc.to_string e)

let failure reason = { Model_eval.reason; next_step = None }
let plain r = Result.map_error failure r

(* one writer at a time per history: the read, the decision and the write happen under an
   exclusive lock on a sibling lock file *)
let with_lock path f =
  let lock = path ^ ".lock" in
  match
    if not_regular lock then Error (lock ^ ": not a regular file")
    else Ok (Unix.openfile lock [ Unix.O_RDWR; Unix.O_CREAT; Unix.O_CLOEXEC ] 0o600)
  with
  | exception ((Unix.Unix_error _ | Sys_error _) as e) -> Error (failure (Printexc.to_string e))
  | Error reason -> Error (failure reason)
  | Ok fd ->
      Fun.protect
        ~finally:(fun () -> try Unix.close fd with Unix.Unix_error _ -> ())
        (fun () ->
          match Unix.lockf fd Unix.F_LOCK 0 with
          | exception Unix.Unix_error (e, _, _) -> Error (failure (Unix.error_message e))
          | () -> f ())

let kind_text = function
  | Resolve.KTerm -> "term"
  | Resolve.KCon -> "con"
  | Resolve.KOp -> "op"
  | Resolve.KType -> "type"
  | Resolve.KEffect -> "effect"

(* the owner and name tables of one store state, and the manifests computed against it: a store
   whose index and names are the very same lists is the same state, so model eval and explain
   resolve owners once and compute each closure once per process *)
type closure_tables = {
  owner : (string, Hash.t) Hashtbl.t;  (** any hash -> its declaration *)
  names : (string, string * string) Hashtbl.t;  (** declaration -> (name, kind), every binding *)
  manifests : (string, string * (Hash.t * string) list) Hashtbl.t;  (** root -> closure *)
}

let closure_memo :
    (Store.t
    * (Hash.t * (Hash.t * Store.role)) list
    * (string * Resolve.entry) list
    * closure_tables)
    option
    ref =
  ref None

let closure_tables (store : Store.t) =
  match !closure_memo with
  | Some (s, index, names, t)
    when s == store && index == store.Store.index && names == Store.names store ->
      t
  | _ ->
      let owner = Hashtbl.create 256 in
      List.iter (fun (h, (d, _)) -> Hashtbl.replace owner (hex h) d) store.Store.index;
      let names = Hashtbl.create 256 in
      List.iter
        (fun (name, (e : Resolve.entry)) ->
          match Hashtbl.find_opt owner (hex e.Resolve.hash) with
          | Some d -> Hashtbl.add names (hex d) (name, kind_text e.Resolve.kind)
          | None -> ())
        (Store.names store);
      let t = { owner; names; manifests = Hashtbl.create 16 } in
      closure_memo := Some (store, store.Store.index, Store.names store, t);
      t

(* the closure manifest of a term: every stored declaration it reaches, one line per (name, kind)
   bound to a member of it, or one unnamed line, each with a snapshot of its stored bytes ("none"
   when they cannot be read or exceed the retention limit), sorted; and the bodies to retain, with
   their hashes. A stored declaration that cannot be loaded is listed with body "none" (its own
   references are not followed); a reference that is not a stored declaration (a builtin) is not
   listed. *)
let closure ~(store : Store.t) root =
  let t = closure_tables store in
  match Hashtbl.find_opt t.manifests (hex root) with
  | Some m -> m
  | None ->
      let seen = Hashtbl.create 64 in
      let refs_of d =
        match Store.locate_internal store d with
        | Ok l -> Store.decl_refs l.Store.decl
        | Error _ -> []
      in
      let rec visit acc h =
        let known = Hashtbl.find_opt t.owner (hex h) in
        let d = match known with Some d -> d | None -> h in
        if Hashtbl.mem seen (hex d) then acc
        else (
          Hashtbl.add seen (hex d) ();
          match known with
          | None -> acc
          | Some _ ->
              (* the stored bytes are read once: retained, hashed, and parsed for references *)
              let path = Store.object_path store d in
              let body, refs =
                match Model_doc.read_bounded ~limit:retention_limit path with
                | Ok bytes -> (
                    match Store.load_object ~file:path bytes with
                    | Ok (decl, _) -> (Some bytes, Store.decl_refs decl)
                    | Error _ -> (Some bytes, refs_of d))
                | Error _ -> (None, refs_of d)
              in
              List.fold_left visit ((d, body) :: acc) refs)
      in
      let bodies =
        List.map
          (fun (d, body) -> (d, Option.map (fun b -> (Hash.of_string b, b)) body))
          (visit [] root)
      in
      let lines =
        List.concat_map
          (fun (d, body) ->
            let b = match body with Some (h, _) -> hex h | None -> "none" in
            match Hashtbl.find_all t.names (hex d) with
            | [] -> [ Printf.sprintf "- - %s %s" (hex d) b ]
            | ns -> List.map (fun (n, k) -> Printf.sprintf "%s %s %s %s" n k (hex d) b) ns)
          bodies
        |> List.sort_uniq compare
      in
      let root_decl = match Hashtbl.find_opt t.owner (hex root) with Some d -> d | None -> root in
      let m =
        ( "jacquard-model-closure format=1\nroot " ^ hex root_decl ^ "\n"
          ^ String.concat "" (List.map (fun l -> l ^ "\n") lines),
          List.filter_map snd bodies )
      in
      Hashtbl.replace t.manifests (hex root) m;
      m

(* a manifest: its root declaration, and ((name, kind), decl, body) per line, unnamed lines with
   name and kind "-"; [None] unless every line is well formed *)
let parse_closure text =
  let is_hash s = Option.is_some (Hash.of_canonical_hex s) in
  let kinds = [ "term"; "con"; "op"; "type"; "effect" ] in
  match String.split_on_char '\n' text with
  | "jacquard-model-closure format=1" :: r :: rest
    when String.starts_with ~prefix:"root " r && is_hash (String.sub r 5 (String.length r - 5)) ->
      let rec lines acc = function
        | [ "" ] -> Some (String.sub r 5 (String.length r - 5), List.rev acc)
        | l :: rest -> (
            match String.split_on_char ' ' l with
            | [ n; k; d; b ]
              when ((n = "-" && k = "-") || (n <> "-" && n <> "" && List.mem k kinds))
                   && is_hash d
                   && (b = "none" || is_hash b) ->
                lines (((n, k), d, b) :: acc) rest
            | _ -> None)
        | [] -> None
      in
      lines [] rest
  | _ -> None

(* the stored declarations of a manifest whose bodies were never retained because they are larger
   than the retention limit, by name, judged from the current store *)
let oversized ~(store : Store.t) text =
  match parse_closure text with
  | None -> []
  | Some (_, lines) ->
      List.filter_map
        (fun ((n, _), d, b) ->
          if b <> "none" then None
          else
            match Hash.of_canonical_hex d with
            | None -> None
            | Some d -> (
                match Unix.stat (Store.object_path store d) with
                | { Unix.st_size; _ } when st_size > retention_limit ->
                    Some (if n = "-" then "#" ^ String.sub (hex d) 0 12 else n)
                | _ -> None
                | exception Unix.Unix_error _ -> None))
        lines
      |> List.sort_uniq compare

let append ~cache ~document (prepared : Model_doc.prepared) (r : Model_doc.resolved) ~outcome =
  let name = r.Model_doc.decl.Model_doc.r_name in
  let path = history_path ~cache ~document name in
  let* () = plain (Model_eval.private_dirs ~root:cache [ "history"; hex document ]) in
  let* () = plain (Model_eval.private_dirs ~root:cache [ "snapshots" ]) in
  with_lock path @@ fun () ->
  let key = Model_doc.key r.Model_doc.dependency in
  (* a damaged history keeps every record before the damage; an unreadable one, one too large to
     read, and one holding another format are left alone *)
  let* history, damage =
    match Model_eval.read_private ~limit:history_limit path with
    | Error `Absent -> Ok ([], None)
    | Error (`Too_large limit) ->
        Error
          {
            Model_eval.reason =
              Printf.sprintf "the history %s is larger than %d bytes, so it is not extended" path
                limit;
            next_step =
              Some
                "Move that history file aside to start a new history for this result; the moved \
                 file keeps every earlier record, and the result itself is unaffected.";
          }
    | Error (`Unreadable reason) -> Error (failure reason)
    | Ok bytes -> (
        match parse_prefix bytes with
        | records, None -> Ok (records, None)
        | _, Some _ when other_format bytes ->
            Error
              {
                Model_eval.reason =
                  "the history holds a record of another format; it was left untouched";
                next_step =
                  Some
                    "Evaluate with the Jacquard version that wrote it, or move the history file \
                     aside to start a new one; the result itself is unaffected.";
              }
        | records, Some (offset, reason) -> Ok (records, Some (String.sub bytes 0 offset, reason)))
  in
  (* snapshots are written, or repaired, on every evaluation, so pruning them never sticks *)
  let* bindings =
    List.fold_right
      (fun (b : Model_doc.binding) acc ->
        let* acc = acc in
        let* snapshot =
          match b.Model_doc.b_content with
          | None -> Ok None
          | Some c -> Result.map Option.some (plain (write_snapshot ~cache c))
        in
        Ok ({ kind = b.Model_doc.b_kind; name = b.Model_doc.b_name; snapshot } :: acc))
      r.Model_doc.bindings (Ok [])
  in
  let* policy_snapshot =
    plain (write_snapshot ~cache (Observation_policy.serialize prepared.Model_doc.policy))
  in
  (* the entry's and each term argument's closure: bodies and manifest, retained *)
  let write_closure h =
    let text, bodies = closure ~store:prepared.Model_doc.store h in
    let* () =
      List.fold_left
        (fun acc (_, body) ->
          let* () = acc in
          Result.map ignore (plain (write_snapshot ~cache body)))
        (Ok ()) bodies
    in
    plain (write_snapshot ~cache text)
  in
  let* entry_closure = write_closure r.Model_doc.dependency.Model_doc.entry in
  let* bindings =
    List.fold_right2
      (fun b a acc ->
        let* acc = acc in
        match a with
        | Model_doc.Term { term; _ } ->
            let* m = write_closure term in
            Ok ({ b with snapshot = Some m } :: acc)
        | _ -> Ok (b :: acc))
      bindings r.Model_doc.dependency.Model_doc.arguments (Ok [])
  in
  let note =
    Option.map
      (fun (_, reason) ->
        Printf.sprintf "the history was damaged (%s); its %d earlier record(s) were kept" reason
          (List.length history))
      damage
  in
  let latest = match List.rev history with r :: _ -> Some r | [] -> None in
  let frame bytes = Printf.sprintf "entry bytes=%d\n%s\n" (String.length bytes) bytes in
  (* the latest record still names a snapshot that is gone (an equal respelling of an
     assumption keeps the key but changes its text): refresh it with a record naming the
     current snapshots *)
  let bodies_missing h =
    match read_snapshot ~cache h with
    | None -> true
    | Some text -> (
        match parse_closure text with
        | None -> true
        | Some (_, lines) ->
            List.exists
              (fun (_, _, b) ->
                b = "none"
                ||
                match Hash.of_canonical_hex b with
                | Some h -> not (snapshot_present ~cache h)
                | None -> true)
              lines)
  in
  let stale_refs (l : record) =
    List.exists
      (fun b -> match b.snapshot with Some h -> not (snapshot_present ~cache h) | None -> false)
      l.bindings
    || (not (snapshot_present ~cache l.policy_snapshot))
    || (match l.entry_closure with Some h -> bodies_missing h | None -> true)
    (* a term argument's manifest whose retained bodies are gone also needs a refresh *)
    || List.exists
         (fun b ->
           match (b.kind, b.snapshot) with "term", Some h -> bodies_missing h | _ -> false)
         l.bindings
  in
  match latest with
  | Some l
    when Hash.equal l.key key
         && ((not (stale_refs l))
            (* a refresh can only help when it would name other snapshots: a body that cannot be
               retained at all stays [none] in the current manifest too *)
            || l.bindings = bindings
               && Hash.equal l.policy_snapshot policy_snapshot
               && l.entry_closure = Some entry_closure) -> (
      match damage with
      | None -> Ok None
      | Some (kept, _) -> Result.map (fun () -> note) (plain (Model_eval.write_atomic path kept)))
  | _ -> (
      let record =
        {
          time = now ();
          entry_name = r.Model_doc.decl.Model_doc.r_entry;
          entry_closure = Some entry_closure;
          key;
          previous = Option.map (fun l -> l.key) latest;
          outcome;
          source = Frontend.Checked.source_digest prepared.Model_doc.artifact;
          interface = Interface.identity (Frontend.Checked.interface prepared.Model_doc.artifact);
          policy_snapshot;
          bindings;
          dependency = r.Model_doc.dependency;
        }
      in
      let bytes = serialize_record record in
      match damage with
      | Some (kept, _) ->
          Result.map (fun () -> note) (plain (Model_eval.write_atomic path (kept ^ frame bytes)))
      | None -> Result.map (fun () -> None) (plain (append_frame path bytes)))

(* --- explanations --- *)

type change = {
  component : string;
  subject : string option;
  before : string option;
  after : string option;
  names : (string * string) list;
  diff : string list;
}

type freshness =
  | Current
  | Unknown of string list
  | Stale of change list
  | Never_evaluated
  | Unavailable of string

type explanation = {
  result : string;
  evaluated_at : string option;
  outcome : string option;
  previous : Hash.t option;
  missing : string list;
  notes : string list;
  freshness : freshness;
  transition : (string * change list) option;
  transition_missing : string list;
}

(* one side of a comparison: a record, or the document as it is now *)
type side = {
  entry : string;
  entry_closure : Hash.t option;
  dep : Model_doc.dependency;
  binds : binding list;
  content : Hash.t -> string option;
}

let driver_text (d : Model_doc.dependency) =
  match d.Model_doc.driver with
  | Model_doc.Run -> "run"
  | Model_doc.Enumerate { max_branches } -> Printf.sprintf "enumerate max-branches=%d" max_branches
  | Model_doc.Lw { seed; samples } -> Printf.sprintf "lw seed=%d samples=%d" seed samples

let shown content = function
  | None -> "(unavailable)"
  | Some h -> ( match content h with Some text -> text | None -> "(unavailable)")

let byte_count content = function
  | None -> "(unavailable)"
  | Some h -> (
      match content h with
      | Some bytes -> Printf.sprintf "%d bytes" (String.length bytes)
      | None -> "(unavailable)")

let surface_kind = function
  | "term" -> Some Surface_name.Term
  | "con" -> Some Surface_name.Con
  | "op" -> Some Surface_name.Op
  | "type" -> Some Surface_name.Type
  | "effect" -> Some Surface_name.Effect
  | _ -> None

(* "term add, int.add" or "type Wrap, con W": each name as the surface spells it, after its kind
   whenever the kind changes *)
let names_text names =
  let rec go last = function
    | [] -> []
    | (kind, name) :: rest ->
        let shown =
          match surface_kind kind with Some k -> Surface_name.render k name | None -> name
        in
        (if Some kind = last then shown else kind ^ " " ^ shown) :: go (Some kind) rest
  in
  String.concat ", " (go None names)

(* the readable [jacquard diff] of two retained bodies of one declaration, without its heading;
   empty when either body is not the declaration its manifest names *)
let body_diff ~(store : Store.t) ~label (old_decl, old_body) (new_decl, new_body) =
  let load decl body =
    match Store.load_object ~file:"(retained declaration)" body with
    | Ok (d, hashes) when hex hashes.Canon.decl_hash = decl -> Some (d, hashes)
    | _ -> None
  in
  match (load old_decl old_body, load new_decl new_body) with
  | Some ((od, _) as o), Some ((nd, _) as n) -> (
      let effect_name_of h =
        Option.value ~default:"unregistered"
          (List.find_map
             (fun (name, (e : Resolve.entry)) ->
               if e.Resolve.kind = Resolve.KEffect && Hash.equal e.Resolve.hash h then Some name
               else None)
             (Store.names store))
      in
      let divergences =
        Diff.form_divergences ~syntax:Diff.Surface ~effect_name_of ~path:label
          (Kernel.decl_to_form od) (Kernel.decl_to_form nd)
      in
      (* each side names its own members first, then whatever the current store names *)
      match
        Diff.render_readable ~old_side:(Diff.source_side store [ o ])
          ~new_side:(Diff.source_side store [ n ])
          [ (label, Diff.Changed { divergences; dependents = []; origin = None }) ]
      with
      | Some text -> ( match String.split_on_char '\n' text with _ :: rest -> rest | [] -> [])
      | None -> [])
  | _ -> []

let differences ~store old_ now_ =
  let change ?subject ?before ?after ?(names = []) ?(diff = []) component =
    { component; subject; before; after; names; diff }
  in
  (* the named declarations that differ between two closure manifests, the root's own declaration
     aside; names bound to the same declarations on both sides (a declaration's aliases, and the
     members of a group or type) are one change, with the diff of their retained bodies *)
  let callees old_c new_c =
    let manifest side = function
      | None -> None
      | Some h -> Option.bind (side.content h) parse_closure
    in
    match (manifest old_ old_c, manifest now_ new_c) with
    | Some (old_root, o), Some (new_root, n) ->
        (* the root's own declaration, with its group siblings, is the change itself; it is
           found by identity, so a same-named declaration of another kind is still followed *)
        let roots = [ old_root; new_root ] in
        let table m =
          let t = Hashtbl.create 64 in
          List.iter
            (fun (((name, _) as key), d, b) ->
              if name <> "-" then
                Hashtbl.replace t key ((d, b) :: Option.value (Hashtbl.find_opt t key) ~default:[]))
            m;
          t
        in
        let ot = table o and nt = table n in
        let decls t key =
          List.sort_uniq compare (Option.value (Hashtbl.find_opt t key) ~default:[])
        in
        let keys =
          List.sort_uniq compare
            (Hashtbl.fold
               (fun k _ acc -> k :: acc)
               ot
               (Hashtbl.fold (fun k _ acc -> k :: acc) nt []))
        in
        let changed =
          List.filter_map
            (fun key ->
              let a = decls ot key and b = decls nt key in
              if List.exists (fun (d, _) -> List.mem d roots) (a @ b) then None
              else if List.map fst a = List.map fst b then None
              else Some (key, a, b))
            keys
        in
        let groups = Hashtbl.create 16 in
        let order =
          List.fold_left
            (fun order (key, a, b) ->
              let g = (List.map fst a, List.map fst b) in
              match Hashtbl.find_opt groups g with
              | Some (ks, a, b) ->
                  Hashtbl.replace groups g (key :: ks, a, b);
                  order
              | None ->
                  Hashtbl.replace groups g ([ key ], a, b);
                  g :: order)
            [] changed
          |> List.rev
        in
        List.map
          (fun g ->
            let keys, a, b = Hashtbl.find groups g in
            let names = List.rev_map (fun (name, kind) -> (kind, name)) keys in
            (* the JSON subject stays the plain names; text spells them with their kinds *)
            let subject = String.concat ", " (List.map snd names) in
            let body side (d, b) =
              Option.bind (Hash.of_canonical_hex b) (fun h ->
                  Option.map (fun text -> (d, text)) (side.content h))
            in
            match (a, b) with
            | [], _ -> change ~subject ~after:"added" ~names "callee"
            | _, [] -> change ~subject ~after:"removed" ~names "callee"
            | [ x ], [ y ] ->
                let diff =
                  match (body old_ x, body now_ y) with
                  | Some x, Some y -> body_diff ~store ~label:(names_text names) x y
                  | _ -> []
                in
                change ~subject ~names ~diff "callee"
            | _ -> change ~subject ~names "callee")
          order
    | _ -> []
  in
  let o = old_.dep and n = now_.dep in
  let some c b = if c then [ b ] else [] in
  let entry =
    some
      ((not (Hash.equal o.Model_doc.entry n.Model_doc.entry)) || old_.entry <> now_.entry)
      (if old_.entry <> now_.entry then change ~before:old_.entry ~after:now_.entry "entry"
       else change ~subject:now_.entry "entry")
    @
    if Hash.equal o.Model_doc.entry n.Model_doc.entry then []
    else callees old_.entry_closure now_.entry_closure
  in
  let fixed =
    some
      (not (Hash.equal o.Model_doc.signature n.Model_doc.signature))
      (change ~subject:now_.entry "signature")
    @ some (o.Model_doc.labels <> n.Model_doc.labels) (change ~subject:now_.entry "labels")
    @ some (o.Model_doc.prelude <> n.Model_doc.prelude) (change "prelude")
    @ some
        (o.Model_doc.core <> n.Model_doc.core)
        (change ~before:o.Model_doc.core ~after:n.Model_doc.core "core")
    @ some
        (driver_text o <> driver_text n)
        (change ~before:(driver_text o) ~after:(driver_text n) "driver")
    @ some
        (o.Model_doc.fuel <> n.Model_doc.fuel)
        (change ~before:(string_of_int o.Model_doc.fuel) ~after:(string_of_int n.Model_doc.fuel)
           "fuel")
    @ some (not (Hash.equal o.Model_doc.policy n.Model_doc.policy)) (change "policy")
  in
  let oa = o.Model_doc.arguments and na = n.Model_doc.arguments in
  let count =
    some
      (List.length oa <> List.length na)
      (change
         ~before:(string_of_int (List.length oa))
         ~after:(string_of_int (List.length na))
         "arguments")
  in
  let rec pairs i ob nb oi ni =
    match (ob, nb, oi, ni) with
    | b0 :: ob, b1 :: nb, i0 :: oi, i1 :: ni ->
        let here =
          if b0.kind <> b1.kind || b0.name <> b1.name then
            [
              change ~subject:(Printf.sprintf "argument %d" i)
                ~before:(b0.kind ^ " " ^ b0.name)
                ~after:(b1.kind ^ " " ^ b1.name)
                "argument";
            ]
          else if i0 = i1 then []
          else
            match b1.kind with
            | "assumption" | "inline" ->
                [
                  change ~subject:b1.name ~before:(shown old_.content b0.snapshot)
                    ~after:(shown now_.content b1.snapshot) b1.kind;
                ]
            | "input" ->
                [
                  change ~subject:b1.name
                    ~before:(byte_count old_.content b0.snapshot)
                    ~after:(byte_count now_.content b1.snapshot)
                    "input";
                ]
            | kind -> change ~subject:b1.name kind :: callees b0.snapshot b1.snapshot
        in
        here @ pairs (i + 1) ob nb oi ni
    | _ -> []
  in
  entry @ fixed @ count @ pairs 0 old_.binds now_.binds oa na

let explain ~cache ~document (prepared : Model_doc.prepared) =
  let store = prepared.Model_doc.store in
  let policy_bytes = Observation_policy.serialize prepared.Model_doc.policy in
  let one (r : Model_doc.resolved) =
    let name = r.Model_doc.decl.Model_doc.r_name in
    let entry_manifest, entry_bodies = closure ~store r.Model_doc.dependency.Model_doc.entry in
    let term_closures =
      List.map
        (function Model_doc.Term { term; _ } -> Some (closure ~store term) | _ -> None)
        r.Model_doc.dependency.Model_doc.arguments
    in
    let term_manifests = List.map (Option.map fst) term_closures in
    (* what the document holds now, by hash: computed once, never read back from the cache *)
    let current = Hashtbl.create 64 in
    let add text = Hashtbl.replace current (hex (Hash.of_string text)) text in
    let add_hashed (h, text) = Hashtbl.replace current (hex h) text in
    add policy_bytes;
    add entry_manifest;
    List.iter add_hashed entry_bodies;
    List.iter
      (function
        | Some (text, bodies) ->
            add text;
            List.iter add_hashed bodies
        | None -> ())
      term_closures;
    List.iter
      (fun (b : Model_doc.binding) -> Option.iter add b.Model_doc.b_content)
      r.Model_doc.bindings;
    let now_ =
      {
        entry = r.Model_doc.decl.Model_doc.r_entry;
        entry_closure = Some (Hash.of_string entry_manifest);
        dep = r.Model_doc.dependency;
        binds =
          List.map2
            (fun (b : Model_doc.binding) m ->
              {
                kind = b.Model_doc.b_kind;
                name = b.Model_doc.b_name;
                snapshot =
                  (match m with
                  | Some text -> Some (Hash.of_string text)
                  | None -> Option.map Hash.of_string b.Model_doc.b_content);
              })
            r.Model_doc.bindings term_manifests;
        content =
          (fun h ->
            match Hashtbl.find_opt current (hex h) with
            | Some c -> Some c
            | None -> read_snapshot ~cache h);
      }
    in
    let of_record (rc : record) =
      {
        entry = rc.entry_name;
        entry_closure = rc.entry_closure;
        dep = rc.dependency;
        binds = rc.bindings;
        content = read_snapshot ~cache;
      }
    in
    let empty =
      {
        result = name;
        evaluated_at = None;
        outcome = None;
        previous = None;
        missing = [];
        notes = [];
        freshness = Never_evaluated;
        transition = None;
        transition_missing = [];
      }
    in
    match read_history ~cache ~document name with
    | Error reason -> { empty with freshness = Unavailable reason }
    | Ok history -> (
        match List.rev history with
        | [] -> empty
        | latest :: earlier -> (
            (* a policy snapshot that is present must be the policy its record names *)
            let policy_mismatch (rc : record) =
              match read_snapshot ~cache rc.policy_snapshot with
              | None -> false
              | Some bytes -> (
                  match Observation_policy.parse bytes with
                  | Ok p ->
                      not
                        (Hash.equal (Observation_policy.identity p) rc.dependency.Model_doc.policy)
                  | Error _ -> true)
            in
            match List.find_opt policy_mismatch history with
            | Some _ ->
                {
                  empty with
                  evaluated_at = Some latest.time;
                  outcome = Some latest.outcome;
                  previous = latest.previous;
                  freshness = Unavailable "a record's policy snapshot is not its policy";
                }
            | None ->
                (* a dependency whose snapshot is gone is never assumed current, and is always named *)
                (* a manifest's retained bodies count as its snapshots *)
                let notes = ref [] in
                let bodies_gone what text =
                  match parse_closure text with
                  | None -> [ what ^ " declarations" ]
                  | Some (_, lines) ->
                      if
                        List.exists
                          (fun (_, _, b) ->
                            b = "none"
                            ||
                            match Hash.of_canonical_hex b with
                            | Some h -> read_snapshot ~cache h = None
                            | None -> true)
                          lines
                      then (
                        (match oversized ~store text with
                        | [] -> ()
                        | big ->
                            notes :=
                              Printf.sprintf
                                "%s declarations: %s %s stored in more than %d bytes, the \
                                 retention limit, so %s never retained"
                                what (String.concat ", " big)
                                (if List.length big = 1 then "is" else "are")
                                retention_limit
                                (if List.length big = 1 then "its body is" else "their bodies are")
                              :: !notes);
                        [ what ^ " declarations" ])
                      else []
                in
                let gone_of (rc : record) =
                  List.concat_map
                    (fun b ->
                      match b.snapshot with
                      | Some h -> (
                          match read_snapshot ~cache h with
                          | None -> [ b.kind ^ " " ^ b.name ]
                          | Some text when b.kind = "term" -> bodies_gone ("term " ^ b.name) text
                          | Some _ -> [])
                      | None -> [])
                    rc.bindings
                  @ (if read_snapshot ~cache rc.policy_snapshot = None then [ "policy" ] else [])
                  @
                  match rc.entry_closure with
                  | None -> []
                  | Some h -> (
                      match read_snapshot ~cache h with
                      | None -> [ "entry " ^ rc.entry_name ]
                      | Some text -> bodies_gone ("entry " ^ rc.entry_name) text)
                in
                let gone = gone_of latest in
                let latest_notes = List.rev !notes in
                let freshness =
                  if Hash.equal latest.key (Model_doc.key r.Model_doc.dependency) then
                    if gone = [] then Current else Unknown gone
                  else Stale (differences ~store (of_record latest) now_)
                in
                (* records refreshing the latest key are one recomputation: the transition is
                   from the last record with another key, at the run's first record *)
                let rec split run = function
                  | rc :: rest when Hash.equal rc.key latest.key -> split (rc :: run) rest
                  | rest -> (run, rest)
                in
                let run, before = split [ latest ] earlier in
                let first = List.hd run in
                let transition, transition_missing =
                  match before with
                  | prev :: _ ->
                      ( Some (first.time, differences ~store (of_record prev) (of_record latest)),
                        gone_of prev )
                  | [] -> (None, [])
                in
                (* a refresh is not a recomputation: report the run's first record *)
                {
                  result = name;
                  evaluated_at = Some first.time;
                  outcome = Some first.outcome;
                  previous = first.previous;
                  missing = gone;
                  notes = latest_notes;
                  freshness;
                  transition;
                  transition_missing;
                }))
  in
  List.map one prepared.Model_doc.resolved

let change_text c =
  let subject =
    match (c.names, c.subject) with
    | _ :: _, _ -> " " ^ names_text c.names
    | [], Some s -> " " ^ s
    | [], None -> ""
  in
  match (c.before, c.after) with
  | Some b, Some a -> Printf.sprintf "%s%s: %s -> %s" c.component subject b a
  | None, Some status -> Printf.sprintf "%s%s %s" c.component subject status
  | _ -> Printf.sprintf "%s%s changed" c.component subject

(* a change, and under it the diff of its retained bodies *)
let change_lines indent c = (indent ^ change_text c) :: List.map (fun l -> indent ^ l) c.diff

let render_text e =
  let head =
    match e.freshness with
    | Current ->
        Printf.sprintf "%s: current (evaluated %s)" e.result
          (Option.value e.evaluated_at ~default:"?")
    | Stale _ ->
        Printf.sprintf "%s: stale (last evaluated %s)" e.result
          (Option.value e.evaluated_at ~default:"?")
    | Unknown gone ->
        Printf.sprintf "%s: unknown (snapshots gone: %s)" e.result (String.concat ", " gone)
    | Never_evaluated -> Printf.sprintf "%s: never evaluated" e.result
    | Unavailable reason -> Printf.sprintf "%s: history unavailable (%s)" e.result reason
  in
  let stale =
    match e.freshness with
    | Stale cs ->
        List.concat_map (change_lines "  ") cs
        @ if e.missing = [] then [] else [ "  snapshots gone: " ^ String.concat ", " e.missing ]
    | _ -> []
  in
  let notes = List.map (fun n -> "  note: " ^ n) e.notes in
  let transition =
    match e.transition with
    | None -> []
    | Some (time, cs) ->
        (Printf.sprintf "  last change (%s):" time :: List.concat_map (change_lines "    ") cs)
        @
        if e.transition_missing = [] then []
        else [ "    snapshots gone: " ^ String.concat ", " e.transition_missing ]
  in
  (head :: stale) @ notes @ transition

let change_json c =
  let o = function Some s -> `String s | None -> `Null in
  `Assoc
    ([
       ("component", `String c.component);
       ("subject", o c.subject);
       ("before", o c.before);
       ("after", o c.after);
     ]
    @ (if c.names = [] then []
       else
         [
           ( "names",
             `List
               (List.map
                  (fun (kind, name) -> `Assoc [ ("kind", `String kind); ("name", `String name) ])
                  c.names) );
         ])
    @ if c.diff = [] then [] else [ ("diff", `List (List.map (fun l -> `String l) c.diff)) ])

let to_json es =
  let one e =
    let freshness, extra =
      match e.freshness with
      | Current -> ("current", [])
      | Stale cs -> ("stale", [ ("changes", `List (List.map change_json cs)) ])
      | Unknown _ -> ("unknown", [])
      | Never_evaluated -> ("never-evaluated", [])
      | Unavailable reason -> ("history-unavailable", [ ("reason", `String reason) ])
    in
    `Assoc
      ([
         ("name", `String e.result);
         ("freshness", `String freshness);
         ("evaluated_at", match e.evaluated_at with Some t -> `String t | None -> `Null);
         ("outcome", match e.outcome with Some o -> `String o | None -> `Null);
         ("previous", match e.previous with Some h -> `String (hex h) | None -> `Null);
         ("missing", `List (List.map (fun m -> `String m) e.missing));
       ]
      @ (if e.notes = [] then [] else [ ("notes", `List (List.map (fun n -> `String n) e.notes)) ])
      @ extra
      @ [
          ( "last_transition",
            match e.transition with
            | None -> `Null
            | Some (t, cs) ->
                `Assoc
                  [
                    ("at", `String t);
                    ("changes", `List (List.map change_json cs));
                    ("missing", `List (List.map (fun m -> `String m) e.transition_missing));
                  ] );
        ])
  in
  Yojson.Safe.to_string
    (`Assoc
       [ ("format", `String "jacquard-model-explain-v1"); ("results", `List (List.map one es)) ])
