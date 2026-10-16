type rec doc =
  | Text(string)
  /** `label: value` */
  | Labeled(string, doc)
  /**
  `prefix` + `opening` + comma-separated `items` + `closing` -- everything
  with elements: `{...}`, `[...]`, `Name(...)`, `list{...}`. The only kind of
  doc `render` can break across lines.
  */
  | Group({prefix: string, opening: string, closing: string, items: array<doc>})

type field = option<(string, doc)>

let rec flat = doc =>
  switch doc {
  | Text(s) => s
  | Labeled(label, value) => `${label}: ${flat(value)}`
  | Group({prefix, opening, closing, items}) =>
    prefix ++ opening ++ items->Array.map(flat)->Array.join(", ") ++ closing
  }

/*
Lays out `doc`, which starts at `column` on a line indented by `indent`, and
is followed on its last line by `trailing` more characters (the `,` after an
element, or an enclosing group's closing delimiter).

Simple rather than fast: `flat` re-renders a doc's whole subtree at every
level that doesn't fit, so this is quadratic in nesting depth. A real
pretty-printer (Wadler's, say) would measure as it goes.
*/
let rec layout = (doc, ~width, ~indent, ~column, ~trailing) => {
  let oneLine = flat(doc)
  if column + String.length(oneLine) + trailing <= width {
    oneLine
  } else {
    switch doc {
    | Text(_) | Group({items: []}) => oneLine
    | Labeled(label, value) =>
      `${label}: ` ++
      layout(value, ~width, ~indent, ~column=column + String.length(label) + 2, ~trailing)
    // A lone group inside another -- `Some({...})`, `Rect({...})` -- hugs its
    // parent's delimiters instead of getting a line and an indent of its own.
    | Group({prefix, opening, closing, items: [Group(_) as only]}) =>
      let head = prefix ++ opening
      head ++
      layout(
        only,
        ~width,
        ~indent,
        ~column=column + String.length(head),
        ~trailing=trailing + String.length(closing),
      ) ++
      closing
    | Group({prefix, opening, closing, items}) =>
      let inner = indent + 2
      let lines =
        items->Array.map(item =>
          " "->String.repeat(inner) ++
          layout(item, ~width, ~indent=inner, ~column=inner, ~trailing=1) ++ ",\n"
        )
      prefix ++ opening ++ "\n" ++ lines->Array.join("") ++ " "->String.repeat(indent) ++ closing
    }
  }
}

let render = (~width=80, doc) => layout(doc, ~width, ~indent=0, ~column=0, ~trailing=0)

let text = s => Text(s)

let group = (~prefix="", opening, closing, items) => Group({prefix, opening, closing, items})

let quote = s => JSON.stringify(JSON.Encode.string(s))

let int = n => Text(Int.toString(n))

// `1.0`, not `1`: keeps a float distinguishable from an int, as in ReScript source.
let float = f => {
  let s = Float.toString(f)
  Text(
    Float.isFinite(f) && Float.toInt(f)->Int.toFloat == f && !String.includes(s, "e")
      ? s ++ ".0"
      : s,
  )
}

let string = s => Text(quote(s))
let bool = b => Text(b ? "true" : "false")
let bigint = n => Text(BigInt.toString(n) ++ "n")
let unit = () => Text("()")

let function_ = _ => Text("<fun>")
let opaque = _ => Text("<opaque>")

let tuple = items => group("(", ")", items)

let constructor = (name, args) =>
  switch args {
  | [] => Text(name)
  | _ => group(~prefix=name, "(", ")", args)
  }

let option = (toDoc, value) =>
  switch value {
  | Some(v) => constructor("Some", [toDoc(v)])
  | None => Text("None")
  }

let result = (okToDoc, errorToDoc, value) =>
  switch value {
  | Ok(v) => constructor("Ok", [okToDoc(v)])
  | Error(e) => constructor("Error", [errorToDoc(e)])
  }

let array = (toDoc, items) => group("[", "]", items->Array.map(toDoc))

let list = (toDoc, items) => group(~prefix="list", "{", "}", items->List.toArray->Array.map(toDoc))

let dict = (toDoc, entries) =>
  group(
    ~prefix="dict",
    "{",
    "}",
    entries->Dict.toArray->Array.map(((key, value)) => Labeled(quote(key), toDoc(value))),
  )

let field = (name, doc) => Some((name, doc))

let optionalField = (name, toDoc, value) => value->Option.map(v => (name, toDoc(v)))

let record = fields =>
  group(
    "{",
    "}",
    fields->Array.filterMap(field => field->Option.map(((name, doc)) => Labeled(name, doc))),
  )
