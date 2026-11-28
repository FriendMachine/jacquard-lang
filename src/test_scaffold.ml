(* TEST.5: `jacquard test --scaffold FILE` writes an exploration-test skeleton for the `multi`
   effects FILE declares: a forwarding handler per effect that answers every operation through
   `explore.branch`, an `<effect>-runs` helper over `explore.all`, and one Case per entry point
   whose property is a TODO. The output is checked together with FILE before it is printed. *)

(* surface AST names are kernel names: kebab-case, PascalCase only when rendered *)
let pascal kernel = Surface_name.render Surface_name.Con kernel
let term kernel = Surface_name.render Surface_name.Term kernel

(* a generated name derived from [kernel]: a trailing `?` or `!` may only end a name, so it is
   dropped before the suffix; rendered, so a name that needs an escape gets one *)
(* every name a scaffold defines, as kernel names, collected while it is generated *)
let generated = ref []

let derived kernel suffix =
  let n = String.length kernel in
  let base =
    if n > 1 && (kernel.[n - 1] = '?' || kernel.[n - 1] = '!') then String.sub kernel 0 (n - 1)
    else kernel
  in
  let name = base ^ "-" ^ suffix in
  if not (List.mem name !generated) then generated := name :: !generated;
  term name

(* prelude names a scaffold relies on: a FILE that redefines one would change what the scaffold
   means (a FILE `Test` type, for example, hides its cases from discovery) *)
let relied_on_types = [ "test" ]

let relied_on_values =
  [ "case"; "true"; "false"; "check.true"; "list.all?"; "explore.all"; "explore.branch" ]

(* names FILE binds, as kernel names, in two groups: type names, and the names a call or pattern
   resolves (terms, constructors, operations) *)
type bound = { types : string list; values : string list }

let file_names (tops : Surface_ast.top list) =
  List.fold_left
    (fun acc (top : Surface_ast.top) ->
      match top.it with
      | Surface_ast.Signature (name, _) | Surface_ast.Definition { name; _ } ->
          { acc with values = name :: acc.values }
      | Surface_ast.TypeDecl { name; constructors; _ } ->
          {
            types = name :: acc.types;
            values =
              List.map (fun (c : Surface_ast.constructor) -> c.name) constructors @ acc.values;
          }
      | Surface_ast.EffectDecl { operations; _ } ->
          {
            acc with
            values = List.map (fun (op : Surface_ast.operation) -> op.name) operations @ acc.values;
          }
      | Surface_ast.TopExpr _ | Surface_ast.RawTop _ | Surface_ast.TopHole _ -> acc)
    { types = []; values = [] } tops

(* The finite outcomes of an operation's result type, when they can be listed: Bool, (), or a type
   this file declares whose constructors all take no fields. *)
let outcomes ~(types : (string * Surface_ast.constructor list) list) (ty : Surface_ast.ty) =
  match ty.Surface_ast.it with
  | Surface_ast.TyName "bool" when not (List.mem_assoc "bool" types) -> Some [ "False"; "True" ]
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

(* A checked signature `forall ... . (P1, P2) ->{E1, E2 | e} R`: its parameter types, the effects
   of its outermost row, and the result type's text. *)
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
            let row =
              match String.index_opt row '|' with Some bar -> String.sub row 0 bar | None -> row
            in
            let effects = split_top_commas row in
            let result = String.sub rest (brace + 1) (String.length rest - brace - 1) in
            Some (params, effects, result)

(* whether a rendered signature's effect rows name [effect] *)
let mentions_effect signature eff =
  let n = String.length signature and m = String.length eff in
  let is_ident c =
    match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '.' | '?' -> true | _ -> false
  in
  let rec go i =
    i + m <= n
    && (String.sub signature i m = eff
        && (i = 0 || not (is_ident signature.[i - 1]))
        && (i + m = n || not (is_ident signature.[i + m]))
       || go (i + 1))
  in
  String.contains signature '{' && go 0

(* a placeholder argument for a rendered parameter type; a type FILE declares under a prelude
   type's name renders the same, so it gets none *)
let placeholder ~types ty =
  let own name = List.mem_assoc name types in
  match ty with
  | "Int" when not (own "int") -> Some "0"
  | "Text" when not (own "text") -> Some "\"\""
  | "Bool" when not (own "bool") -> Some "False"
  | "Real" when not (own "real") -> Some "0.0"
  | "()" -> Some "()"
  | _ when String.length ty >= 5 && String.sub ty 0 5 = "List " && not (own "list") -> Some "[]"
  (* a bare type variable: any value instantiates it *)
  | _ when String.length ty > 0 && String.for_all (fun c -> c >= 'a' && c <= 'z') ty -> Some "0"
  | _ -> None

(** The names FILE installs, from its checked declarations (each with its introduced names and
    schemes): written in surface syntax or as a raw [jqd { }] block, including generated field
    accessors. *)
let installed_names (tops : (Kernel.top * (string * string) list) list) =
  List.fold_left
    (fun acc (top, signatures) ->
      match top with
      | Kernel.Expr _ -> acc
      | Kernel.Decl d -> (
          match d.Kernel.it with
          | Kernel.DefTerm bindings ->
              {
                acc with
                values =
                  List.map (fun (b : Kernel.binding) -> b.bname) bindings
                  @ List.map fst signatures @ acc.values;
              }
          | Kernel.DefType { tname; cons; _ } ->
              (* the type's introduced names: its constructors and generated field accessors *)
              {
                types = tname :: acc.types;
                values =
                  List.map (fun (c : Kernel.conspec) -> c.con_name) cons
                  @ List.filter (fun n -> n <> tname) (List.map fst signatures)
                  @ acc.values;
              }
          | Kernel.DefEffect { ops; _ } ->
              { acc with values = List.map (fun (o : Kernel.opspec) -> o.op_name) ops @ acc.values }
          ))
    { types = []; values = [] } tops

(** [generate ?installed ~file ~tops ~signatures ()] is [Ok (Some text)], the scaffold; [Ok None]
    when FILE declares no [multi] effect to explore; or [Error cause] when FILE binds a name the
    scaffold defines or relies on, so the scaffold would not test what it says. [signatures] maps
    each top-level term to its checked signature. *)
let generate ?(installed = { types = []; values = [] }) ~file ~(tops : Surface_ast.top list)
    ~(signatures : (string * string) list) () =
  generated := [];
  let types =
    List.filter_map
      (fun (top : Surface_ast.top) ->
        match top.it with
        (* an opaque type's constructors are sealed to FILE: the scaffold cannot name them *)
        | Surface_ast.TypeDecl { name; opaque = true; _ } -> Some (name, [])
        | Surface_ast.TypeDecl { name; constructors; opaque = false; _ } -> Some (name, constructors)
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
  if effects = [] then Ok None
  else
    let b = Buffer.create 2048 in
    let line fmt =
      Printf.ksprintf
        (fun s ->
          Buffer.add_string b s;
          Buffer.add_char b '\n')
        fmt
    in
    line "-- Exploration tests for %s, generated by `jacquard test --scaffold`." file;
    line "-- Save next to it and run: jacquard test %s <this file>" file;
    List.iter
      (fun name ->
        line "-- %s is not explored: exploration needs a `multi` effect without parameters."
          (Surface_name.render Surface_name.Effect name))
      skipped_effects;
    line "";
    (* operations whose outcomes cannot be listed come first: the formatter places a definition
       before its first use, which would otherwise move it above this header *)
    let todo_outcomes =
      List.concat_map
        (fun (_, operations) ->
          List.filter_map
            (fun (op : Surface_ast.operation) ->
              match outcomes ~types op.result with None -> Some op.name | Some _ -> None)
            operations)
        effects
    in
    List.iter
      (fun op ->
        line
          "-- TODO: list the outcomes of %s; an empty list prunes every execution that reaches it"
          op;
        line "%s() = []" (derived op "outcomes");
        line "")
      todo_outcomes;
    List.iter
      (fun (name, operations) ->
        line "%s(body) = handle body() {" (derived name "world");
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
                  Printf.sprintf "explore.branch(\"%s\", %s())" op.name (derived op.name "outcomes")
            in
            line "  | %s(%s) resume k -> k(%s)"
              (Surface_name.render Surface_name.Op op.name)
              (String.concat ", " params) answer)
          operations;
        line "}";
        line "";
        line "%s(thunk) = explore.all(fn () -> %s(thunk))" (derived name "runs")
          (derived name "world");
        line "")
      effects;
    let effect_names =
      List.map (fun (name, _) -> Surface_name.render Surface_name.Effect name) effects
    in
    List.iter
      (fun (name, signature) ->
        match parse_signature signature with
        | Some (_, _, result) when List.exists (fun e -> mentions_effect result e) effect_names ->
            line "-- TODO: %s returns a function that performs an effect (%s); write its case." name
              signature
        | Some (params, [ eff ], _) when List.mem eff effect_names ->
            let args = List.map (placeholder ~types) params in
            if List.exists Option.is_none args then
              line "-- TODO: %s takes arguments the scaffold cannot fill in (%s); write its case."
                name signature
            else begin
              let args = List.filter_map Fun.id args in
              line "%s : Test" (derived name "explored");
              line "%s = Case(\"%s on every outcome (TODO: state the property)\", fn () -> {"
                (derived name "explored") name;
              let effect_kernel =
                fst
                  (List.find
                     (fun (name, _) -> Surface_name.render Surface_name.Effect name = eff)
                     effects)
              in
              line "  let runs = %s(fn () -> %s(%s))" (derived effect_kernel "runs") (term name)
                (String.concat ", " args);
              line
                "  check.true(list.all?(runs, fn (run) -> True), \"TODO: replace True with the \
                 property\")";
              line "})";
              line ""
            end
        | Some (_, effects, _) when List.exists (fun e -> List.mem e effect_names) effects ->
            line
              "-- TODO: %s performs several effects (%s); a scaffold Case explores one. Write its \
               case."
              name signature
        | None when List.exists (fun e -> mentions_effect signature e) effect_names ->
            line "-- TODO: %s has a signature the scaffold cannot call (%s); write its case." name
              signature
        | _ -> ())
      signatures;
    let surface = file_names tops in
    let types = installed.types @ surface.types and values = installed.values @ surface.values in
    let taken = List.filter (fun name -> List.mem name values) (List.rev !generated) in
    let redefined =
      List.filter (fun name -> List.mem name types) relied_on_types
      @ List.filter (fun name -> List.mem name values) relied_on_values
    in
    let render =
      List.map (fun name ->
          match name with
          | "test" -> "`Test`"
          | "case" | "true" | "false" -> "`" ^ pascal name ^ "`"
          | _ -> "`" ^ term name ^ "`")
    in
    match (taken, redefined) with
    | [], [] -> Ok (Some (Buffer.contents b))
    | [], _ ->
        Error
          (Printf.sprintf
             "%s redefines %s, which the scaffold relies on from the prelude; a scaffold would not \
              test what it says"
             file
             (String.concat ", " (render redefined)))
    | _ ->
        Error
          (Printf.sprintf "%s already defines %s, which the scaffold would define too; rename %s"
             file
             (String.concat ", " (render taken))
             (if List.length taken = 1 then "it" else "them"))
