(* A ReScript PPX deriving pretty-printers from type declarations.

   For every type declaration annotated with `@prettyPrint`, e.g.

   {[
     @prettyPrint
     type point = {x: float, y: float}
   ]}

   it appends two functions right after the declaration:

   {[
     let point_toDoc = (v: point) =>
       PrettyPrint.record([
         PrettyPrint.field("x", PrettyPrint.float(v.x)),
         PrettyPrint.field("y", PrettyPrint.float(v.y)),
       ])
     let point_prettyPrint = (v: point) => PrettyPrint.render(point_toDoc(v))
   ]}

   `<type>_toDoc` builds a `PrettyPrint.doc` -- the layout-independent
   description of the value that `PrettyPrint.render` turns into a string --
   and is what printers for other types compose with. `<type>_prettyPrint` is
   the convenience entry point returning the string. `PrettyPrint` is the
   runtime module in `../src/PrettyPrint.res`.

   In an interface file (`.resi`) the same annotation appends the matching
   `let point_toDoc: point => PrettyPrint.doc` and
   `let point_prettyPrint: point => string` declarations instead.

   A note on the AST this works with. bsc doesn't hand a PPX its own parsetree
   but a frozen, OCaml 4.06-shaped compatibility version of it (`Parsetree0`
   in the compiler's sources), which ppxlib migrates up to its own AST version
   on the way in and back down on the way out. ReScript 12 constructs that have
   no OCaml 4.06 equivalent are encoded with conventions the two helpers below
   (`fn` and `arrow`) follow -- see `compiler/ml/ast_mapper_to0.ml` and
   `ast_mapper_from0.ml` in the ReScript repo for the encoding's source of
   truth. *)

open Ppxlib
open Ast_builder.Default

let annotation = "prettyPrint"
let opaque_annotation = "prettyPrint.opaque"
let doc_suffix = "_toDoc"
let string_suffix = "_prettyPrint"

(* The name a polymorphic type's printer gives the printer it takes for its
   type parameter `'name`. *)
let param_printer_name name = "toDoc_" ^ name

let fail ~loc message =
  Location.raise_errorf ~loc "@%s: %s" annotation message

let has_attribute name attributes =
  List.exists (fun attribute -> attribute.attr_name.txt = name) attributes

(* Names for the variables generated code binds (constructor arguments, tuple
   components, lambda parameters). Globally unique, so no generated binding
   can shadow another. *)
let fresh_var =
  let counter = ref 0 in
  fun () ->
    incr counter;
    Printf.sprintf "v%d" !counter

(* -- ReScript-flavored AST helpers ---------------------------------------- *)

(* A string literal. The "js" delimiter is what ReScript's own parser attaches
   to `"..."` literals: it marks the contents as JS string source, so (unlike
   an undelimited OCaml string) non-ASCII characters survive untouched -- and
   backslashes and quotes have to be escaped. *)
let str ~loc s =
  let buffer = Buffer.create (String.length s) in
  String.iter
    (function
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '"' -> Buffer.add_string buffer "\\\""
      | '\n' -> Buffer.add_string buffer "\\n"
      | c -> Buffer.add_char buffer c)
    s;
  pexp_constant ~loc (Pconst_string (Buffer.contents buffer, loc, Some "js"))

(* `(p1, p2, ...) => body`. ReScript 12 functions carry their arity; in the
   AST a PPX sees, that's a curried `fun p1 -> fun p2 -> body` wrapped in a
   `Function$` constructor with a `res.arity` attribute. *)
let fn ~loc params body =
  let curried =
    List.fold_right
      (fun param body -> pexp_fun ~loc Nolabel None param body)
      params body
  in
  let arity =
    attribute ~loc
      ~name:{ txt = "res.arity"; loc }
      ~payload:(PStr [ pstr_eval ~loc (eint ~loc (List.length params)) [] ])
  in
  {
    (pexp_construct ~loc { txt = Lident "Function$"; loc } (Some curried)) with
    pexp_attributes = [ arity ];
  }

(* `(t1, t2, ...) => result`, as a type. The same idea as [fn]: a curried arrow
   wrapped in `function$<_, [#Has_arityN]>`. *)
let arrow ~loc params result =
  let curried =
    List.fold_right
      (fun param result -> ptyp_arrow ~loc Nolabel param result)
      params result
  in
  let arity = Printf.sprintf "Has_arity%d" (List.length params) in
  ptyp_constr ~loc
    { txt = Lident "function$"; loc }
    [
      curried;
      ptyp_variant ~loc [ rtag ~loc { txt = arity; loc } true [] ] Closed None;
    ]

(* `f(arg1, arg2, ...)`. *)
let call ~loc f args =
  pexp_apply ~loc f (List.map (fun arg -> (Nolabel, arg)) args)

(* `PrettyPrint.name`, as a value and as a type. *)
let runtime ~loc name =
  pexp_ident ~loc { txt = Ldot (Lident "PrettyPrint", name); loc }

let doc_type ~loc =
  ptyp_constr ~loc { txt = Ldot (Lident "PrettyPrint", "doc"); loc } []

(* -- Printers for type expressions ---------------------------------------- *)

(* Built-in types and the `PrettyPrint` function printing each. Like the
   printer derived for a user-defined polymorphic type, the ones for
   `option`, `array`, ... take a printer per type argument before the value. *)
let builtin_printer = function
  | Lident
      (( "int" | "float" | "string" | "bool" | "bigint" | "unit" | "option"
       | "array" | "list" | "dict" | "result" ) as name) ->
      Some name
  | _ -> None

(* The printer derived for the type `lid` names: `foo` -> `foo_toDoc`,
   `Mod.t` -> `Mod.t_toDoc`. Located at the type reference, so when no such
   printer exists the compiler's "can't be found" error points at the type
   that's missing its `@prettyPrint`. *)
let derived_printer ~loc lid =
  match lid with
  | Lident name -> pexp_ident ~loc { txt = Lident (name ^ doc_suffix); loc }
  | Ldot (path, name) ->
      pexp_ident ~loc { txt = Ldot (path, name ^ doc_suffix); loc }
  | Lapply _ -> fail ~loc "can't print a type named by a functor application"

(* An expression of type `PrettyPrint.doc` printing `value`, which has type
   `typ`. *)
let rec to_doc (typ : core_type) (value : expression) : expression =
  let loc = typ.ptyp_loc in
  if has_attribute opaque_annotation typ.ptyp_attributes then
    call ~loc (runtime ~loc "opaque") [ value ]
  else
    match typ.ptyp_desc with
    | Ptyp_var name -> call ~loc (evar ~loc (param_printer_name name)) [ value ]
    (* A function type is a `function$<_, _>` by the time a PPX sees it (see
       [arrow]). *)
    | Ptyp_arrow _ | Ptyp_constr ({ txt = Lident "function$"; _ }, _) ->
        call ~loc (runtime ~loc "function_") [ value ]
    | Ptyp_constr ({ txt = lid; _ }, args) ->
        let printer =
          match builtin_printer lid with
          | Some name -> runtime ~loc name
          | None -> derived_printer ~loc lid
        in
        call ~loc printer (List.map printer_fn args @ [ value ])
    | Ptyp_tuple types ->
        let vars = List.map (fun _ -> fresh_var ()) types in
        let docs =
          List.map2 (fun typ var -> to_doc typ (evar ~loc var)) types vars
        in
        pexp_match ~loc value
          [
            case
              ~lhs:(ppat_tuple ~loc (List.map (pvar ~loc) vars))
              ~guard:None
              ~rhs:(call ~loc (runtime ~loc "tuple") [ pexp_array ~loc docs ]);
          ]
    | Ptyp_variant (rows, Closed, None) ->
        pexp_match ~loc value (List.map poly_variant_case rows)
    | Ptyp_variant _ ->
        fail ~loc "can't print an open polymorphic variant type"
    | _ -> fail ~loc "can't print this kind of type"

(* The printer for `typ` as a function, `typ => PrettyPrint.doc` -- what the
   printers for polymorphic types take as arguments. *)
and printer_fn (typ : core_type) : expression =
  let loc = typ.ptyp_loc in
  let var = fresh_var () in
  fn ~loc [ pvar ~loc var ] (to_doc typ (evar ~loc var))

(* `PrettyPrint.constructor("Name", [doc1, doc2, ...])`. *)
and constructor_doc ~loc name docs =
  call ~loc (runtime ~loc "constructor") [ str ~loc name; pexp_array ~loc docs ]

(* A `switch` case for a polymorphic variant's `#label(...)` tag. *)
and poly_variant_case (row : row_field) : case =
  let loc = row.prf_loc in
  match row.prf_desc with
  | Rinherit _ ->
      fail ~loc "can't print a polymorphic variant that includes another one"
  | Rtag ({ txt = label; _ }, _, args) -> (
      let name = "#" ^ label in
      match args with
      | [] ->
          case
            ~lhs:(ppat_variant ~loc label None)
            ~guard:None
            ~rhs:(constructor_doc ~loc name [])
      (* `#label(a, b)` is a tag with one tuple-typed payload. *)
      | [ { ptyp_desc = Ptyp_tuple types; ptyp_attributes = []; _ } ] ->
          let vars = List.map (fun _ -> fresh_var ()) types in
          let docs =
            List.map2 (fun typ var -> to_doc typ (evar ~loc var)) types vars
          in
          case
            ~lhs:
              (ppat_variant ~loc label
                 (Some (ppat_tuple ~loc (List.map (pvar ~loc) vars))))
            ~guard:None
            ~rhs:(constructor_doc ~loc name docs)
      | [ typ ] ->
          let var = fresh_var () in
          case
            ~lhs:(ppat_variant ~loc label (Some (pvar ~loc var)))
            ~guard:None
            ~rhs:(constructor_doc ~loc name [ to_doc typ (evar ~loc var) ])
      | _ -> fail ~loc "can't print a polymorphic variant tag with a conjunctive type")

(* -- Printers for type declarations --------------------------------------- *)

(* `PrettyPrint.record([field1, field2, ...])` for a record `value` with the
   fields `labels`. *)
let record_doc ~loc (labels : label_declaration list) (value : expression) =
  let field (label : label_declaration) =
    let loc = label.pld_loc in
    let name = label.pld_name.txt in
    (* `@prettyPrint.opaque` works on the field as well as on its type. *)
    let typ =
      if has_attribute opaque_annotation label.pld_attributes then
        {
          label.pld_type with
          ptyp_attributes =
            List.filter
              (fun attribute -> attribute.attr_name.txt = opaque_annotation)
              label.pld_attributes;
        }
      else label.pld_type
    in
    let access = pexp_field ~loc value { txt = Lident name; loc } in
    (* An optional field (`name?: typ`) is declared with the type of its
       contents, plus this attribute, but read as an `option` of it. *)
    if has_attribute "res.optional" label.pld_attributes then
      call ~loc
        (runtime ~loc "optionalField")
        [ str ~loc name; printer_fn typ; access ]
    else call ~loc (runtime ~loc "field") [ str ~loc name; to_doc typ access ]
  in
  call ~loc (runtime ~loc "record") [ pexp_array ~loc (List.map field labels) ]

(* A `switch` case for a variant's constructor. *)
let constructor_case (constructor : constructor_declaration) : case =
  let loc = constructor.pcd_loc in
  let name = constructor.pcd_name.txt in
  let lid = { txt = Lident name; loc } in
  match constructor.pcd_args with
  | Pcstr_tuple [] ->
      case
        ~lhs:(ppat_construct ~loc lid None)
        ~guard:None
        ~rhs:(constructor_doc ~loc name [])
  | Pcstr_tuple types ->
      let vars = List.map (fun _ -> fresh_var ()) types in
      let docs =
        List.map2 (fun typ var -> to_doc typ (evar ~loc var)) types vars
      in
      let args =
        match List.map (pvar ~loc) vars with
        | [ arg ] -> arg
        | args -> ppat_tuple ~loc args
      in
      case
        ~lhs:(ppat_construct ~loc lid (Some args))
        ~guard:None
        ~rhs:(constructor_doc ~loc name docs)
  (* An inline record: `Name({field: typ, ...})`. *)
  | Pcstr_record labels ->
      let var = fresh_var () in
      case
        ~lhs:(ppat_construct ~loc lid (Some (pvar ~loc var)))
        ~guard:None
        ~rhs:
          (constructor_doc ~loc name
             [ record_doc ~loc labels (evar ~loc var) ])

(* What both the generated definitions and the generated declarations need
   from an annotated type declaration. *)
type derived = {
  loc : location;
  doc_name : string;  (** `foo_toDoc` *)
  string_name : string;  (** `foo_prettyPrint` *)
  self_type : core_type;  (** `foo<'a, 'b>` *)
  params : string list;  (** `["a"; "b"]` *)
}

let derived_of_decl (decl : type_declaration) : derived option =
  if not (has_attribute annotation decl.ptype_attributes) then None
  else
    let loc = { decl.ptype_loc with loc_ghost = true } in
    let name = decl.ptype_name.txt in
    let params =
      List.map
        (fun ((param : core_type), _) ->
          match param.ptyp_desc with
          | Ptyp_var name -> name
          | _ -> fail ~loc:param.ptyp_loc "type parameters must be named")
        decl.ptype_params
    in
    Some
      {
        loc;
        doc_name = name ^ doc_suffix;
        string_name = name ^ string_suffix;
        self_type =
          ptyp_constr ~loc
            { txt = Lident name; loc }
            (List.map (ptyp_var ~loc) params);
        params;
      }

(* Generated values go unused whenever the type's module has an interface
   that doesn't expose them (32), a printer never calls the one it's given for
   a phantom type parameter (27), and `type rec` doesn't always translate to
   printers that actually recurse (39). *)
let silence_warnings ~loc =
  attribute ~loc ~name:{ txt = "warning"; loc }
    ~payload:(PStr [ pstr_eval ~loc (str ~loc "-27-32-39") [] ])

(* The parameters every generated function takes: a printer per type
   parameter, then the value. Returned with the expressions referring back to
   them. *)
let fn_params { loc; self_type; params; _ } =
  let printers = List.map param_printer_name params in
  ( List.map (pvar ~loc) printers
    @ [ ppat_constraint ~loc (pvar ~loc "v") self_type ],
    List.map (evar ~loc) printers @ [ evar ~loc "v" ] )

(* `let foo_toDoc = (v: foo) => ...` *)
let doc_binding (decl : type_declaration) (derived : derived) : value_binding =
  let loc = derived.loc in
  let value = evar ~loc "v" in
  let body =
    match (decl.ptype_kind, decl.ptype_manifest) with
    | Ptype_record labels, _ -> record_doc ~loc labels value
    | Ptype_variant constructors, _ ->
        pexp_match ~loc value (List.map constructor_case constructors)
    | Ptype_abstract, Some manifest -> to_doc manifest value
    | Ptype_abstract, None ->
        fail ~loc:decl.ptype_loc "can't print an abstract type"
    | Ptype_open, _ -> fail ~loc:decl.ptype_loc "can't print an extensible type"
  in
  let params, _ = fn_params derived in
  {
    (value_binding ~loc ~pat:(pvar ~loc derived.doc_name)
       ~expr:(fn ~loc params body))
    with
    pvb_attributes = [ silence_warnings ~loc ];
  }

(* `let foo_prettyPrint = (v: foo) => PrettyPrint.render(foo_toDoc(v))` *)
let string_binding (derived : derived) : value_binding =
  let loc = derived.loc in
  let params, args = fn_params derived in
  let doc = call ~loc (evar ~loc derived.doc_name) args in
  {
    (value_binding ~loc
       ~pat:(pvar ~loc derived.string_name)
       ~expr:(fn ~loc params (call ~loc (runtime ~loc "render") [ doc ])))
    with
    pvb_attributes = [ silence_warnings ~loc ];
  }

(* The definitions to add after `type ... and ...` in an implementation.
   `<type>_toDoc` functions share the declaration's `rec` flag, since they
   refer to each other exactly where the types do. *)
let derive_structure ~loc rec_flag (decls : type_declaration list) :
    structure_item list =
  let annotated =
    List.filter_map
      (fun decl ->
        Option.map (fun derived -> (decl, derived)) (derived_of_decl decl))
      decls
  in
  match annotated with
  | [] -> []
  | _ ->
      let loc = { loc with loc_ghost = true } in
      [
        pstr_value ~loc rec_flag
          (List.map (fun (decl, derived) -> doc_binding decl derived) annotated);
        pstr_value ~loc Nonrecursive
          (List.map (fun (_, derived) -> string_binding derived) annotated);
      ]

(* The declarations to add after `type ... and ...` in an interface:
   `let foo_toDoc: foo => PrettyPrint.doc` and
   `let foo_prettyPrint: foo => string`. *)
let derive_signature (decls : type_declaration list) : signature_item list =
  decls
  |> List.filter_map derived_of_decl
  |> List.concat_map (fun { loc; doc_name; string_name; self_type; params } ->
         let fn_type result =
           let param_printer name =
             arrow ~loc [ ptyp_var ~loc name ] (doc_type ~loc)
           in
           arrow ~loc (List.map param_printer params @ [ self_type ]) result
         in
         let declare name result =
           psig_value ~loc
             (value_description ~loc ~name:{ txt = name; loc }
                ~type_:(fn_type result) ~prim:[])
         in
         [
           declare doc_name (doc_type ~loc);
           declare string_name
             (ptyp_constr ~loc { txt = Lident "string"; loc } []);
         ])

(* -- The transformation --------------------------------------------------- *)

(* Walks the whole file (so declarations in nested modules are found too),
   appending the generated items after each annotated type declaration. *)
let mapper =
  object
    inherit Ast_traverse.map as super

    method! structure items =
      super#structure items
      |> List.concat_map (fun (item : structure_item) ->
             match item.pstr_desc with
             | Pstr_type (rec_flag, decls) ->
                 item :: derive_structure ~loc:item.pstr_loc rec_flag decls
             | _ -> [ item ])

    method! signature items =
      super#signature items
      |> List.concat_map (fun (item : signature_item) ->
             match item.psig_desc with
             | Psig_type (_, decls) -> item :: derive_signature decls
             | _ -> [ item ])
  end

let () =
  Driver.register_transformation annotation ~impl:mapper#structure
    ~intf:mapper#signature
