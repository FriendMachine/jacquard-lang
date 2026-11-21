(** Discrete probabilistic inference (plan W4.2 enumeration, W4.3 likelihood weighting).

    Both algorithms are HANDLERS over the same untouched model — the M3 thesis. The model is any
    zero-ary function (or expression) whose row includes [dist]; the two entry points install
    different native semantics for [sample]/[observe]:

    - {!enumerate}: exact inference. On [sample d], resume once per support element (the multi-shot
      machinery doing its job), weighting each branch by [pmf d x]; on [observe d v], multiply the
      branch weight by [pmf d v]; collect (value, weight) leaves; normalize. A branch with an exact
      zero factor is pruned; one whose weight merely underflows survives. The outcome is typed
      (INF.1, {!enumerate_v1}): an impossible observation set reports E0901, underflow or non-finite
      or negative mass E0917, and an exhausted branch budget E0918.
    - {!likelihood_weighting}: approximate inference. Run K independent executions; [sample] draws
      ancestrally from the seeded splittable PRNG (single resume); [observe] multiplies the run's
      weight; report the normalized empirical posterior.

    Mechanism: both algorithms drive the machine through {!Eval.run_state_capturing}. When a
    [sample] or [observe] reaches the root, the algorithm receives the whole remaining continuation
    as immutable data and resumes it per its semantics — enumeration invokes the SAME continuation
    once per support element (multi-shot), likelihood weighting exactly once per run. The model file
    is identical under both algorithms; only the driver changes. The driver owns these two
    operations ({!driver_ops}): a root [dist] grant does not answer them inside a driver run, while
    every other root grant still reaches the model. *)

open Value

type weighted = { value : Value.t; weight : float }

type posterior = { entries : (Value.t * float) list }
(** normalized, sorted by probability descending then rendering for determinism *)

type risk_weights = { low : float; medium : float; high : float; forbidden : float }
(** Raw, unnormalized binary64 weights in the released risk order. Exact risk enumeration
    accumulates duplicate terminal leaves into these four fields without projecting or normalizing
    them. *)

type risk_positive_support = { low : bool; medium : bool; high : bool; forbidden : bool }
(** Theoretical positive reachability in the released risk order. A field is [true] when at least
    one terminal path to that risk has only strictly positive support factors, even if multiplying
    those factors underflows to binary64 zero. *)

type risk_branch_accounting = {
  completed : int;
  positive : int;
  zero_weight : int;
  underflowed : int;
}
(** Terminal-path accounting for one bounded exact risk enumeration. [positive] counts paths with
    theoretical positive support, [zero_weight] counts paths containing an explicit zero support
    factor, and [underflowed] is the subset of [positive] whose binary64 path weight became zero. *)

type exact_risk_enumeration = {
  weights : risk_weights;
  positive_support : risk_positive_support;
  branches : risk_branch_accounting;
}
(** Decision-neutral evidence from bounded exact enumeration. The record contains raw weights,
    theoretical support, and branch accounting only; normalization and policy projection are
    deliberately separate contracts. *)

let diagnostic ~code cause =
  let summary, next_step =
    match code with
    | "E0901" ->
        ( "The posterior is empty.",
          "Change the model or observations so at least one execution branch has nonzero weight." )
    | "E0902" ->
        ( "Probabilistic inference stopped on a runtime failure.",
          "Correct the reported model runtime failure and rerun inference." )
    | "E0910" ->
        ( "The exact risk-enumeration configuration is invalid.",
          "Supply a strictly positive max_branches budget." )
    | "E0911" ->
        ( "The exact risk model contains an invalid finite distribution.",
          "Use only finite discrete supports whose every weight is finite and nonnegative." )
    | "E0912" ->
        ( "Exact risk enumeration exceeded its branch budget.",
          "Raise max_branches only after reviewing the model's finite support size." )
    | "E0913" ->
        ( "The exact risk model returned a non-Risk value.",
          "Return one released Risk constructor: low, medium, high, or forbidden." )
    | "E0914" ->
        ( "The exact risk model performed an unexpected effect.",
          "Keep the exact model closed except for the released Dist sample and observe operations."
        )
    | "E0915" ->
        ( "Exact risk enumeration stopped on a runtime failure.",
          "Correct the reported model runtime failure and rerun exact risk enumeration." )
    | "E0917" ->
        ( "Inference failed numerically.",
          "Rescale the model's weights so every path weight and the total stay finite, \
           nonnegative, and representable." )
    | "E0922" ->
        ( "async.scope cannot run inside an inference model.",
          "Open the scope outside the inference model and pass its result in." )
    | "E0918" ->
        ( "Exact enumeration exceeded its terminal-path budget.",
          "Raise --max-branches after reviewing the model's finite support size, or use likelihood \
           weighting." )
    | "E0916" ->
        ( "Exact risk enumeration produced a non-finite raw weight.",
          "Rescale the finite model weights so path multiplication and risk accumulation stay \
           finite." )
    | _ -> raise (Diag.Bug_invalid_diagnostic ("unknown inference diagnostic code " ^ code))
  in
  Diag.error ~domain:Inference ~code ~summary ~cause ~next_step ~contrast:None ()

let err ~code fmt = Printf.ksprintf (fun cause -> Error [ diagnostic ~code cause ]) fmt

(* A runtime failure under [code], except exhaustion of computation fuel (RT.1, E0919) or
   allocation (RT.2, E0921), which keeps its code: running out is incomplete inference, not a model
   failure. *)
let runtime_diagnostic ~code error =
  match error with
  | Runtime_err.Diagnostic d when Diag.code d = Some "E0922" -> d
  | _ ->
      if Runtime_err.is_incomplete error then Runtime_err.to_diag error
      else diagnostic ~code (Runtime_err.to_string error)

(* C1: no driver hosts a scheduler, so the scope control operation [async.scope] performs under a
   driver fails closed with its own code (E0922) instead of an unhandled-effect or type error. *)
let is_scope_control op = Hash.equal op Concurrency_contract.scope_control_hash

let scope_cause =
  "the model opened async.scope; an inference driver (dist.sample-lw, jacquard infer, a model \
   document's enumerate or lw result, or a posterior builtin) runs the model on a fresh \
   continuation without a scheduler, so a scope cannot run inside it"

let scope_refusal () = Runtime_err.Diagnostic (diagnostic ~code:"E0922" scope_cause)

(* --- distribution values --- *)

type dist_v =
  | Bernoulli of float
  | Categorical of (Value.t * float) list
  | UniformInt of int * int (* lo..hi inclusive (SL.7) *)

(** [uniform_fits lo hi] (for [lo <= hi]) holds when the range's size [hi - lo + 1] is an OCaml int.
    [uniform-int(min-int, max-int)] and other ranges spanning at least [max_int] do not fit: their
    size wraps, so every site below computes it without integer overflow. The native runtime's
    [uniform_fits] is the same test. *)
let uniform_fits lo hi = hi - lo >= 0 && hi - lo < max_int

(** [uniform_count lo hi] (for [lo <= hi]) is the range's size as a float: exact up to float
    rounding, positive, and never wrapped. *)
let uniform_count lo hi =
  if uniform_fits lo hi then float_of_int (hi - lo + 1)
  else float_of_int hi -. float_of_int lo +. 1.0

(** [uniform_span_at_least lo hi k] (for [lo <= hi] and [0 <= k < max_int]) holds when the range has
    more than [k] values, that is when [hi - lo >= k], with [hi - lo] read as the unsigned number it
    denotes even when it wraps. *)
let uniform_span_at_least lo hi k = (not (uniform_fits lo hi)) || hi - lo >= k

(** [uniform_exact_threshold] is 2^32: a range with more values than this is drawn from integer RNG
    bits ({!uniform_bits_offset}); a range with at most this many is drawn by scaling one uniform
    float by its size, the formula every release used. The native runtime's
    [JQ_UNIFORM_EXACT_THRESHOLD] is the same. *)
let uniform_exact_threshold = 1 lsl 32

(** [uniform_bits_count lo hi] (for [lo <= hi]) is the range's size [hi - lo + 1] as an unsigned
    64-bit number: up to 2^63 (stored as [Int64.min_int]) for [uniform-int(min-int, max-int)]. *)
let uniform_bits_count lo hi = Int64.add (Int64.logand (Int64.of_int (hi - lo)) Int64.max_int) 1L

(** [uniform_bits_offset count r] (for [count] an unsigned size above 2^32 and at most 2^63, and [r]
    63 unsigned random bits, below 2^63) is [Some (r mod count)] when [r] is below the largest
    multiple of [count] that is at most 2^63, else [None]: the draw rejects [r] and takes fresh
    bits. Accepted offsets are exactly uniform. For [count = 2^63] every [r] is accepted. The native
    runtime's [uniform_draw] computes the same in [uint64_t]. *)
let uniform_bits_offset count r =
  let limit = Int64.sub Int64.min_int (Int64.unsigned_rem Int64.min_int count) in
  if Int64.unsigned_compare r limit < 0 then Some (Int64.unsigned_rem r count) else None

(** [unsigned_offset_text i] renders [i], an offset stored as an OCaml int, as the unsigned 63-bit
    decimal it denotes (offsets of [2^62] and above are stored as negative ints). *)
let unsigned_offset_text i =
  Printf.sprintf "%Lu" (Int64.logand (Int64.of_int i) 0x7FFF_FFFF_FFFF_FFFFL)

(** [uniform_count_text lo hi] (for [lo <= hi]) is the range's exact size in decimal, up to
    9223372036854775808 for [uniform-int(min-int, max-int)]. *)
let uniform_count_text lo hi = Printf.sprintf "%Lu" (uniform_bits_count lo hi)

(* Recognize a runtime distribution value built from the prelude constructors. *)
let dist_of_value (ctx : Eval.ctx) (v : Value.t) : (dist_v, Runtime_err.t) result =
  ignore ctx;
  match v with
  | VCon { name = "bernoulli"; args = [ VReal p ]; _ } ->
      if p < 0.0 || p > 1.0 || Float.is_nan p then
        Error (Runtime_err.Arithmetic (Printf.sprintf "bernoulli parameter %g is not in [0, 1]" p))
      else Ok (Bernoulli p)
  | VCon { name = "categorical"; args = [ entries ]; _ } ->
      let rec entries_of = function
        | VCon { name = "nil"; _ } -> Ok []
        | VCon
            {
              name = "cons";
              args = [ VCon { name = "mk-pair"; args = [ x; VReal w ]; _ }; rest ];
              _;
            } ->
            Result.map (fun tail -> (x, w) :: tail) (entries_of rest)
        | v ->
            Error
              (Runtime_err.Type_error
                 (Printf.sprintf "categorical expects a list of pairs, got %s" (Value.display v)))
      in
      Result.bind (entries_of entries) (function
        | [] ->
            (* like an empty uniform-int range: no element to draw, enumerate or score *)
            Error (Runtime_err.Arithmetic "categorical support is empty")
        | es -> Ok (Categorical es))
  | VCon { name = "uniform-int"; args = [ VInt lo; VInt hi ]; _ } ->
      if hi < lo then
        Error (Runtime_err.Arithmetic (Printf.sprintf "uniform-int range %d..%d is empty" lo hi))
      else Ok (UniformInt (lo, hi))
  | v ->
      Error
        (Runtime_err.Type_error (Printf.sprintf "%s is not a distribution value" (Value.display v)))

(* Support with probabilities. Bernoulli's support uses the prelude bool constructors. *)
let support ctx (d : dist_v) : ((Value.t * float) list, Runtime_err.t) result =
  match d with
  | Bernoulli p -> (
      match
        ( Prelude_identity.lookup_kind (Eval.store ctx) "true" Resolve.KCon,
          Prelude_identity.lookup_kind (Eval.store ctx) "false" Resolve.KCon )
      with
      | Some { Resolve.hash = t; _ }, Some { Resolve.hash = f; _ } ->
          Ok
            [
              (VCon { con = t; name = "true"; args = [] }, p);
              (VCon { con = f; name = "false"; args = [] }, 1. -. p);
            ]
      | _ -> Error (Runtime_err.Unresolved "prelude bool constructors"))
  | Categorical entries -> Ok entries
  | UniformInt (lo, hi) ->
      (* enumeration support is the whole range; budget-capped so a huge range is a clean
         error instead of an out-of-memory list *)
      if uniform_span_at_least lo hi 10_000 then
        Error
          (Runtime_err.Arithmetic
             (Printf.sprintf "uniform-int %d..%d has %s outcomes; enumeration caps at 10000" lo hi
                (uniform_count_text lo hi)))
      else
        let n = hi - lo + 1 in
        let p = 1.0 /. float_of_int n in
        Ok (List.init n (fun i -> (Value.VInt (lo + i), p)))

(** [pmf d v]: probability mass of [v] under [d]; 0.0 off-support. UniformInt is computed directly
    so its pmf works on ranges the enumeration cap refuses. *)
let pmf ctx (d : dist_v) (v : Value.t) : (float, Runtime_err.t) result =
  match d with
  | UniformInt (lo, hi) ->
      Ok
        (match v with
        | Value.VInt x when x >= lo && x <= hi -> 1.0 /. uniform_count lo hi
        | _ -> 0.0)
  | _ ->
      Result.map
        (fun entries ->
          List.fold_left
            (fun acc (x, w) -> if Value.show x = Value.show v then acc +. w else acc)
            0.0 entries)
        (support ctx d)

(* value equality via stable rendering: fine for the discrete literals/constructors the
   support can contain *)

(* --- driving the machine --- *)

(* Run a state to either a terminal value or the first root-reaching dist op. *)
(* TYPE.1: an operation is the prelude's [sample] or [observe] by its frozen identity, never by a
   name a user effect may also use *)
let is_dist_op (ctx : Eval.ctx) op name =
  match Prelude_identity.lookup_kind (Eval.store ctx) name Resolve.KOp with
  | Some { Resolve.hash; _ } -> Hash.equal hash op
  | None -> false

type outcome =
  | Done of Value.t
  | Op of { op : Hash.t; name : string; args : Value.t list; resume : Eval.captured_kont }

type validated_outcome =
  | Validated_done of Value.t
  | Validated_op of {
      op : Hash.t;
      name : string;
      args : Value.t list;
      resume : Eval.validated_captured_kont;
    }

(** [driver_ops ctx] is the prelude's [sample] and [observe] by their frozen identities: the
    operations an inference driver owns. A driver captures them before any root handler, so a root
    [dist] grant ([--allow dist], [--dry-run]) never answers a model's draw or observation; other
    root grants still reach the model. A store without them yields only those present. *)
let driver_ops (ctx : Eval.ctx) =
  List.filter_map
    (fun name ->
      Option.map
        (fun { Resolve.hash; _ } -> hash)
        (Prelude_identity.lookup_kind (Eval.store ctx) name Resolve.KOp))
    [ "sample"; "observe" ]

let run_until_op (ctx : Eval.ctx) (state : Eval.state) : (outcome, Runtime_err.t) result =
  match Eval.run_state_capturing ~driver_ops:(driver_ops ctx) ctx state with
  | Ok (Eval.CValue v) -> Ok (Done v)
  | Ok (Eval.COp { op; name; args; kont }) -> Ok (Op { op; name; args; resume = kont })
  | Error e -> Error e

let run_until_op_validated (ctx : Eval.ctx) (state : Eval.validated_state) :
    (validated_outcome, Runtime_err.t) result =
  match Eval.run_validated_state_capturing ~driver_ops:(driver_ops ctx) ctx state with
  | Ok (Eval.VCValue value) -> Ok (Validated_done value)
  | Ok (Eval.VCOp { op; name; args; kont }) -> Ok (Validated_op { op; name; args; resume = kont })
  | Error e -> Error e

(* --- enumeration (W4.2) --- *)

let branch_counter = ref 0

(** Branches explored by the last {!enumerate} (instrumentation for the no-duplicate test). *)
let last_branch_count () = !branch_counter

(* --- bounded exact risk enumeration (GM.21 core) --- *)

(** [enumerate_risk_exact ctx ~max_branches model] depth-first enumerates one finite discrete Dist
    model and returns raw weights for the four released Risk constructors. Every categorical support
    weight is validated before its continuation is resumed. [max_branches] is a strictly positive
    terminal-path budget; attempting the next terminal path fails with E0912 rather than returning
    partial evidence.

    The driver accepts only the released [sample] and [observe] operation identities and only
    terminal [low], [medium], [high], or [forbidden] constructor identities. It continues paths
    after binary64 weight underflow and records their theoretical positive support separately.
    Runtime failures, malformed distributions, non-finite arithmetic, unexpected effects, and wrong
    terminal values are diagnostics. This function does not normalize or project the raw result and
    does not alter {!enumerate}. *)
let enumerate_risk_exact (ctx : Eval.ctx) ~max_branches (model : Eval.state) :
    (exact_risk_enumeration, Diag.t list) result =
  if max_branches <= 0 then err ~code:"E0910" "max_branches must be positive, got %d" max_branches
  else
    let ( let* ) = Result.bind in
    let lookup kind name =
      match Prelude_identity.lookup_kind (Eval.store ctx) name kind with
      | Some { Resolve.hash; _ } -> Ok hash
      | None ->
          err ~code:"E0915" "the released `%s` identity is unavailable in the evaluator store" name
    in
    let* sample_op = lookup Resolve.KOp "sample" in
    let* observe_op = lookup Resolve.KOp "observe" in
    let* low_con = lookup Resolve.KCon "low" in
    let* medium_con = lookup Resolve.KCon "medium" in
    let* high_con = lookup Resolve.KCon "high" in
    let* forbidden_con = lookup Resolve.KCon "forbidden" in
    let finite_nonnegative value =
      match classify_float value with
      | FP_normal | FP_subnormal | FP_zero -> value >= 0.0
      | FP_infinite | FP_nan -> false
    in
    let finite value =
      match classify_float value with
      | FP_normal | FP_subnormal | FP_zero -> true
      | FP_infinite | FP_nan -> false
    in
    let canonical_zero value = if value = 0.0 then 0.0 else value in
    let invalid_distribution fmt =
      Printf.ksprintf (fun cause -> Error [ diagnostic ~code:"E0911" cause ]) fmt
    in
    let invalid_arithmetic fmt =
      Printf.ksprintf (fun cause -> Error [ diagnostic ~code:"E0916" cause ]) fmt
    in
    let decode_distribution value =
      match dist_of_value ctx value with
      | Ok distribution -> Ok distribution
      | Error error -> Error [ runtime_diagnostic ~code:"E0911" error ]
    in
    let validate_entries operation entries =
      let rec validate index = function
        | [] -> Ok entries
        | (_, weight) :: rest ->
            if finite_nonnegative weight then validate (index + 1) rest
            else
              invalid_distribution
                "%s support weight %d is %g; every support weight must be finite and nonnegative"
                operation index weight
      in
      validate 0 entries
    in
    let materialized_support operation distribution =
      match support ctx distribution with
      | Error error -> Error [ runtime_diagnostic ~code:"E0915" error ]
      | Ok entries -> validate_entries operation entries
    in
    let uniform_probability lo hi =
      let probability = 1.0 /. uniform_count lo hi in
      if finite_nonnegative probability && probability > 0.0 then Ok probability
      else
        invalid_arithmetic "uniform-int %d..%d produced invalid support weight %g" lo hi probability
    in
    let rec comparable_value value =
      (* observed values can be shared: every node visited draws on computation fuel (RT.1) *)
      Fuel_meter.tick 1;
      match value with
      | Value.VInt _ | VReal _ | VText _ | VHash _ -> Ok ()
      | VTuple items -> comparable_values items
      | VCon { args; _ } -> comparable_values args
      | value ->
          invalid_distribution
            "exact observe requires transparent data support; opaque or executable value %s is not \
             comparable"
            (Value.display value)
    and comparable_values = function
      | [] -> Ok ()
      | value :: rest ->
          let* () = comparable_value value in
          comparable_values rest
    in
    let rec same_comparable_value left right =
      Fuel_meter.tick 1;
      let* () = comparable_value left in
      let* () = comparable_value right in
      match (left, right) with
      | Value.VInt a, VInt b -> Ok (Int.equal a b)
      | VReal a, VReal b -> Ok (Float.equal a b)
      | VText a, VText b ->
          Fuel_meter.tick (String.length a);
          Ok (String.equal a b)
      | VHash a, VHash b -> Ok (Hash.equal a b)
      | VTuple left_items, VTuple right_items -> same_comparable_values left_items right_items
      | VCon left_con, VCon right_con ->
          if Hash.equal left_con.con right_con.con then
            same_comparable_values left_con.args right_con.args
          else Ok false
      | _ -> Ok false
    and same_comparable_values left right =
      match (left, right) with
      | [], [] -> Ok true
      | left_value :: left_rest, right_value :: right_rest ->
          let* same = same_comparable_value left_value right_value in
          if same then same_comparable_values left_rest right_rest else Ok false
      | _ -> Ok false
    in
    let observation_mass distribution observed =
      match distribution with
      | UniformInt (lo, hi) ->
          let* probability = uniform_probability lo hi in
          Ok
            (match observed with
            | Value.VInt value when value >= lo && value <= hi -> (probability, true)
            | _ -> (0.0, false))
      | Bernoulli _ | Categorical _ ->
          let* entries = materialized_support "observe" distribution in
          let rec sum mass theoretically_positive = function
            | [] -> Ok (canonical_zero mass, theoretically_positive)
            | (value, weight) :: rest ->
                let* same = same_comparable_value value observed in
                if same then
                  let next = mass +. weight in
                  if finite next then sum next (theoretically_positive || weight > 0.0) rest
                  else
                    invalid_arithmetic
                      "observe support accumulation overflowed for value %s in support order"
                      (Value.display observed)
                else sum mass theoretically_positive rest
          in
          sum 0.0 false entries
    in
    let multiply path_weight factor =
      let product = path_weight *. factor in
      if finite product then Ok (canonical_zero product)
      else
        invalid_arithmetic "path-weight multiplication produced %g from %g * %g" product path_weight
          factor
    in
    let weights = ref ({ low = 0.0; medium = 0.0; high = 0.0; forbidden = 0.0 } : risk_weights) in
    let positive_support =
      ref ({ low = false; medium = false; high = false; forbidden = false } : risk_positive_support)
    in
    let completed = ref 0 in
    let positive = ref 0 in
    let zero_weight = ref 0 in
    let underflowed = ref 0 in
    let classify_risk = function
      | VCon { con; args = []; _ } when Hash.equal con low_con -> Ok 0
      | VCon { con; args = []; _ } when Hash.equal con medium_con -> Ok 1
      | VCon { con; args = []; _ } when Hash.equal con high_con -> Ok 2
      | VCon { con; args = []; _ } when Hash.equal con forbidden_con -> Ok 3
      | value ->
          err ~code:"E0913" "expected a released Risk constructor, got %s" (Value.display value)
    in
    let add_terminal risk path_weight theoretically_positive =
      let current = !weights in
      let add prior =
        let total = prior +. path_weight in
        if finite total then Ok (canonical_zero total)
        else
          invalid_arithmetic
            "raw risk-weight accumulation overflowed while adding terminal weight %g" path_weight
      in
      let* total =
        match risk with
        | 0 -> add current.low
        | 1 -> add current.medium
        | 2 -> add current.high
        | 3 -> add current.forbidden
        | _ -> assert false
      in
      (weights :=
         match risk with
         | 0 -> { current with low = total }
         | 1 -> { current with medium = total }
         | 2 -> { current with high = total }
         | 3 -> { current with forbidden = total }
         | _ -> assert false);
      if theoretically_positive then begin
        let support = !positive_support in
        positive_support :=
          match risk with
          | 0 -> { support with low = true }
          | 1 -> { support with medium = true }
          | 2 -> { support with high = true }
          | 3 -> { support with forbidden = true }
          | _ -> assert false
      end;
      Ok ()
    in
    let resume continuation value =
      match Eval.resume_captured_state ctx continuation value with
      | Ok state -> Ok state
      | Error error -> Error [ runtime_diagnostic ~code:"E0915" error ]
    in
    (* RT.2 §4: a sample point's support entries are pending until each one's branch starts *)
    let pending count =
      match Eval.retain ~count ctx Frontier with
      | Ok () -> Ok ()
      | Error error -> Error [ Runtime_err.to_diag error ]
    in
    let rec explore state path_weight theoretically_positive =
      match run_until_op ctx state with
      | Error error -> Error [ runtime_diagnostic ~code:"E0915" error ]
      | Ok (Done value) ->
          if !completed >= max_branches then
            err ~code:"E0912"
              "max_branches=%d was exhausted after %d terminal paths; no partial result was \
               returned"
              max_branches !completed
          else
            let* risk = classify_risk value in
            incr completed;
            if theoretically_positive then begin
              incr positive;
              if path_weight = 0.0 then incr underflowed
            end
            else incr zero_weight;
            add_terminal risk path_weight theoretically_positive
      | Ok (Op { op; args; resume = continuation; _ }) when Hash.equal op sample_op -> (
          match args with
          | [ distribution_value ] -> (
              let* distribution = decode_distribution distribution_value in
              let visit value factor =
                let* path_weight = multiply path_weight factor in
                let* state = resume continuation value in
                explore state path_weight (theoretically_positive && factor > 0.0)
              in
              match distribution with
              | UniformInt (lo, hi) ->
                  let* probability = uniform_probability lo hi in
                  let* () =
                    pending (if hi - lo < 0 || hi - lo = max_int then max_int else hi - lo + 1)
                  in
                  let rec visit_range value =
                    Eval.release_retained Frontier 1;
                    let* () = visit (Value.VInt value) probability in
                    if value = hi then Ok () else visit_range (value + 1)
                  in
                  visit_range lo
              | Bernoulli _ | Categorical _ ->
                  let* entries = materialized_support "sample" distribution in
                  let* () = pending (List.length entries) in
                  let rec visit_entries = function
                    | [] -> Ok ()
                    | (value, factor) :: rest ->
                        Eval.release_retained Frontier 1;
                        let* () = visit value factor in
                        visit_entries rest
                  in
                  visit_entries entries)
          | _ ->
              invalid_distribution "sample expects one distribution, got %d arguments"
                (List.length args))
      | Ok (Op { op; args; resume = continuation; _ }) when Hash.equal op observe_op -> (
          match args with
          | [ distribution_value; observed ] ->
              let* distribution = decode_distribution distribution_value in
              let* factor, factor_positive = observation_mass distribution observed in
              let* path_weight = multiply path_weight factor in
              let* state = resume continuation Value.unit_v in
              explore state path_weight (theoretically_positive && factor_positive)
          | _ ->
              invalid_distribution "observe expects a distribution and a value, got %d arguments"
                (List.length args))
      | Ok (Op { op; _ }) when is_scope_control op -> Error [ diagnostic ~code:"E0922" scope_cause ]
      | Ok (Op { op; name; args; _ }) ->
          err ~code:"E0914" "unexpected operation %s/%d (%s)" name (List.length args)
            (Hash.to_hex op)
    in
    let* () = explore model 1.0 true in
    Ok
      {
        weights = !weights;
        positive_support = !positive_support;
        branches =
          {
            completed = !completed;
            positive = !positive;
            zero_weight = !zero_weight;
            underflowed = !underflowed;
          };
      }

(* --- likelihood weighting (W4.3) --- *)

(* splitmix64 (decision D4): deterministic and seedable; the finalizer and constants follow
   the reference. [split] reseeds a child from the parent's next output with the same fixed
   gamma — a simplification of reference SplitMix's per-split gamma derivation, adequate for
   the discrete M3 demos (the finalizer scrambles child seeds) and deterministic on 64-bit
   platforms (the cram goldens assume 64-bit). *)
module Rng = struct
  type t = { mutable state : int64 }

  let make seed = { state = Int64.of_int seed }

  let next_int64 t =
    t.state <- Int64.add t.state 0x9E3779B97F4A7C15L;
    let z = t.state in
    let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
    let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 27)) 0x94D049BB133111EBL in
    Int64.logxor z (Int64.shift_right_logical z 31)

  (* uniform in [0,1) from the top 53 bits *)
  let float t =
    let bits = Int64.shift_right_logical (next_int64 t) 11 in
    Int64.to_float bits /. 9007199254740992.0

  (** [bounded_int t bound] draws uniformly from zero (inclusive) to [bound] (exclusive). It uses 62
      unsigned bits and rejection sampling, so non-power-of-two bounds have no modulo/float bias and
      every positive OCaml-int bound is range-safe on the supported 64-bit runtime. *)
  let bounded_int t bound =
    if bound <= 0 then invalid_arg "Infer_dist.Rng.bounded_int: bound must be positive";
    let range = Int64.shift_left 1L 62 in
    let bound = Int64.of_int bound in
    let limit = Int64.sub range (Int64.rem range bound) in
    let rec draw () =
      let bits = Int64.shift_right_logical (next_int64 t) 2 in
      if Int64.compare bits limit < 0 then Int64.to_int (Int64.rem bits bound) else draw ()
    in
    draw ()

  let split t = make (Int64.to_int (next_int64 t))
end

(** [uniform_draw rng lo hi] (for [lo <= hi]) draws one element of [[lo, hi]]. A range of more than
    2^32 values ({!uniform_exact_threshold}), up to the 2^63 values of
    [uniform-int(min-int, max-int)], is drawn exactly uniformly: it takes the top 63 bits of
    [Rng.next_int64] and rejects as {!uniform_bits_offset} says, so it consumes one or more RNG
    outputs; the element is [lo] plus the accepted offset (wrapping, which is exact). A range of at
    most 2^32 values takes one [Rng.float] scaled by its size n, the formula every release used, so
    its seeded draws are unchanged. Each of the 2^53 equally likely floats maps to one element, and
    every element gets between q - 1 and q + 1 of them, where q = floor(2^53/n) >= 2^21 (rounding of
    the product moves each element's lower boundary by at most one of them). So every element is
    reachable, and two elements' probabilities differ by a factor of at most (q + 1)/(q - 1), below
    1 + 10^-6; when n is a power of two the draw is exactly uniform. [pmf] reports the ideal [1/n].
    The root sampler, likelihood weighting and Warp's sampled lane all draw through it; the native
    runtime's [uniform_draw] is the same, bit for bit. *)
let uniform_draw rng lo hi =
  if not (uniform_span_at_least lo hi uniform_exact_threshold) then
    lo + int_of_float (Rng.float rng *. float_of_int (hi - lo + 1))
  else
    let count = uniform_bits_count lo hi in
    let rec draw () =
      match uniform_bits_offset count (Int64.shift_right_logical (Rng.next_int64 rng) 1) with
      | Some offset -> lo + Int64.to_int offset
      | None -> draw ()
    in
    draw ()

(* Ancestral draw by inverse CDF over NORMALIZED weights (support may carry an unnormalized
   categorical; without normalization a right-edge u would bias toward the first entry). *)

(** [ascending_total entries] sums the weights smallest first. For finite, nonnegative weights the
    result is the same for every order of the entries, so it decides whether a total overflows. The
    native runtime's [ascending_total] is the same. *)
let ascending_total entries =
  List.fold_left ( +. ) 0.0 (List.sort Float.compare (List.map snd entries))

(** [entry_order_suffices in_order] holds when [in_order], finite, nonnegative weights summed in
    entry order, is finite and at most half the largest float: then no order of those weights can
    overflow, so the entry-order sum can stand in for {!ascending_total}. *)
let entry_order_suffices in_order = Float.is_finite in_order && in_order <= Float.max_float /. 2.0

(** [order_free_total entries in_order] is [in_order], the weights summed in entry order, when
    {!entry_order_suffices} holds, else {!ascending_total}. Only weights near the top of the float
    range pay for the sort. *)
let order_free_total entries in_order =
  if entry_order_suffices in_order then in_order else ascending_total entries

(** [draw_total entries] is the total an inverse-CDF draw scales its uniform by: the weights summed
    in entry order when that is finite (so valid draws keep their stream), else {!ascending_total}
    when that is finite (the total {!check_weights} accepts), else the entry-order total. Every
    categorical draw ({!draw}, Warp's sampled lane) uses it, so they pick the same entry for the
    same uniform; the native runtime's [draw_dist] computes the same total. *)
let draw_total entries =
  let total = List.fold_left (fun acc (_, p) -> acc +. p) 0.0 entries in
  if Float.is_finite total then total
  else
    let ascending = ascending_total entries in
    if Float.is_finite ascending then ascending else total

let draw rng entries =
  let total = draw_total entries in
  let u = Rng.float rng *. if total > 0.0 then total else 1.0 in
  let rec go acc = function
    | [] -> ( match List.rev entries with (x, _) :: _ -> x | [] -> Value.unit_v)
    | (x, p) :: rest -> if u < acc +. p then x else go (acc +. p) rest
  in
  go 0.0 entries

(** [show_weight w] renders a weight in a draw failure as C's [%g] does, except that every NaN is
    [nan]: the sign of a NaN, and C libraries' spelling of it, differ between platforms. The native
    runtime's [show_weight] is the same. *)
let show_weight w = if Float.is_nan w then "nan" else Printf.sprintf "%g" w

(** Why a categorical's weights cannot be drawn from: the first weight that is negative or not
    finite (its index and value), a sum that overflows, or a sum that is exactly zero. *)
type draw_failure = No_mass | Invalid_weight of int * float | Nonfinite_total of float

(** [check_weights entries] validates a support for a draw without touching any random stream: every
    weight finite and nonnegative (the first offender is reported), then a finite sum, then a
    positive sum. Whether the sum is finite is decided by the weights summed in ascending order
    ({!order_free_total}), so it does not depend on the order of the entries. The native runtime's
    [categorical_status] applies the same order. *)
let check_weights (entries : (Value.t * float) list) : (unit, draw_failure) result =
  let rec go index total = function
    | [] ->
        let checked = order_free_total entries total in
        if not (Float.is_finite checked) then Error (Nonfinite_total checked)
        else if total = 0.0 then Error No_mass
        else Ok ()
    | (_, w) :: rest ->
        if Float.is_finite w && w >= 0.0 then go (index + 1) (total +. w) rest
        else Error (Invalid_weight (index, w))
  in
  go 0 0.0 entries

(** The run-time message for a categorical draw that cannot be made; the native runtime prints the
    same text. *)
let draw_failure_message = function
  | No_mass -> "categorical weights sum to zero; there is nothing to draw"
  | Invalid_weight (index, w) ->
      Printf.sprintf "categorical weight %d is %s; a draw needs finite, nonnegative weights" index
        (show_weight w)
  | Nonfinite_total total ->
      Printf.sprintf "categorical weights sum to %s; a draw needs a finite total"
        (show_weight total)

(** The numeric failures of INF.1's shared classification; [numeric] is mirrored by the prelude's
    [inference-numeric-v1]. *)
type numeric = Underflow | Non_finite | Negative_mass

(** [invalid_weights entries] is why enumeration and likelihood weighting refuse to draw from a
    categorical, independent of the order of its entries: [Non_finite] when a weight is NaN or
    infinite, else [Negative_mass] when a weight is negative, else [Non_finite] when the finite,
    nonnegative weights summed in ascending order are not finite ({!order_free_total}); [None] for
    weights a draw accepts, and for a zero-mass support, which is an impossible draw rather than a
    numeric failure. The native runtime's [categorical_refusal] ranks the same way. *)
let invalid_weights (entries : (Value.t * float) list) : numeric option =
  if List.exists (fun (_, w) -> not (Float.is_finite w)) entries then Some Non_finite
  else if List.exists (fun (_, w) -> w < 0.0) entries then Some Negative_mass
  else if
    not
      (Float.is_finite
         (order_free_total entries (List.fold_left (fun acc (_, w) -> acc +. w) 0.0 entries)))
  then Some Non_finite
  else None

(** The cause of the E0917 refusal of such a draw; the native runtime prints the same text. *)
let refusal_cause = function
  | Negative_mass ->
      "a categorical to draw from has a negative weight; enumeration and likelihood weighting draw \
       only from finite, nonnegative weights"
  | Non_finite | Underflow ->
      "a categorical to draw from has a weight or a total that is not finite; enumeration and \
       likelihood weighting draw only from finite weights with a finite total"

(** [draw_checked rng entries] is [draw rng entries] for a support [check_weights] accepts, with the
    same single [Rng.float]; otherwise the failure, with no random draw. *)
let draw_checked rng entries : (Value.t, draw_failure) result =
  Result.map (fun () -> draw rng entries) (check_weights entries)

(** [sample_dist ctx rng d] draws one value from [d] — by {!uniform_draw} for UniformInt (huge
    ranges must not materialize a support list), by inverse CDF over the support otherwise. A
    categorical whose weights [check_weights] refuses is an arithmetic error, like an out-of-range
    Bernoulli parameter. Valid distributions draw exactly as before, except UniformInt ranges above
    2^32 values. *)
let sample_dist ctx rng (d : dist_v) : (Value.t, Runtime_err.t) result =
  match d with
  | UniformInt (lo, hi) -> Ok (Value.VInt (uniform_draw rng lo hi))
  | Categorical entries ->
      Result.map_error
        (fun failure -> Runtime_err.Arithmetic (draw_failure_message failure))
        (draw_checked rng entries)
  | Bernoulli _ -> Result.map (draw rng) (support ctx d)

(** [likelihood_weighting ctx ~seed ~samples model] obtains one immutable initial state from
    [model], validates it, then reuses it for K independent weighted executions. The factory is
    evaluated exactly once; recovery-marked initial states fail before the first execution. A draw
    from a zero-mass categorical gives its run weight zero; a draw from a categorical with a
    negative or non-finite weight (or an overflowing sum) is a runtime failure (E0902). *)
let likelihood_weighting (ctx : Eval.ctx) ~seed ~samples (model : unit -> Eval.state) :
    (posterior, Diag.t list) result =
  let master = Rng.make seed in
  let runs : weighted list ref = ref [] in
  let rec one_run rng (state : Eval.validated_state) (weight : float) : (unit, Runtime_err.t) result
      =
    match run_until_op_validated ctx state with
    | Error e -> Error e
    | Ok (Validated_done v) ->
        runs := { value = v; weight } :: !runs;
        (* alloc-v1: the retained run is a pair of its value and weight *)
        Eval.charge_driver_alloc ctx 3;
        Ok ()
    | Ok (Validated_op { op; name = "sample"; args = [ dv ]; resume; _ })
      when is_dist_op ctx op "sample" -> (
        let drawn =
          Result.bind (dist_of_value ctx dv) (function
            | Categorical entries -> (
                match check_weights entries with
                | Ok () -> Ok (draw rng entries, weight)
                (* a zero-mass draw is an impossible run: weight zero, resumed with the same draw *)
                | Error No_mass -> Ok (draw rng entries, 0.0)
                | Error failure -> Error (Runtime_err.Arithmetic (draw_failure_message failure)))
            | d -> Result.map (fun x -> (x, weight)) (sample_dist ctx rng d))
        in
        match drawn with
        | Error e -> Error e
        | Ok (x, weight) ->
            Result.bind (Eval.resume_validated_state ctx resume x) (fun state ->
                one_run rng state weight))
    | Ok (Validated_op { op; name = "observe"; args = [ dv; v ]; resume; _ })
      when is_dist_op ctx op "observe" -> (
        match Result.bind (dist_of_value ctx dv) (fun d -> pmf ctx d v) with
        | Error e -> Error e
        | Ok p ->
            Result.bind (Eval.resume_validated_state ctx resume Value.unit_v) (fun state ->
                one_run rng state (weight *. p)))
    | Ok (Validated_op { op; _ }) when is_scope_control op -> Error (scope_refusal ())
    | Ok (Validated_op { name; _ }) ->
        (* a non-dist op reached the root during a weighted run (unreachable via the CLI,
           which manifest-checks first; the raw harness can get here) *)
        Error (Runtime_err.Unhandled { effect_ = "(not handled during inference)"; op = name })
  in
  let initial = model () in
  let rec k_runs initial i =
    if i >= samples then Ok ()
    else
      let rng = Rng.split master in
      let state = Eval.fresh_validated_state ctx initial in
      match one_run rng state 1.0 with Error e -> Error e | Ok () -> k_runs initial (i + 1)
  in
  match Eval.validate_state_once ctx initial with
  | Error error -> Error [ runtime_diagnostic ~code:"E0902" error ]
  | Ok initial -> (
      match k_runs initial 0 with
      | Error error -> Error [ runtime_diagnostic ~code:"E0902" error ]
      | Ok () ->
          let total = List.fold_left (fun acc { weight; _ } -> acc +. weight) 0.0 !runs in
          if total <= 0.0 then
            err ~code:"E0901"
              "the posterior is empty: every run is impossible under the observations"
          else
            let tbl : (string, Value.t * float ref) Hashtbl.t = Hashtbl.create 16 in
            List.iter
              (fun { value; weight } ->
                let key = Value.show value in
                match Hashtbl.find_opt tbl key with
                | Some (_, w) -> w := !w +. weight
                | None -> Hashtbl.add tbl key (value, ref weight))
              !runs;
            let entries =
              Hashtbl.fold (fun _ (v, w) acc -> (v, !w /. total) :: acc) tbl []
              |> List.sort (fun (va, pa) (vb, pb) ->
                  match compare pb pa with 0 -> compare (Value.show va) (Value.show vb) | c -> c)
            in
            Ok { entries })

(* --- typed outcomes (INF.1) --- *)

(** [Invalid_draw]: a sample site's categorical weights were refused ({!invalid_weights}), so the
    search stopped there; it is an E0917 numeric failure like [Numeric]. *)
type failure = Impossible | Exhausted | Numeric of numeric | Invalid_draw of numeric

type metadata = {
  exact : bool;  (** exact enumeration, else likelihood weighting *)
  complete : bool;  (** every terminal path explored; never for sampling *)
  seed : int option;
  bound : int option;  (** terminal-path budget or sample count; [None] for unbounded *)
  explored : int;  (** terminal paths reached or runs executed *)
}

type classified = { result : (posterior, failure) result; metadata : metadata }

let merge_normalize total leaves =
  let tbl : (string, Value.t * float ref) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun { value; weight } ->
      let key = Value.show value in
      match Hashtbl.find_opt tbl key with
      | Some (_, w) -> w := !w +. weight
      | None -> Hashtbl.add tbl key (value, ref weight))
    leaves;
  let entries =
    Hashtbl.fold (fun _ (v, w) acc -> (v, !w /. total) :: acc) tbl []
    |> List.sort (fun (va, pa) (vb, pb) ->
        match compare pb pa with 0 -> compare (Value.show va) (Value.show vb) | c -> c)
  in
  { entries }

(** [classify leaves] is the shared outcome contract, mirrored by the prelude's [dist.classify-v1]:
    a non-finite leaf, then a negative leaf, then no surviving leaf (impossible), then a non-finite
    total, then a zero total (every surviving path underflowed), else the merged, normalized
    posterior. [leaves] are the surviving paths or runs, most recent first. *)
let classify (leaves : weighted list) : (posterior, failure) result =
  let finite w = Float.is_finite w in
  if List.exists (fun { weight; _ } -> not (finite weight)) leaves then Error (Numeric Non_finite)
  else if List.exists (fun { weight; _ } -> weight < 0.0) leaves then Error (Numeric Negative_mass)
  else if leaves = [] then Error Impossible
  else
    let total = List.fold_left (fun acc { weight; _ } -> acc +. weight) 0.0 leaves in
    if not (finite total) then Error (Numeric Non_finite)
    else if total = 0.0 then Error (Numeric Underflow)
    else Ok (merge_normalize total leaves)

(** [refusal_diagnostic reason] is the E0917 diagnostic of a draw {!invalid_weights} refuses. The
    in-language drivers raise it (through [support] and [dist.sample-lw-weights-v1]); [infer] and
    model documents report it as an {!Invalid_draw} outcome. *)
let refusal_diagnostic reason = diagnostic ~code:"E0917" (refusal_cause reason)

let failure_diagnostics ~sampled = function
  | Impossible ->
      err ~code:"E0901" "the posterior is empty: every %s is impossible under the observations"
        (if sampled then "run" else "branch")
  | Exhausted ->
      err ~code:"E0918"
        "exploration stopped at the terminal-path budget before every path was reached"
  | Numeric Underflow ->
      err ~code:"E0917"
        "every possible %s's weight underflowed to zero; the posterior is not representable"
        (if sampled then "run" else "path")
  | Numeric Non_finite -> err ~code:"E0917" "a path weight or the total mass is not finite"
  | Numeric Negative_mass -> err ~code:"E0917" "a path weight is negative"
  | Invalid_draw reason -> Error [ refusal_diagnostic reason ]

(** [enumerate_v1 ?max_branches ctx model] is exact enumeration with the typed outcome. A path with
    an exact zero factor is pruned (it counts as a terminal path and leaves nothing); a path whose
    product merely underflows survives, so underflow is distinguished from impossibility. With
    [max_branches], attempting a terminal path beyond the budget stops exploration: the outcome is
    [Exhausted], never a partial posterior. A sample site whose categorical weights
    {!invalid_weights} refuses stops exploration there with [Invalid_draw], before any of its
    branches, so no later factor can prune it. Runtime failures are E0902 diagnostics. *)
let enumerate_v1 ?max_branches (ctx : Eval.ctx) (model : Eval.state) :
    (classified, Diag.t list) result =
  branch_counter := 0;
  (* a non-positive budget is exhausted before the model runs *)
  let exhausted = ref (match max_branches with Some budget -> budget <= 0 | None -> false) in
  let leaves : weighted list ref = ref [] in
  (* the reason a sample site's weights were refused; exploration stops there *)
  let refused : numeric option ref = ref None in
  let terminal () =
    match max_branches with
    | Some budget when !branch_counter >= budget ->
        exhausted := true;
        false
    | _ ->
        incr branch_counter;
        true
  in
  let factor p resume explore_next =
    if !exhausted then Ok ()
    else if p = 0.0 then (
      ignore (terminal ());
      Ok ())
    else Result.bind (resume ()) explore_next
  in
  let rec explore (state : Eval.state) (weight : float) : (unit, Runtime_err.t) result =
    if !exhausted then Ok ()
    else
      match run_until_op ctx state with
      | Error e -> Error e
      | Ok (Done v) ->
          if terminal () then leaves := { value = v; weight } :: !leaves;
          Ok ()
      | Ok (Op { op; name = "sample"; args = [ dv ]; resume; _ }) when is_dist_op ctx op "sample"
        -> (
          match Result.bind (dist_of_value ctx dv) (support ctx) with
          | Error e -> Error e
          | Ok entries when Option.is_some (invalid_weights entries) ->
              (* refused at the draw, before any branch: no later factor can prune it *)
              refused := invalid_weights entries;
              Error (Runtime_err.Arithmetic "refused categorical draw")
          | Ok entries ->
              (* RT.2 §4: the support entries not yet explored are the pending frontier; each
                 leaves it as its branch starts *)
              Result.bind (Eval.retain ~count:(List.length entries) ctx Frontier) @@ fun () ->
              let rec branches = function
                | [] -> Ok ()
                | (x, p) :: rest ->
                    Eval.release_retained Frontier 1;
                    Result.bind
                      (factor p
                         (fun () -> Eval.resume_captured_state ctx resume x)
                         (fun state -> explore state (weight *. p)))
                      (fun () -> branches rest)
              in
              branches entries)
      | Ok (Op { op; name = "observe"; args = [ dv; v ]; resume; _ })
        when is_dist_op ctx op "observe" -> (
          match Result.bind (dist_of_value ctx dv) (fun d -> pmf ctx d v) with
          | Error e -> Error e
          | Ok p ->
              factor p
                (fun () -> Eval.resume_captured_state ctx resume Value.unit_v)
                (fun state -> explore state (weight *. p)))
      | Ok (Op { op; _ }) when is_scope_control op -> Error (scope_refusal ())
      | Ok (Op { name; args; _ }) ->
          Error
            (Runtime_err.Type_error
               (Printf.sprintf "enumerate: unexpected op %s/%d" name (List.length args)))
  in
  let metadata ~complete =
    { exact = true; complete; seed = None; bound = max_branches; explored = !branch_counter }
  in
  let explored = explore model 1.0 in
  match (explored, !refused) with
  | Error _, Some reason ->
      Ok { result = Error (Invalid_draw reason); metadata = metadata ~complete:false }
  | Error error, None -> Error [ runtime_diagnostic ~code:"E0902" error ]
  | Ok (), _ ->
      let result = if !exhausted then Error Exhausted else classify !leaves in
      Ok { result; metadata = metadata ~complete:(not !exhausted) }

(** The seeded likelihood-weighting runs behind {!lw_surviving_runs} and {!likelihood_weighting_v1}:
    the possible runs, oldest first, with their unnormalized weights, or [Refused (reason, runs)]
    when run number [runs] (counted from one) reached a draw {!invalid_weights} refuses while it was
    still possible. *)
type lw_runs = Surviving of (Value.t * float) list | Refused of numeric * int

(** [lw_runs ctx ~seed ~samples model] runs [samples] seeded likelihood-weighting executions exactly
    as {!likelihood_weighting} does (the same draws). A run is impossible when an observation has an
    exact zero factor or a categorical draw's support has zero total mass; an impossible run is
    dropped when it ends. A possible run that reaches a categorical {!invalid_weights} refuses stops
    the driver there, as enumeration stops at the same site, whatever the rest of the run would
    observe. A run that is already impossible draws from such a categorical over {!draw_total} and
    carries on, since enumeration never reaches a site behind an exact zero factor; that is the
    released driver's pick unless only the entry-order total overflows, where the ascending sum is
    used. *)
let lw_runs (ctx : Eval.ctx) ~seed ~samples (model : unit -> Eval.state) :
    (lw_runs, Diag.t list) result =
  let master = Rng.make seed in
  let runs : weighted list ref = ref [] in
  let refused : numeric option ref = ref None in
  let rec one_run rng (state : Eval.validated_state) (weight : float) (possible : bool) :
      (unit, Runtime_err.t) result =
    match run_until_op_validated ctx state with
    | Error e -> Error e
    | Ok (Validated_done v) ->
        if possible then (
          runs := { value = v; weight } :: !runs;
          (* alloc-v1: the retained run is a pair of its value and weight *)
          Eval.charge_driver_alloc ctx 3);
        Ok ()
    | Ok (Validated_op { op; name = "sample"; args = [ dv ]; resume; _ })
      when is_dist_op ctx op "sample" -> (
        let drawn =
          Result.bind (dist_of_value ctx dv) (function
            | Categorical entries -> (
                match (check_weights entries, invalid_weights entries) with
                | Ok (), _ -> Ok (draw rng entries, possible)
                (* a categorical whose support has no mass is an impossible draw, not a value; the
                   run resumes with the same draw as before and is dropped when it ends *)
                | Error No_mass, _ -> Ok (draw rng entries, false)
                | Error _, Some reason when possible ->
                    refused := Some reason;
                    Error (Runtime_err.Arithmetic "refused categorical draw")
                | Error _, _ -> Ok (draw rng entries, false))
            | d -> Result.map (fun x -> (x, possible)) (sample_dist ctx rng d))
        in
        match drawn with
        | Error e -> Error e
        | Ok (x, possible) ->
            Result.bind (Eval.resume_validated_state ctx resume x) (fun state ->
                one_run rng state weight possible))
    | Ok (Validated_op { op; name = "observe"; args = [ dv; v ]; resume; _ })
      when is_dist_op ctx op "observe" -> (
        match Result.bind (dist_of_value ctx dv) (fun d -> pmf ctx d v) with
        | Error e -> Error e
        | Ok p ->
            Result.bind (Eval.resume_validated_state ctx resume Value.unit_v) (fun state ->
                one_run rng state (weight *. p) (possible && p <> 0.0)))
    | Ok (Validated_op { op; _ }) when is_scope_control op -> Error (scope_refusal ())
    | Ok (Validated_op { name; _ }) ->
        Error (Runtime_err.Unhandled { effect_ = "(not handled during inference)"; op = name })
  in
  let initial = model () in
  let rec k_runs initial i =
    if i >= samples then Ok i
    else
      let rng = Rng.split master in
      let state = Eval.fresh_validated_state ctx initial in
      match one_run rng state 1.0 true with
      | Error e -> Error (e, i + 1)
      | Ok () -> k_runs initial (i + 1)
  in
  match Eval.validate_state_once ctx initial with
  | Error error -> Error [ runtime_diagnostic ~code:"E0902" error ]
  | Ok initial -> (
      let ran = k_runs initial 0 in
      match (ran, !refused) with
      | Error (_, run), Some reason -> Ok (Refused (reason, run))
      | Error (error, _), None -> Error [ runtime_diagnostic ~code:"E0902" error ]
      | Ok _, _ -> Ok (Surviving (List.rev_map (fun { value; weight } -> (value, weight)) !runs)))

(** [lw_surviving_runs ctx ~seed ~samples model] is {!lw_runs}'s possible runs, oldest first, with
    their unnormalized weights; a refused draw is its E0917 diagnostic. [dist.sample-lw-weights-v1]
    returns the runs. *)
let lw_surviving_runs (ctx : Eval.ctx) ~seed ~samples (model : unit -> Eval.state) :
    ((Value.t * float) list, Diag.t list) result =
  Result.bind (lw_runs ctx ~seed ~samples model) (function
    | Surviving runs -> Ok runs
    | Refused (reason, _) -> Error [ refusal_diagnostic reason ])

(** [likelihood_weighting_v1] is seeded likelihood weighting with the typed outcome; for a
    classifiable model its posterior equals {!likelihood_weighting}'s. A refused draw is an
    [Invalid_draw] outcome whose metadata counts the runs executed up to it. *)
let likelihood_weighting_v1 (ctx : Eval.ctx) ~seed ~samples (model : unit -> Eval.state) :
    (classified, Diag.t list) result =
  let metadata explored =
    { exact = false; complete = false; seed = Some seed; bound = Some samples; explored }
  in
  Result.map
    (function
      | Surviving runs ->
          {
            result = classify (List.rev_map (fun (value, weight) -> { value; weight }) runs);
            metadata = metadata samples;
          }
      | Refused (reason, run) -> { result = Error (Invalid_draw reason); metadata = metadata run })
    (lw_runs ctx ~seed ~samples model)

(* RT.1: drivers key, merge and compare values outside any evaluator run; a walk that runs out of
   fuel there ends the driver with E0919 *)
let guard_walks ctx run =
  let exhausted error = Error [ Runtime_err.to_diag error ] in
  (* exhaustion is sticky: a driver entered, or finishing, after the invocation ran out (of fuel or,
     RT.2, of allocation) reports it even on a path that does no further metered work *)
  match Eval.exhaustion ctx with
  | Some error -> exhausted error
  | None -> (
      match Eval.with_rendered ctx ~exceeded:exhausted run with
      | result -> ( match Eval.exhaustion ctx with Some error -> exhausted error | None -> result)
      | exception Fuel_meter.Exceeded -> exhausted (Eval.fuel_error ctx))

(* RT.2 §4: a search that ends, however it ends, leaves none of its pending entries counted *)
let releasing_frontier run =
  let start = Retain_meter.frontier.count in
  Fun.protect ~finally:(fun () -> Retain_meter.frontier.count <- start) run

let enumerate_v1 ?max_branches ctx model =
  guard_walks ctx (fun () -> releasing_frontier (fun () -> enumerate_v1 ?max_branches ctx model))

let likelihood_weighting_v1 ctx ~seed ~samples model =
  guard_walks ctx (fun () -> likelihood_weighting_v1 ctx ~seed ~samples model)

let likelihood_weighting ctx ~seed ~samples model =
  guard_walks ctx (fun () -> likelihood_weighting ctx ~seed ~samples model)

let lw_surviving_runs ctx ~seed ~samples model =
  guard_walks ctx (fun () -> lw_surviving_runs ctx ~seed ~samples model)

let enumerate_risk_exact ctx ~max_branches model =
  guard_walks ctx (fun () ->
      releasing_frontier (fun () -> enumerate_risk_exact ctx ~max_branches model))

(** The legacy success-or-diagnostic view of a classified outcome. *)
let classified_to_result ~sampled (c : classified) : (posterior, Diag.t list) result =
  match c.result with Ok p -> Ok p | Error f -> failure_diagnostics ~sampled f

(** [enumerate ctx state] runs exact enumeration of a model state (build one with {!Eval.expr_state}
    or {!Eval.apply_state}): {!enumerate_v1} without a budget, failures as diagnostics. *)
let enumerate (ctx : Eval.ctx) (model : Eval.state) : (posterior, Diag.t list) result =
  Result.bind (enumerate_v1 ctx model) (classified_to_result ~sampled:false)

let show_metadata (m : metadata) : string =
  Printf.sprintf "method=%s complete=%b seed=%s bound=%s explored=%d"
    (if m.exact then "exact-enumeration" else "likelihood-weighting")
    m.complete
    (match m.seed with Some s -> string_of_int s | None -> "none")
    (match m.bound with Some b -> string_of_int b | None -> "unbounded")
    m.explored

(** Render a posterior table, one row per value, probabilities to 6 places. *)
let show_posterior (p : posterior) : string =
  String.concat "\n"
    (List.map (fun (v, pr) -> Printf.sprintf "%.6f  %s" pr (Value.display v)) p.entries)
