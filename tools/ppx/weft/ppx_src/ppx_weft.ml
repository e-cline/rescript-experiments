(* A ReScript PPX for Weft's component attribute, `@weft.component`.

   {[
     @weft.component                          // a shared component
     @weft.component({kind: Server})          // runs only on the server
     @weft.component({kind: Entrypoint})      // where client code starts
   ]}

   bsc runs a PPX listed in `ppx-flags` before its own JSX transform, so
   whatever this leaves behind is what the transform sees. For now (phase 0 of
   docs/weft_server_components_plan.md) it replaces each `@weft.component`,
   whatever its kind, with a plain `@jsx.component`: every kind compiles as a
   shared component, exactly as `@jsx.component` would. What makes the kinds
   different (rewriting async server components, marking entrypoints, the
   file directives) comes in phase 2.

   It already checks how the attribute is used, so a mistake is a compile error
   rather than something silently ignored:

   - its argument is either absent or a record with one field, `kind`, whose
     value is `Server` or `Entrypoint`;
   - it's on a `let` binding (or, in an interface, a `let` declaration), the
     only places the JSX transform looks;
   - a binding has it at most once, and not together with `@jsx.component`.

   The compiler itself ignores attributes it doesn't know, so without this
   PPX in `ppx-flags`, `@weft.component` would be dropped and the component
   left without the `props` type JSX needs: every use of it would then fail to
   type-check, with an error about `component<'a>` that doesn't mention the
   PPX. *)

open Ppxlib

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

(* Replaces a binding's `@weft.component` with `@jsx.component`. Returns the
   attributes unchanged if it has none. *)
let rewrite_attributes attributes =
  match List.filter (is_named name) attributes with
  | [] -> attributes
  | _ :: second :: _ -> fail ~loc:second.attr_loc "is given twice"
  | [ attribute ] ->
      (match List.find_opt (is_named jsx_name) attributes with
      | Some jsx ->
          fail ~loc:jsx.attr_loc
            "replaces @%s, so a binding can't have both" jsx_name
      | None -> ());
      let (_ : kind) = kind_of_payload ~loc:attribute.attr_loc attribute.attr_payload in
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

let rewriter =
  object
    inherit Ast_traverse.map as super

    method! value_binding binding =
      super#value_binding
        { binding with pvb_attributes = rewrite_attributes binding.pvb_attributes }

    method! value_description description =
      super#value_description
        {
          description with
          pval_attributes = rewrite_attributes description.pval_attributes;
        }

    (* Every `@weft.component` in a place handled above has been replaced
       before the traversal gets here, so any it still finds is somewhere the
       JSX transform wouldn't look. *)
    method! attribute attribute =
      if is_named name attribute then
        fail ~loc:attribute.attr_loc
          "goes on a `let` binding of a component (or its declaration in an \
           interface)"
      else super#attribute attribute
  end

let () =
  Driver.register_transformation "ppx_weft" ~impl:rewriter#structure
    ~intf:rewriter#signature
