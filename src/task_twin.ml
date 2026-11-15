(** Root twins: the label [E@task] that an effect [E] a task (an [async.spawn] child or an
    [async.scope] body) leaves unhandled carries in the rows outside the task.

    A task runs on a fresh continuation under the scheduler, so a handler written around the task
    never sees its operations; they go to the root grant. The twin is a separate identity that no
    handler discharges, so it stays in the row up to the root, where authority consumers charge its
    base effect. Its identity is the deterministic hash
    [HASH_V0("jacquard/task-root-effect/v1\000" ^ raw E)]. Source spells it [E@task] in an effect
    row (kernel name [e@task]); resolution maps that spelling to the twin's hash, and only a
    {!twinnable} effect has one.

    The twin-to-base table is filled at initialization with the twin of every twinnable effect, so a
    twin hash read back from a store, a [.jqd] file or an export is recognized in a fresh process.
    It never fails. *)

let tag = "jacquard/task-root-effect/v1\000"

(** The source and kernel spelling suffix of a twin. *)
let suffix = "@task"

(* twin raw digest -> base effect identity. A mutex guards it because editor recovery may check in
   several domains at once; entries are deterministic, so a race could only repeat one. *)
let table : (string, Hash.t) Hashtbl.t = Hashtbl.create 16
let lock = Mutex.create ()

(** [base_of label] is [Some base] when [label] is the root twin of [base], and [None] otherwise. *)
let base_of label = Mutex.protect lock (fun () -> Hashtbl.find_opt table (Hash.to_raw label))

(** [is_twin label] holds when [label] is a root twin. *)
let is_twin label = Option.is_some (base_of label)

(** [twin base] is the root twin of [base]. It is idempotent: the twin of a twin is itself. *)
let twin base =
  if is_twin base then base
  else
    let twin = Hash.of_string (tag ^ Hash.to_raw base) in
    Mutex.protect lock (fun () -> Hashtbl.replace table (Hash.to_raw twin) base);
    twin

(** [base label] is the base effect of a root twin and [label] itself otherwise. *)
let base label = Option.value (base_of label) ~default:label

(** [root_grantable identity] holds when a root grant can handle effect [identity]: a registry
    effect whose grant name is root-grantable. Identity decides, never the spelling. *)
let root_grantable identity =
  match Effect_registry.find_canonical identity with
  | Some metadata ->
      List.mem (Effect_registry.root_grant_name metadata) Effect_registry.root_grantable_names
  | None -> false

(** [is_channel identity] holds for the scheduler's Channel effect. *)
let is_channel identity = String.equal (Hash.to_hex identity) Channel_contract.channel_effect_hash

(** [twinnable identity] holds when a task may leave [identity] to its surroundings and it then
    carries a twin there: Channel and the root-grantable effects. Async stays itself (the scheduler
    handles the spawn or scope call), and every other effect must be handled inside the task. *)
let twinnable identity = (not (is_twin identity)) && (is_channel identity || root_grantable identity)

(** [spelled_base name] is [Some base] when the kernel name [name] spells a twin, [base ^ "@task"]
    with a nonempty [base], and [None] otherwise. *)
let spelled_base name =
  let n = String.length name and k = String.length suffix in
  if n > k && String.ends_with ~suffix name then Some (String.sub name 0 (n - k)) else None

let () =
  List.iter
    (fun (metadata : Effect_registry.metadata) ->
      match metadata.interface with
      | Effect_registry.Released { hash; _ } when root_grantable hash -> ignore (twin hash)
      | Effect_registry.Released _ | Effect_registry.Reserved _ -> ())
    Effect_registry.catalog;
  match Hash.of_hex Channel_contract.channel_effect_hash with
  | Some channel -> ignore (twin channel)
  | None -> ()
