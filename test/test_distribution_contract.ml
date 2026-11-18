(* The construction typing of the prelude's Bernoulli and UniformInt constructors
   (Distribution_contract): keyed on the frozen declaration and constructor hashes, applied at
   construction sites (expressions, host ingress) and not at patterns. *)

open Jacquard

let fail_diags label diagnostics =
  Alcotest.failf "%s: %s" label (String.concat "; " (List.map Diag.to_string diagnostics))

let expect_ok label = function Ok value -> value | Error ds -> fail_diags label ds

let expect_code label expected = function
  | Error (diagnostic :: _) ->
      Alcotest.(check string) label expected (Diag.code_or_uncoded diagnostic)
  | Error [] -> Alcotest.failf "%s returned an empty diagnostic list" label
  | Ok _ -> Alcotest.failf "%s unexpectedly succeeded" label

let make () =
  let store, _ = Eval_support.make_prelude_ctx () in
  let checker = expect_ok "checker context" (Check.make_ctx store) in
  (store, checker)

let pinned name kind =
  match Prelude_identity.pinned_identity name kind with
  | Some hash -> hash
  | None -> Alcotest.failf "no pinned prelude identity for %s" name

let hash = Alcotest.testable (fun ppf h -> Format.pp_print_string ppf (Hash.to_hex h)) Hash.equal

let test_frozen_hashes_are_the_prelude_pins () =
  Alcotest.check hash "distribution"
    (pinned "distribution" Resolve.KType)
    Distribution_contract.distribution_type;
  Alcotest.check hash "bernoulli" (pinned "bernoulli" Resolve.KCon)
    Distribution_contract.bernoulli_constructor;
  Alcotest.check hash "uniform-int"
    (pinned "uniform-int" Resolve.KCon)
    Distribution_contract.uniform_int_constructor;
  Alcotest.check hash "bool" (pinned "bool" Resolve.KType) Distribution_contract.bool_type

let element_name = function
  | None -> "none"
  | Some Distribution_contract.Bool -> "bool"
  | Some Distribution_contract.Int -> "int"

let test_indexed_element_needs_both_hashes () =
  let d = Distribution_contract.distribution_type in
  let element type_hash constructor_hash =
    element_name (Distribution_contract.indexed_element ~type_hash ~constructor_hash)
  in
  Alcotest.(check string) "bernoulli" "bool" (element d Distribution_contract.bernoulli_constructor);
  Alcotest.(check string)
    "uniform-int" "int"
    (element d Distribution_contract.uniform_int_constructor);
  Alcotest.(check string) "categorical" "none" (element d (pinned "categorical" Resolve.KCon));
  Alcotest.(check string)
    "another type's hash" "none"
    (element (pinned "option" Resolve.KType) Distribution_contract.bernoulli_constructor);
  Alcotest.(check string)
    "the type hash as a constructor" "none"
    (element d Distribution_contract.distribution_type)

let scheme_text checker ?site constructor =
  Check.show_scheme checker (Check.con_scheme checker ?site constructor)

let test_construction_is_indexed_and_patterns_are_declared () =
  let _, checker = make () in
  let bernoulli = Distribution_contract.bernoulli_constructor
  and uniform_int = Distribution_contract.uniform_int_constructor
  and categorical = pinned "categorical" Resolve.KCon in
  Alcotest.(check string)
    "Bernoulli construction" "(Real) ->{} Distribution Bool" (scheme_text checker bernoulli);
  Alcotest.(check string)
    "UniformInt construction" "(Int, Int) ->{} Distribution Int" (scheme_text checker uniform_int);
  Alcotest.(check string)
    "host ingress (force_constructor) is a construction" "(Real) ->{} Distribution Bool"
    (Check.show_scheme checker
       (expect_ok "force bernoulli" (Check.force_constructor checker bernoulli)));
  Alcotest.(check string)
    "Bernoulli pattern" "forall a. (Real) ->{} Distribution a"
    (scheme_text checker ~site:`Pattern bernoulli);
  Alcotest.(check string)
    "UniformInt pattern" "forall a. (Int, Int) ->{} Distribution a"
    (scheme_text checker ~site:`Pattern uniform_int);
  let categorical_construction = scheme_text checker categorical in
  Alcotest.(check string)
    "Categorical is the same at both sites" categorical_construction
    (scheme_text checker ~site:`Pattern categorical);
  Alcotest.(check bool)
    "Categorical stays polymorphic" true
    (String.length categorical_construction >= 9
    && String.sub categorical_construction 0 9 = "forall a.")

(* user declarations that spell the prelude's names, or its whole shape under another name, have
   other hashes and keep their declared schemes *)
let test_user_lookalikes_are_not_indexed () =
  let store, _ = make () in
  let put source =
    Eval_support.put_src store (Store.names_view store) source |> fun hashes -> hashes.Canon.named
  in
  let coin =
    put
      "(deftype coin ((tvar a)) (con bernoulli (field (tref real))) (con uniform-int (field (tref \
       int)) (field (tref int))))"
  in
  let lookalike =
    put
      "(deftype distribution-lookalike ((tvar a)) (con lookalike-bernoulli (field (tref real))) \
       (con lookalike-categorical (field (tapp (tref list) (tapp (tref pair) (tvar a) (tref \
       real))))) (con lookalike-uniform-int (field (tref int)) (field (tref int))))"
  in
  let checker = expect_ok "checker context" (Check.make_ctx store) in
  let shows name hashes =
    Check.show_scheme checker
      (expect_ok name (Check.force_constructor checker (List.assoc name hashes)))
  in
  Alcotest.(check string) "a user bernoulli" "forall a. (Real) ->{} Coin a" (shows "bernoulli" coin);
  Alcotest.(check string)
    "a user uniform-int" "forall a. (Int, Int) ->{} Coin a" (shows "uniform-int" coin);
  Alcotest.(check string)
    "the prelude shape under another name" "forall a. (Real) ->{} DistributionLookalike a"
    (shows "lookalike-bernoulli" lookalike);
  Alcotest.(check bool)
    "the user bernoulli has another hash" false
    (Hash.equal (List.assoc "bernoulli" coin) Distribution_contract.bernoulli_constructor)

let distribution_of element = Types.TCon (Distribution_contract.distribution_type, [ element ])

let test_host_ingress_refuses_a_wrong_element_type () =
  let store, checker = make () in
  let prim name = Types.TCon (pinned name Resolve.KType, []) in
  let value con args = Value.VCon { con; name = "boundary"; args } in
  let coin = value Distribution_contract.bernoulli_constructor [ Value.VReal 0.5 ] in
  let die = value Distribution_contract.uniform_int_constructor [ Value.VInt 1; Value.VInt 6 ] in
  ignore
    (expect_ok "Distribution Text is a boundary type"
       (Host_protocol_v0.boundary_type_supported ~store (distribution_of (prim "text"))));
  ignore
    (expect_ok "a Bernoulli value for a Distribution Bool"
       (Host_protocol_v0.validate_argument_value checker
          ~expected:(distribution_of (prim "bool"))
          coin));
  ignore
    (expect_ok "a UniformInt value for a Distribution Int"
       (Host_protocol_v0.validate_argument_value checker
          ~expected:(distribution_of (prim "int"))
          die));
  expect_code "a Bernoulli value for a Distribution Text" "E1603"
    (Host_protocol_v0.validate_argument_value checker
       ~expected:(distribution_of (prim "text"))
       coin);
  expect_code "a UniformInt value for a Distribution Bool" "E1603"
    (Host_protocol_v0.validate_argument_value checker ~expected:(distribution_of (prim "bool")) die);
  let categorical =
    value
      (pinned "categorical" Resolve.KCon)
      [
        Value.VCon
          {
            con = pinned "cons" Resolve.KCon;
            name = "cons";
            args =
              [
                Value.VCon
                  {
                    con = pinned "mk-pair" Resolve.KCon;
                    name = "mk-pair";
                    args = [ Value.VText "a"; Value.VReal 1.0 ];
                  };
                Value.VCon { con = pinned "nil" Resolve.KCon; name = "nil"; args = [] };
              ];
          };
      ]
  in
  ignore
    (expect_ok "a Categorical value for a Distribution Text"
       (Host_protocol_v0.validate_argument_value checker
          ~expected:(distribution_of (prim "text"))
          categorical))

let suite =
  [
    Alcotest.test_case "frozen hashes are the prelude pins" `Quick
      test_frozen_hashes_are_the_prelude_pins;
    Alcotest.test_case "the indexed element needs both hashes" `Quick
      test_indexed_element_needs_both_hashes;
    Alcotest.test_case "construction is indexed, patterns are declared" `Quick
      test_construction_is_indexed_and_patterns_are_declared;
    Alcotest.test_case "user lookalikes are not indexed" `Quick test_user_lookalikes_are_not_indexed;
    Alcotest.test_case "host ingress refuses a wrong element type" `Quick
      test_host_ingress_refuses_a_wrong_element_type;
  ]
