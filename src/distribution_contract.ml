(* Frozen identities for the prelude Distribution constructors whose element type the declaration
   cannot state; contracts in distribution_contract.mli. *)

exception Bug_invalid_distribution_hash of string

let hash_of_frozen label encoded =
  match Hash.of_hex encoded with
  | Some hash -> hash
  | None -> raise (Bug_invalid_distribution_hash (Printf.sprintf "malformed frozen %s hash" label))

let distribution_type =
  hash_of_frozen "Distribution type"
    "53183d6bfd3437588d6f8a01e2fc8df17ee9971d28a6362228f83bbe94b78db3"

let bernoulli_constructor =
  hash_of_frozen "Bernoulli constructor"
    "a1acd43fd2b30b2e47feb4d4137b98876a4c696c6b203598c3898ccf00600287"

let uniform_int_constructor =
  hash_of_frozen "UniformInt constructor"
    "6c99c712622f30eb924001702d7b07b1286d36aa375022635817093e778b05d7"

let bool_type =
  hash_of_frozen "Bool type" "1b2db433ec9de4ff5e8a351301178838634f950ddd9bf08937ed1dd0b4a9a3fc"

type element = Bool | Int

let indexed_element ~type_hash ~constructor_hash =
  if not (Hash.equal type_hash distribution_type) then None
  else if Hash.equal constructor_hash bernoulli_constructor then Some Bool
  else if Hash.equal constructor_hash uniform_int_constructor then Some Int
  else None
