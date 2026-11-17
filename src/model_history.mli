(** MODEL.1 evaluation history, snapshots, and explanations (docs/designs/model-dependencies.md
    §3.5).

    Under a cache directory, each document has an append-only history per result: a
    [jacquard-model-history-v1] record is appended whenever a result is evaluated under a key that
    differs from its latest record's. Each record names the dependency record, the named bindings
    with snapshot references, the source digest and interface identity, and the outcome. Snapshots
    retain assumption text, inline literals, input bytes and the policy, content-addressed by their
    HASH_V0, so a past evaluation can be explained after the document changes. *)

val document_identity : string -> Hash.t
(** [document_identity file] is HASH_V0 of the document's canonical absolute path, so documents
    sharing a cache directory never share histories. *)

type binding = { kind : string; name : string; snapshot : Hash.t option }

type record = {
  time : string;  (** UTC, [YYYY-MM-DDTHH:MM:SSZ] *)
  entry_name : string;
  entry_closure : Hash.t option;
      (** the snapshot of the entry's closure manifest ([jacquard-model-closure format=1]): a
          [root DECL] line naming the entry's own declaration, then, sorted, one
          [NAME KIND DECL BODY] line per (name, kind) bound to a member of each stored declaration
          the entry reaches, or one [- - DECL BODY] line when nothing names it. [BODY] is the
          snapshot of the declaration's stored bytes, or [none] when they cannot be read, exceed the
          16 MiB retention limit, or the declaration cannot be loaded. [None] for records written
          before closures existed, which carry no [entry-closure] line. *)
  key : Hash.t;
  previous : Hash.t option;  (** the key of the record before this one *)
  outcome : string;  (** the status and outcome tag, as [model eval] reported them *)
  source : Hash.t;  (** provenance: the source digest *)
  interface : Hash.t;  (** provenance: the source's interface-v1 identity *)
  policy_snapshot : Hash.t;
  bindings : binding list;
  dependency : Model_doc.dependency;
}

val serialize_record : record -> string
(** [serialize_record r] is the canonical bytes of one history record, without its [entry bytes=N]
    frame; {!parse_history} accepts exactly these bytes. *)

val parse_history : string -> (record list, string) result
(** [parse_history bytes] reads a whole history file, oldest record first; any malformed or
    noncanonical record, a record whose key is not its dependency record's, or whose bindings do not
    match its arguments, refuses the file. *)

val append :
  cache:string ->
  document:Hash.t ->
  Model_doc.prepared ->
  Model_doc.resolved ->
  outcome:string ->
  (string option, Model_eval.history_failure) result
(** [append ~cache ~document prepared resolved ~outcome] writes the result's snapshots (owner-only,
    atomically): each assumption's text, inline literal and input, the policy, and the closure
    manifest and declaration bodies of the entry and of each term argument. A snapshot is written
    when absent or no longer holding its content, on every call (one this process already wrote or
    verified, and that is still the same file, is not read again). A record is appended when the
    result has no history, when its latest record has another key, or, as a refresh under the same
    key, when the latest record names a snapshot that is gone and a refresh would name other
    snapshots. The read, the decision and the write hold an exclusive lock on a sibling [.lock]
    file. The [history] and [snapshots] directories are made owner-only. A cache path that is a
    symbolic link is never followed: a history or lock is refused, and a snapshot is rewritten as a
    file.

    [Ok None] is success; [Ok (Some note)] means a history with a damaged frame kept every record
    before it and was rewritten atomically, and the note says so. [Error failure] leaves the history
    untouched: it cannot be read at all, is larger than 64 MiB (the failure's next step says to move
    it aside, since histories are never compacted), holds a record of another format (the next step
    names the version that wrote it), or a write failed. *)

val closure : store:Store.t -> Hash.t -> string * (Hash.t * string) list
(** [closure ~store term] is the closure manifest of [term] (see {!record.entry_closure}) and the
    stored bytes of every declaration it lists, each with its HASH_V0. A stored declaration that
    cannot be loaded is listed with body [none]; a reference that is not a stored declaration is not
    listed. Computed once per term for one store state (the same index and names) in a process. *)

val parse_closure : string -> (string * ((string * string) * string * string) list) option
(** [parse_closure text] reads a closure manifest (see {!record.entry_closure}): its root
    declaration's hex, and [((name, kind), decl, body)] per line, unnamed lines with name and kind
    ["-"]. [None] unless the header, a [root] line with a canonical hash, and every line (a known
    kind, canonical hashes, a body hash or [none]) are well formed. *)

(** {1 Explanations} *)

type change = {
  component : string;
      (** ["entry"] (its implementation or name), ["signature"], ["labels"], ["prelude"], ["core"],
          ["driver"], ["fuel"], ["policy"], ["arguments"] (the count), ["argument"] (an argument's
          kind or name), an argument kind (["assumption"], ["inline"], ["input"], ["term"]) for a
          changed value, or ["callee"] for a declaration a changed entry or term argument reaches *)
  subject : string option;
      (** the entry, assumption, input or term name; for a callee, its kernel names, such as
          ["add, int.add"] (the text rendering spells them with their kinds, from [names], such as
          ["term add, int.add"] or ["con W, type Wrap"]) *)
  before : string option;
  after : string option;  (** for a callee, ["added"] or ["removed"], or [None] when it changed *)
  names : (string * string) list;
      (** for a callee, every (kind, kernel name) bound to the declaration: its aliases and the
          other members of its group or type are one change; empty otherwise *)
  diff : string list;
      (** for a changed callee whose two retained bodies are available, the readable [jacquard diff]
          of them (regions, then [-]/[+] or [before -> after] lines); empty otherwise *)
}

type freshness =
  | Current
  | Unknown of string list
      (** the key is unchanged, but these dependencies' snapshots are gone, so the result is never
          assumed current *)
  | Stale of change list  (** every differing key component *)
  | Never_evaluated
  | Unavailable of string  (** the history cannot be read; never guessed *)

type explanation = {
  result : string;
  evaluated_at : string option;
      (** when the latest key was first recorded; refresh records under the same key do not move it
      *)
  outcome : string option;  (** that first record's status and outcome tag *)
  previous : Hash.t option;  (** that first record's predecessor key *)
  missing : string list;
      (** dependencies of the latest record whose snapshots are gone; always reported, and a result
          with an unchanged key and missing snapshots is [Unknown] *)
  notes : string list;
      (** why some of [missing] can never be restored: declarations whose stored bytes exceed the 16
          MiB retention limit *)
  freshness : freshness;
  transition : (string * change list) option;
      (** the latest record against the last record with another key: the time of the first record
          under the latest key, and the changes *)
  transition_missing : string list;
      (** that earlier record's dependencies whose snapshots are gone *)
}

val explain : cache:string -> document:Hash.t -> Model_doc.prepared -> explanation list
(** [explain ~cache ~document prepared] compares each result's current dependency record, computed
    without evaluating, with its latest record (policies by identity), and that record with its
    predecessor. An assumption or input renders from its snapshots; a missing snapshot renders as
    ["(unavailable)"]. It never writes: a history that cannot be used is [Unavailable], with a
    reason that says what to do (a damaged one is repaired by the next [model eval]; one larger than
    64 MiB can be moved aside). *)

val render_text : explanation -> string list
(** [render_text e] is the human rendering: a [RESULT: FRESHNESS] line, the stale changes (each
    callee followed by its body diff, indented), [snapshots gone:] and [note:] lines, then the last
    change. *)

val to_json : explanation list -> string
(** The [jacquard-model-explain-v1] JSON object [{format, results}], on one line. A callee change
    also carries [names] (each [{kind, name}]) and, when its retained bodies are available, [diff]
    (the rendered lines); a result with notes carries [notes]. *)
