(** Frozen identities for the prelude [Distribution] constructors whose element type the declaration
    cannot state.

    The prelude declares
    [type Distribution a = Bernoulli Real | Categorical (List (a, Real)) | UniformInt Int Int].
    [Bernoulli] and [UniformInt] do not mention [a], yet every trusted eliminator (the root sampling
    handler, [pmf], [support], the inference drivers, Warp and the native runtime) produces a [Bool]
    for [Bernoulli] and an [Int] for [UniformInt]. The checker therefore types a {e construction} of
    either constructor with that element type; patterns keep the declared scheme. The rule is keyed
    on both the declaration and the constructor hash, so a user declaration with the same spelling
    or shape gains nothing, and no canonical hash changes. *)

exception Bug_invalid_distribution_hash of string
(** Raised at module initialisation if a frozen hash literal is malformed (an internal invariant
    failure). *)

val distribution_type : Hash.t
(** The frozen prelude [distribution] type declaration. *)

val bernoulli_constructor : Hash.t
(** The frozen prelude [bernoulli] constructor. *)

val uniform_int_constructor : Hash.t
(** The frozen prelude [uniform-int] constructor. *)

val bool_type : Hash.t
(** The frozen prelude [bool] type, the element type of a constructed [Bernoulli]. *)

type element =
  | Bool  (** the element type is the prelude [Bool] *)
  | Int  (** the element type is the primitive [Int] *)

val indexed_element : type_hash:Hash.t -> constructor_hash:Hash.t -> element option
(** [indexed_element ~type_hash ~constructor_hash] is [Some Bool] for the frozen [bernoulli]
    constructor of the frozen [distribution] declaration, [Some Int] for its frozen [uniform-int]
    constructor, and [None] for every other pair (including [categorical] and any user lookalike).
    It never fails. *)
