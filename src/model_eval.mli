(** MODEL.1 evaluation and the result cache (docs/designs/model-dependencies.md §3.3-§3.4).

    Each result of a prepared model document is one invocation: its application runs under its
    driver on its own fuel budget, and the outcome is projected under the document's observation
    policy inside that budget. A fully replayable outcome is stored as [model-result-v1] under its
    dependency key; a later evaluation with the same key serves it without running anything. *)

(** {1 Outcomes} *)

type posterior_entry = { probability : float; value : Observation_transcript.field }

type outcome =
  | Value of Observation_transcript.field option
      (** [run] completed; [None] when the policy excludes the result *)
  | Posterior of {
      sampled : bool;
      explored : int;
      entries : posterior_entry list option;  (** [None] when the policy excludes the result *)
    }
  | Inference_failure of { sampled : bool; explored : int; failure : string }
      (** ["impossible"], ["exhausted"], or ["numerical"] *)
  | Failure of string  (** a deterministic runtime failure, by diagnostic code *)
  | Incomplete  (** the fuel budget ran out, during evaluation or projection *)

val uncacheable : outcome -> string option
(** [uncacheable outcome] is the reason an outcome may not be stored: ["fuel"] for an incomplete
    run, ["result-excluded"] when the policy excludes the result, or the kind of the first field
    that is not entirely data (["truncated"], or the opaque kind, such as ["secret"] or
    ["closure"]). [None] when it is fully replayable. *)

val serialize : Model_doc.dependency -> outcome -> string
(** The canonical [model-result-v1] bytes: the dependency record, then the outcome section. *)

val parse : string -> (Model_doc.dependency * outcome, string) result
(** [parse bytes] accepts exactly canonical [model-result-v1] bytes holding a cacheable outcome. *)

(** {1 Evaluation} *)

type status =
  | Fresh  (** evaluated and stored *)
  | Cached  (** served from the cache *)
  | Uncacheable of string  (** evaluated, never stored; the reason *)
  | Refused of Diag.t list  (** not evaluated: the entry needs a root grant that was not given *)

type evaluated = { name : string; key : Hash.t; status : status; outcome : outcome option }

type history_failure = {
  reason : string;  (** why the history was not extended, for the W1802 cause *)
  next_step : string option;  (** what the user can do, when it is not the default advice *)
}

val evaluate :
  ?record:(Model_doc.resolved -> outcome:string -> (string option, history_failure) result) ->
  ?build:string ->
  ctx:Eval.ctx ->
  allows:string list ->
  seed:int ->
  cache:string option ->
  out:(string -> unit) ->
  Model_doc.prepared ->
  evaluated list * Diag.t list
(** [evaluate ~ctx ~allows ~seed ~cache ~out prepared] evaluates every result in document order and
    returns them with cache warnings. [ctx] must be a session over [prepared]'s store. Without
    [allows] no root handler is installed; a result whose entry needs a grant is [Refused] with
    E1806. With [allows] the named grants are installed for every result (seeded with [seed],
    printing through [out]) and nothing is read from or written to the cache. [cache], when present,
    is the cache directory: outcomes live under [outcomes/BUILD/KEY], where [BUILD] is [build] or,
    by default, the HASH_V0 of the running executable and the Core version, so an outcome stored by
    another build is never served; when the executable cannot be read nothing is served or stored
    ([Uncacheable "no-build-identity"]). A stored outcome whose record matches is served; a corrupt
    or foreign file, or a symbolic link, is ignored with W1800 and replaced; a failed write is W1801
    and leaves the result [Uncacheable "write-failed"]. Files are created owner-only and written
    atomically, and the cache's [outcomes] directories are made owner-only when they are ours and
    are not. [record] is called for every result that has an outcome when [cache] is present and
    [allows] is empty, with its status and outcome tag; its failure is W1802 (with the failure's
    next step when it names one), and a note it returns is W1803. *)

val read_private :
  limit:int -> string -> (string, [ `Absent | `Too_large of int | `Unreadable of string ]) result
(** [read_private ~limit path] reads a cache file: [path] itself must name a regular file (a
    symbolic link is [`Unreadable], and so is a file replaced between the check and the open) of at
    most [limit] bytes. Never blocks on a FIFO. *)

val private_dirs : root:string -> string list -> (unit, string) result
(** [private_dirs ~root parts] creates [root] when absent (mode 0700) and each directory [root/p1],
    [root/p1/p2], ... named by [parts]: a missing one is created 0700, and an existing one owned by
    the current user that others can reach is made 0700. [root] itself is never changed, since it
    may be a directory the user named. A path that is not a directory (a symbolic link, say) is an
    error. *)

val make_dirs : string -> unit
(** [make_dirs dir] creates [dir] and its missing parents with mode 0700. *)

val write_atomic : string -> string -> (unit, string) result
(** [write_atomic path bytes] writes [bytes] to an owner-only temporary file beside [path], syncs
    it, and renames it onto [path] (replacing a symbolic link there rather than following it). *)

val render_text : evaluated -> string list
(** The human rendering: a [NAME: STATUS] line, then indented outcome lines. *)

val to_json : evaluated list -> string
(** The [jacquard-model-eval-v1] JSON object [{format, results}], on one line. *)
