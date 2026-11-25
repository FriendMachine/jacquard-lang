(* TEST.5: `jacquard test --scaffold FILE` writes an exploration-test skeleton for the `multi`
   effects FILE declares: a forwarding handler per effect that answers every operation through
   `explore.branch`, an `<effect>-runs` helper over `explore.all`, and one Case per entry point
   whose property is a TODO. The output is checked together with FILE before it is printed. *)

(* surface AST names are kernel names: kebab-case, PascalCase only when rendered *)
let pascal kernel = Surface_name.render Surface_name.Con kernel

(* The finite outcomes of an operation's result type, when they can be listed: Bool, (), or a type
   this file declares whose constructors all take no fields. *)
let outcomes ~(types : (string * Surface_ast.constructor list) list) (ty : Surface_ast.ty) =
  match ty.Surface_ast.it with
  | Surface_ast.TyName "bool" -> Some [ "False"; "True" ]
  | Surface_ast.TyTuple [] -> Some [ "()" ]
  | Surface_ast.TyName name -> (
      match List.assoc_opt name types with
      | Some constructors
        when constructors <> []
             && List.for_all (fun (c : Surface_ast.constructor) -> c.fields = []) constructors ->
          Some (List.map (fun (c : Surface_ast.constructor) -> pascal c.name) constructors)
      | Some _ | None -> None)
  | _ -> None

(* split "A, B (C, D), E" at commas outside brackets *)
let split_top_commas text =
  let parts = ref [] and depth = ref 0 and start = ref 0 in
  String.iteri
    (fun i c ->
      match c with
      | '(' | '[' | '{' -> incr depth
      | ')' | ']' | '}' -> decr depth
      | ',' when !depth = 0 ->
          parts := String.sub text !start (i - !start) :: !parts;
          start := i + 1
      | _ -> ())
    text;
  parts := String.sub text !start (String.length text - !start) :: !parts;
  List.rev_map String.trim !parts |> List.filter (fun s -> s <> "")

(* A checked signature `forall ... . (P1, P2) ->{E1, E2 | e} R`: its parameter types and the
   effects of its outermost row. *)
let parse_signature signature =
  let signature = String.trim signature in
  (* a quantifier only names type and row variables: drop it *)
  let signature =
    if String.length signature > 7 && String.sub signature 0 7 = "forall " then
      match String.index_opt signature '.' with
      | Some dot -> String.trim (String.sub signature (dot + 1) (String.length signature - dot - 1))
      | None -> signature
    else signature
  in
  if String.length signature = 0 || signature.[0] <> '(' then None
  else
    let depth = ref 0 and close = ref (-1) in
    String.iteri
      (fun i c ->
        if !close < 0 then
          match c with
          | '(' -> incr depth
          | ')' ->
              decr depth;
              if !depth = 0 then close := i
          | _ -> ())
      signature;
    if !close < 0 then None
    else
      let params = split_top_commas (String.sub signature 1 (!close - 1)) in
      let rest = String.sub signature (!close + 1) (String.length signature - !close - 1) in
      let rest = String.trim rest in
      if String.length rest < 3 || String.sub rest 0 3 <> "->{" then None
      else
        match String.index_opt rest '}' with
        | None -> None
        | Some brace ->
            (* a row `{E1, E2 | e}`: its tail variable is not an effect *)
            let row = String.sub rest 3 (brace - 3) in
            let row = match String.index_opt row '|' with Some bar -> String.sub row 0 bar | None -> row in
            let effects = split_top_commas row in
            Some (params, effects)

(* whether a rendered signature's effect rows name [effect] *)
let mentions_effect signature effect =
  let n = String.length signature and m = String.length effect in
  let is_ident c = match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '.' | '?' -> true | _ -> false in
  let rec go i =
    i + m <= n
    && ((String.sub signature i m = effect
        && (i = 0 || not (is_ident signature.[i - 1]))
        && (i + m = n || not (is_ident signature.[i + m])))
       || go (i + 1))
  in
  String.contains signature '{' && go 0

let placeholder ty =
  match ty with
  | "Int" -> Some "0"
  | "Text" -> Some "\"\""
  | "Bool" -> Some "False"
  | "Real" -> Some "0.0"
  | _ when String.length ty >= 5 && String.sub ty 0 5 = "List " -> Some "[]"
  | _ -> None

(** [generate ~file ~tops ~signatures] is the scaffold text, or [None] when FILE declares no
    [multi] effect. [signatures] maps each top-level term to its checked signature. *)
let generate ~file ~(tops : Surface_ast.top list) ~(signatures : (string * string) list) =
  let types =
    List.filter_map
      (fun (top : Surface_ast.top) ->
        match top.it with
        | Surface_ast.TypeDecl { name; constructors; _ } -> Some (name, constructors)
        | _ -> None)
      tops
  in
  let effects =
    List.filter_map
      (fun (top : Surface_ast.top) ->
        match top.it with
        | Surface_ast.EffectDecl { name; vars = []; operations }
          when operations <> []
               && List.for_all
                    (fun (op : Surface_ast.operation) -> op.mode = Some Kernel.Multi)
                    operations ->
            Some (name, operations)
        | _ -> None)
      tops
  in
  let skipped_effects =
    List.filter_map
      (fun (top : Surface_ast.top) ->
        match top.it with
        | Surface_ast.EffectDecl { name; _ } when not (List.mem_assoc name effects) -> Some name
        | _ -> None)
      tops
  in
  if effects = [] then None
  else
    let b = Buffer.create 2048 in
    let line fmt = Printf.ksprintf (fun s -> Buffer.add_string b s; Buffer.add_char b '\n') fmt in
    line "-- Exploration tests for %s, generated by `jacquard test --scaffold`." file;
    line "-- Save next to it and run: jacquard test %s <this file>" file;
    List.iter
      (fun name ->
        line "-- %s is not explored: exploration needs a `multi` effect without parameters."
          (Surface_name.render Surface_name.Effect name))
      skipped_effects;
    line "";
    let todo_outcomes = ref [] in
    List.iter
      (fun (name, operations) ->
        let effect_kebab = name in
        line "%s-world(body) = handle body() {" effect_kebab;
        line "  | return v -> v";
        List.iter
          (fun (op : Surface_ast.operation) ->
            let params = List.mapi (fun i _ -> Printf.sprintf "a%d" (i + 1)) op.params in
            let answer =
              match outcomes ~types op.result with
              | Some [ "()" ] -> "()"
              | Some listed ->
                  Printf.sprintf "explore.branch(\"%s\", [%s])" op.name (String.concat ", " listed)
              | None ->
                  todo_outcomes := op.name :: !todo_outcomes;
                  Printf.sprintf "explore.branch(\"%s\", %s-outcomes())" op.name op.name
            in
            line "  | %s(%s) resume k -> k(%s)" op.name (String.concat ", " params) answer)
          operations;
        line "}";
        line "";
        line "%s-runs(thunk) = explore.all(fn () -> %s-world(thunk))" effect_kebab effect_kebab;
        line "")
      effects;
    List.iter
      (fun op ->
        line "-- TODO: list the outcomes of %s; an empty list prunes every execution that reaches it"
          op;
        line "%s-outcomes() = []" op;
        line "")
      (List.rev !todo_outcomes);
    let effect_names = List.map (fun (name, _) -> Surface_name.render Surface_name.Effect name) effects in
    List.iter
      (fun (term, signature) ->
        match parse_signature signature with
        | Some (params, [ effect ]) when List.mem effect effect_names ->
            let args = List.map placeholder params in
            if List.exists Option.is_none args then
              line "-- TODO: %s takes arguments the scaffold cannot fill in (%s); write its case."
                term signature
            else begin
              let args = List.filter_map Fun.id args in
              line "%s-explored : Test" term;
              line
                "%s-explored = Case(\"%s on every outcome (TODO: state the property)\", fn () -> {"
                term term;
              let effect_kernel =
                fst (List.find (fun (name, _) -> Surface_name.render Surface_name.Effect name = effect) effects)
              in
              line "  let runs = %s-runs(fn () -> %s(%s))" effect_kernel term
                (String.concat ", " args);
              line "  check.true(list.all?(runs, fn (run) -> True), \"TODO: replace True with the property\")";
              line "})";
              line ""
            end
        | Some (_, effects) when List.exists (fun e -> List.mem e effect_names) effects ->
            line
              "-- TODO: %s also performs effects the scaffold does not explore (%s); write its case."
              term signature
        | None when List.exists (fun e -> mentions_effect signature e) effect_names ->
            line "-- TODO: %s has a signature the scaffold cannot call (%s); write its case." term
              signature
        | _ -> ())
      signatures;
    Some (Buffer.contents b)
