(* A ReScript PPX for Weft's component attribute, `@weft.component`.

   {[
     @weft.component                          // a shared component
     @weft.component({kind: Server})          // runs only on the server
     @weft.component({kind: Entrypoint})      // where client code starts
   ]}

   bsc runs a PPX listed in `ppx-flags` before its own JSX transform, so
   whatever this leaves behind is what the transform sees. Each
   `@weft.component` becomes a plain `@jsx.component`, and then, by kind
   (docs/weft_server_components_plan.md, section 2):

   - Shared: nothing else.
   - Server: an `async` component is rewritten into a synchronous one
     returning a `WeftCore.Lazy` element around its body's promise, since the
     JSX transform wraps an async component in the standard library's
     `Jsx.promise`, which doesn't fit Weft's element type:

     {[
       let make = async (~id) => body
       // becomes
       let make = (~id) => WeftCore.Lazy.fromPromise((async () => body)())
     ]}

     The file gets `@@directive("'use weft server'")`.
   - Entrypoint: right after the binding,

     {[
       let () = WeftCore.Entrypoint.mark(make, "<package>/<path>#<Module.Path>")
     ]}

     marks the component the JSX transform defines last (the props-taking
     `make` that `jsx` receives) with an id the client can load it by: the
     package's name and the file's path from its root (from the nearest
     `rescript.json`), then the path of modules inside the file to the
     `make` (empty for the file's own). The file gets
     `@@directive("'use weft entrypoint'")`.

   Mistakes are compile errors rather than something silently ignored:

   - the argument is absent, or a record with one field, `kind`, whose value
     is `Server` or `Entrypoint`;
   - the attribute is on a `let` binding (or, in an interface, a `let`
     declaration), the only places the JSX transform looks, at most once, and
     not together with `@jsx.component`;
   - only a server component may be `async`;
   - a file has server components or entrypoints, not both (an entrypoint's
     file goes to the browser, and a server component's must not);
   - an entrypoint is a binding named `make` (what the client looks up),
     whose labelled arguments aren't written with function types (its props
     come from the server, serialized, and functions can't be). The check is
     syntactic: it can't see through a type alias.

   In an interface file only the attribute is replaced: the signature of a
   rewritten async server component is already `(~id: string) => element`.

   The compiler ignores attributes it doesn't know, so without this PPX in
   `ppx-flags`, `@weft.component` would be dropped and the component left
   without the `props` type JSX needs: every use of it would then fail to
   type-check, with an error about `component<'a>` that doesn't mention the
   PPX.

   It also handles Weft RPCs (section 8 of the plan):

   {[
     @weft.rpc({id: "notes.addComment"})
     let addComment = WeftServer.Rpc.make(~request=...)
     // becomes
     let addComment = WeftServer.Rpc.make(~request=..., ~id="notes.addComment")
   ]}

   after checking the ID is names separated by dots, each a letter then
   letters, digits and `_`. The file gets a `'use weft rpc <id>'` directive
   for each, beside any `'use weft entrypoint'` one, from which the Vite
   plugin collects the app's IDs. And a file with `@@weft.server` gets
   `'use weft server'` whatever it has, so the client can't import it.

   The mistakes for these: `@weft.rpc` with anything but `{id: "<literal>"}`,
   an ID that isn't one, given twice in a file, on something other than a
   `let` of `WeftServer.Rpc.make(...)` (or `makePrepared`), twice, or in a
   server file (which the client can't import, so its declarations would be
   no use); `@@weft.server` anywhere but at the top level, or in a file with
   entrypoints.

   A note on the AST. bsc hands a PPX a frozen, OCaml 4.06-shaped version of
   its parsetree (`Parsetree0` in the compiler's sources), with ReScript-only
   constructs encoded: a function `(a, b) => body` is `fun a -> fun b -> body`
   under a `Function$` constructor carrying `[@res.arity 2]`, with
   `[@res.async]` on the `fun` when it's async; a function type is wrapped in
   `function$<_, [#Has_arityN]>`; a string literal has the delimiter "js".
   See `compiler/ml/ast_mapper_to0.ml` in the ReScript repo. *)

open Ppxlib
open Ast_builder.Default

let name = "weft.component"
let jsx_name = "jsx.component"

let fail ~loc fmt = Location.raise_errorf ~loc ("@%s: " ^^ fmt) name

type kind = Shared | Server | Entrypoint

let usage = "takes no argument, {kind: Server} or {kind: Entrypoint}"

(* The kind an attribute's argument names. ReScript's `{kind: Server}` reaches
   a PPX as an OCaml record expression `{ kind = Server }`. *)
let kind_of_payload ~loc = function
  | PStr [] -> Shared
  | PStr
      [
        {
          pstr_desc =
            Pstr_eval
              ( {
                  pexp_desc =
                    Pexp_record ([ ({ txt = Lident "kind"; _ }, value) ], None);
                  _;
                },
                _ );
          _;
        };
      ] -> (
      match value.pexp_desc with
      | Pexp_construct ({ txt = Lident "Server"; _ }, None) -> Server
      | Pexp_construct ({ txt = Lident "Entrypoint"; _ }, None) -> Entrypoint
      | Pexp_construct ({ txt; _ }, None) ->
          fail ~loc:value.pexp_loc "unknown kind `%s`: it's Server or Entrypoint"
            (Longident.name txt)
      | _ -> fail ~loc:value.pexp_loc "the kind is Server or Entrypoint")
  | _ -> fail ~loc "%s" usage

let is_named n attribute = String.equal attribute.attr_name.txt n

(* The `@weft.component` among a binding's attributes, if any, with its kind,
   and the attributes with it replaced by `@jsx.component`. *)
let rewrite_attributes attributes =
  match List.filter (is_named name) attributes with
  | [] -> None
  | _ :: second :: _ -> fail ~loc:second.attr_loc "is given twice"
  | [ attribute ] ->
      (match List.find_opt (is_named jsx_name) attributes with
      | Some jsx ->
          fail ~loc:jsx.attr_loc
            "replaces @%s, so a binding can't have both" jsx_name
      | None -> ());
      let kind = kind_of_payload ~loc:attribute.attr_loc attribute.attr_payload in
      let attributes =
        List.map
          (fun a ->
            if is_named name a then
              {
                a with
                attr_name = { a.attr_name with txt = jsx_name };
                attr_payload = PStr [];
              }
            else a)
          attributes
      in
      Some (kind, attribute.attr_loc, attributes)

(* -- ReScript-flavored AST helpers ---------------------------------------- *)

(* A string literal, as ReScript's parser writes one: with the "js"
   delimiter, which marks the contents as JS string source (so quotes and
   backslashes are escaped). *)
let str ~loc s =
  let buffer = Buffer.create (String.length s) in
  String.iter
    (function
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '"' -> Buffer.add_string buffer "\\\""
      | c -> Buffer.add_char buffer c)
    s;
  pexp_constant ~loc (Pconst_string (Buffer.contents buffer, loc, Some "js"))

let arity_attribute ~loc n =
  attribute ~loc ~name:{ txt = "res.arity"; loc }
    ~payload:(PStr [ pstr_eval ~loc (eint ~loc n) [] ])

let has_attribute n attributes = List.exists (is_named n) attributes

(* `() => body`, async, as ReScript encodes it. *)
let async_thunk ~loc body =
  let fn =
    pexp_fun ~loc Nolabel None (punit ~loc) body
    |> fun e ->
    {
      e with
      pexp_attributes =
        [ attribute ~loc ~name:{ txt = "res.async"; loc } ~payload:(PStr []) ];
    }
  in
  {
    (pexp_construct ~loc { txt = Lident "Function$"; loc } (Some fn)) with
    pexp_attributes = [ arity_attribute ~loc 1 ];
  }

(* `@@directive("'<text>'")`: the compiled file's first line is the JS
   directive `'<text>'`. (bsc writes the string verbatim, so it carries its
   own quotes.) *)
let directive ~loc text =
  pstr_attribute ~loc
    (attribute ~loc ~name:{ txt = "directive"; loc }
       ~payload:(PStr [ pstr_eval ~loc (str ~loc ("'" ^ text ^ "'")) [] ]))

(* -- Component functions -------------------------------------------------- *)

(* The `fun` inside a component's `Function$` wrapper, and a way to put a
   rewritten one back. *)
let split_function expr =
  match expr.pexp_desc with
  | Pexp_construct (({ txt = Lident "Function$"; _ } as constr), Some fn) ->
      Some (fn, fun fn -> { expr with pexp_desc = Pexp_construct (constr, Some fn) })
  | _ -> None

let is_async fn = has_attribute "res.async" fn.pexp_attributes

(* Rewrites `async (~a, ~b) => body` into
   `(~a, ~b) => WeftCore.Lazy.fromPromise((async () => body)())`. *)
let rewrite_async fn =
  let attributes =
    List.filter (fun a -> not (is_named "res.async" a)) fn.pexp_attributes
  in
  let rec go expr =
    match expr.pexp_desc with
    | Pexp_fun (label, default, pattern, body) ->
        { expr with pexp_desc = Pexp_fun (label, default, pattern, go body) }
    | _ ->
        let loc = expr.pexp_loc in
        eapply ~loc
          (evar ~loc "WeftCore.Lazy.fromPromise")
          [ eapply ~loc (async_thunk ~loc expr) [ eunit ~loc ] ]
  in
  { (go fn) with pexp_attributes = attributes }

(* A function type, or an option of one, as written. *)
let rec function_type typ =
  match typ.ptyp_desc with
  | Ptyp_constr ({ txt = Lident "function$"; _ }, _) | Ptyp_arrow _ -> Some typ
  | Ptyp_constr ({ txt = Lident "option"; _ }, [ inner ]) -> function_type inner
  | _ -> None

(* Fails on a labelled argument written with a function type. *)
let rec check_props fn =
  match fn.pexp_desc with
  | Pexp_fun ((Labelled label | Optional label), _, pattern, body) ->
      (match pattern.ppat_desc with
      | Ppat_constraint (_, typ) -> (
          match function_type typ with
          | Some typ ->
              fail ~loc:typ.ptyp_loc
                "an entrypoint's props come from the server, so they can't be \
                 functions: `~%s` is one"
                label
          | None -> ())
      | _ -> ());
      check_props body
  | Pexp_fun (Nolabel, _, _, body) -> check_props body
  | _ -> ()

let binding_name binding =
  match binding.pvb_pat.ppat_desc with
  | Ppat_var { txt; _ } | Ppat_constraint ({ ppat_desc = Ppat_var { txt; _ }; _ }, _)
    ->
      Some txt
  | _ -> None

(* -- Ids ------------------------------------------------------------------ *)

let read_file path = In_channel.with_open_bin path In_channel.input_all

(* The value of the first `"name": "..."` in a `rescript.json`. Enough JSON
   for that file, whose `name` is a plain string. *)
let package_name ~loc config_path =
  let text = read_file config_path in
  let fail () = fail ~loc "%s has no \"name\"" config_path in
  let key = "\"name\"" in
  let rec find from =
    match String.index_from_opt text from '"' with
    | None -> fail ()
    | Some i ->
        if i + String.length key <= String.length text
           && String.sub text i (String.length key) = key
        then i + String.length key
        else find (i + 1)
  in
  let after_key = find 0 in
  let rec skip i = if i < String.length text && text.[i] <> '"' then skip (i + 1) else i in
  let start = skip (after_key + 1) in
  match String.index_from_opt text (start + 1) '"' with
  | Some stop when start < String.length text ->
      String.sub text (start + 1) (stop - start - 1)
  | _ -> fail ()

(* `<package name>/<path from the package root>`, for the file being
   compiled, from the nearest `rescript.json` above it. *)
let file_id ~loc =
  let file = loc.loc_start.pos_fname in
  let file =
    if Filename.is_relative file then Filename.concat (Sys.getcwd ()) file else file
  in
  let rec find dir rel =
    let config = Filename.concat dir "rescript.json" in
    if Sys.file_exists config then package_name ~loc config ^ "/" ^ rel
    else
      let parent = Filename.dirname dir in
      if parent = dir then
        fail ~loc "found no rescript.json above %s, to name the entrypoint by" file
      else find parent (Filename.basename dir ^ "/" ^ rel)
  in
  find (Filename.dirname file) (Filename.basename file)

(* -- RPCs ----------------------------------------------------------------- *)

let rpc_name = "weft.rpc"
let server_name = "weft.server"

let fail_rpc ~loc fmt = Location.raise_errorf ~loc ("@%s: " ^^ fmt) rpc_name

let is_letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_name_char c = is_letter c || (c >= '0' && c <= '9') || c = '_'

(* Names separated by dots, each a letter then letters, digits and `_`: what
   `WeftServer.Rpc.isValidId` accepts. *)
let valid_rpc_id id =
  id <> ""
  && List.for_all
       (fun name ->
         name <> "" && is_letter name.[0] && String.for_all is_name_char name)
       (String.split_on_char '.' id)

(* The ID in `@weft.rpc({id: "..."})`. *)
let rpc_id_of_payload ~loc = function
  | PStr
      [
        {
          pstr_desc =
            Pstr_eval
              ( {
                  pexp_desc =
                    Pexp_record ([ ({ txt = Lident "id"; _ }, value) ], None);
                  _;
                },
                _ );
          _;
        };
      ] -> (
      match value.pexp_desc with
      | Pexp_constant (Pconst_string (id, _, _)) ->
          if valid_rpc_id id then id
          else
            fail_rpc ~loc:value.pexp_loc
              "\"%s\" isn't an RPC ID: it's names separated by dots, each a \
               letter then letters, digits and _ (notes.addComment, say)"
              id
      | _ ->
          fail_rpc ~loc:value.pexp_loc
            "the ID is a string literal, so it's the same in every build")
  | _ -> fail_rpc ~loc "takes the RPC's ID: @weft.rpc({id: \"notes.addComment\"})"

(* The `@weft.rpc` among a binding's attributes, if any, with its ID, and the
   attributes without it. *)
let rpc_attribute attributes =
  match List.filter (is_named rpc_name) attributes with
  | [] -> None
  | _ :: second :: _ -> fail_rpc ~loc:second.attr_loc "is given twice"
  | [ attribute ] ->
      let id = rpc_id_of_payload ~loc:attribute.attr_loc attribute.attr_payload in
      Some
        ( id,
          attribute.attr_loc,
          List.filter (fun a -> not (is_named rpc_name a)) attributes )

let is_rpc_make = function
  | Ldot (Lident "Rpc", ("make" | "makePrepared"))
  | Ldot (Ldot (_, "Rpc"), ("make" | "makePrepared")) ->
      true
  | _ -> false

(* `WeftServer.Rpc.make(...)` (under any type annotations) with `~id` added. *)
let rec add_rpc_id ~loc id expr =
  match expr.pexp_desc with
  | Pexp_constraint (inner, typ) ->
      { expr with pexp_desc = Pexp_constraint (add_rpc_id ~loc id inner, typ) }
  | Pexp_apply (({ pexp_desc = Pexp_ident { txt; _ }; _ } as callee), args)
    when is_rpc_make txt ->
      if List.exists (function Labelled "id", _ -> true | _ -> false) args then
        fail_rpc ~loc "passes the ID itself, so `~id` can't be given too";
      let gloc = { expr.pexp_loc with loc_ghost = true } in
      {
        expr with
        pexp_desc = Pexp_apply (callee, args @ [ (Labelled "id", str ~loc:gloc id) ]);
      }
  | _ ->
      fail_rpc ~loc
        "goes on a `let` whose value is `WeftServer.Rpc.make(...)` (or \
         `WeftServer.Rpc.makePrepared(...)`)"

(* -- The rewrite ---------------------------------------------------------- *)

(* What a file has, so far: the first server component and the first
   entrypoint (where they are), to keep the two apart. *)
type file = {
  mutable server : location option;
  mutable entrypoint : location option;
  mutable id : string option;
  (* `@@weft.server`, if the file has it. *)
  mutable server_only : location option;
  (* Each RPC declared, in order, and where. *)
  mutable rpcs : (string * location) list;
}

let note_kind file ~loc = function
  | Shared -> ()
  | Server -> (
      match file.entrypoint with
      | Some other ->
          fail ~loc
            "a file has server components or entrypoints, not both: this file \
             has an entrypoint at line %d"
            other.loc_start.pos_lnum
      | None -> if file.server = None then file.server <- Some loc)
  | Entrypoint -> (
      (match file.server_only with
      | Some server_only ->
          fail ~loc
            "an entrypoint is loaded by the client, so it can't be in a file \
             marked server-only (@@@@weft.server, at line %d)"
            server_only.loc_start.pos_lnum
      | None -> ());
      match file.server with
      | Some other ->
          fail ~loc
            "a file has server components or entrypoints, not both: this file \
             has a server component at line %d"
            other.loc_start.pos_lnum
      | None -> if file.entrypoint = None then file.entrypoint <- Some loc)

let file_id_once file ~loc =
  match file.id with
  | Some id -> id
  | None ->
      let id = file_id ~loc in
      file.id <- Some id;
      id

let rewriter () =
  let file =
    { server = None; entrypoint = None; id = None; server_only = None; rpcs = [] }
  in
  (* The modules the traversal is inside, innermost first. *)
  let modules = ref [] in
  (* Rewrites one binding, returning it and, for an entrypoint, the
     statement that marks it. *)
  let rewrite_rpc binding =
    match rpc_attribute binding.pvb_attributes with
    | None -> binding
    | Some (id, loc, attributes) ->
        if has_attribute name attributes then
          fail_rpc ~loc "is for an RPC, so a binding can't have @%s too" name;
        (match List.assoc_opt id file.rpcs with
        | Some other ->
            fail_rpc ~loc "the ID %s is already this file's RPC at line %d" id
              other.loc_start.pos_lnum
        | None -> ());
        file.rpcs <- file.rpcs @ [ (id, loc) ];
        {
          binding with
          pvb_attributes = attributes;
          pvb_expr = add_rpc_id ~loc id binding.pvb_expr;
        }
  in
  let rewrite_binding binding =
    let binding = rewrite_rpc binding in
    match rewrite_attributes binding.pvb_attributes with
    | None -> (binding, None)
    | Some (kind, loc, attributes) ->
        note_kind file ~loc kind;
        let binding = { binding with pvb_attributes = attributes } in
        let fn = split_function binding.pvb_expr in
        let async = match fn with Some (fn, _) -> is_async fn | None -> false in
        (match kind with
        | Shared when async ->
            fail ~loc "only a server component can be async, and this one is shared"
        | Entrypoint when async ->
            fail ~loc
              "only a server component can be async, and this one is an entrypoint"
        | _ -> ());
        (match kind, fn with
        | Server, Some (fn, rebuild) when async ->
            ({ binding with pvb_expr = rebuild (rewrite_async fn) }, None)
        | Entrypoint, _ ->
            (match binding_name binding with
            | Some "make" -> ()
            | _ ->
                fail ~loc
                  "an entrypoint is a binding named `make`, which is what the \
                   client loads");
            Option.iter (fun (fn, _) -> check_props fn) fn;
            let id =
              file_id_once file ~loc ^ "#"
              ^ String.concat "." (List.rev !modules)
            in
            let gloc = { binding.pvb_loc with loc_ghost = true } in
            let mark =
              pstr_value ~loc:gloc Nonrecursive
                [
                  value_binding ~loc:gloc ~pat:(punit ~loc:gloc)
                    ~expr:
                      (eapply ~loc:gloc
                         (evar ~loc:gloc "WeftCore.Entrypoint.mark")
                         [ evar ~loc:gloc "make"; str ~loc:gloc id ]);
                ]
            in
            (binding, Some mark)
        | _ -> (binding, None))
  in
  object (self)
    inherit Ast_traverse.map as super

    method! module_binding binding =
      let name = Option.value binding.pmb_name.txt ~default:"_" in
      modules := name :: !modules;
      let binding = super#module_binding binding in
      modules := List.tl !modules;
      binding

    method! structure items =
      List.concat_map
        (fun item ->
          match item.pstr_desc with
          | Pstr_value (rec_flag, bindings) ->
              let rewritten = List.map rewrite_binding bindings in
              let item =
                {
                  item with
                  pstr_desc =
                    Pstr_value
                      ( rec_flag,
                        List.map (fun (b, _) -> super#value_binding b) rewritten );
                }
              in
              item :: List.filter_map snd rewritten
          | Pstr_attribute attribute when is_named server_name attribute ->
              if !modules <> [] then
                Location.raise_errorf ~loc:attribute.attr_loc
                  "@@@@%s: marks a whole file, so it goes at its top level, not \
                   in a module"
                  server_name;
              (match attribute.attr_payload with
              | PStr [] -> ()
              | _ ->
                  Location.raise_errorf ~loc:attribute.attr_loc
                    "@@@@%s: takes no argument" server_name);
              if file.server_only = None then
                file.server_only <- Some attribute.attr_loc;
              []
          | _ -> [ self#structure_item item ])
        items

    method! value_description description =
      match rewrite_attributes description.pval_attributes with
      | None -> super#value_description description
      | Some (_, _, attributes) ->
          super#value_description { description with pval_attributes = attributes }

    (* Every `@weft.component` in a place handled above has been replaced
       before the traversal gets here, so any it still finds is somewhere the
       JSX transform wouldn't look. *)
    method! attribute attribute =
      if is_named name attribute then
        fail ~loc:attribute.attr_loc
          "goes on a `let` binding of a component (or its declaration in an \
           interface)"
      else if is_named rpc_name attribute then
        fail_rpc ~loc:attribute.attr_loc
          "goes on a `let` whose value is `WeftServer.Rpc.make(...)`, in an \
           implementation"
      else if is_named server_name attribute then
        Location.raise_errorf ~loc:attribute.attr_loc
          "@@@@%s: marks a whole file, so it goes at the top level of an \
           implementation, as `@@@@%s`"
          server_name server_name
      else super#attribute attribute

    (* The whole file: rewritten, then given the directive for what it has. *)
    method file items =
      let items = self#structure items in
      let loc = Location.none in
      let server =
        match file.server, file.server_only with
        | Some loc, _ | None, Some loc -> Some loc
        | None, None -> None
      in
      (match server, file.entrypoint, file.server_only with
      | _, Some entrypoint, Some server_only ->
          Location.raise_errorf ~loc:server_only
            "@@@@%s: this file has an entrypoint (line %d), which the client \
             loads, so it can't be server-only"
            server_name entrypoint.loc_start.pos_lnum
      | _ -> ());
      (match server, file.rpcs with
      | Some _, (_, rpc_loc) :: _ ->
          fail_rpc ~loc:rpc_loc
            "the client can't import a server file, so an RPC is declared in a \
             shared one (its handler goes in the server file)"
      | _ -> ());
      let rpcs =
        List.map (fun (id, _) -> directive ~loc ("use weft rpc " ^ id)) file.rpcs
      in
      match server, file.entrypoint with
      | Some _, _ -> directive ~loc "use weft server" :: items
      | _, Some _ -> (directive ~loc "use weft entrypoint" :: rpcs) @ items
      | None, None -> rpcs @ items
  end

let () =
  Driver.register_transformation "ppx_weft"
    ~impl:(fun items -> (rewriter ())#file items)
    ~intf:(fun items -> (rewriter ())#signature items)
