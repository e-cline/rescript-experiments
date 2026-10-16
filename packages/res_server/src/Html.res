type t = string

let escape = (text: string): string =>
  text
  ->String.replaceAll("&", "&amp;")
  ->String.replaceAll("<", "&lt;")
  ->String.replaceAll(">", "&gt;")
  ->String.replaceAll("\"", "&quot;")
  ->String.replaceAll("'", "&#39;")

let text = (text: string): t => escape(text)

let url = (url: string): t => {
  // What a browser makes of it: tabs and newlines anywhere in a URL are
  // dropped, and so are spaces and control characters before it.
  let cleaned =
    url->String.replaceRegExp(/[\t\n\r]/g, "")->String.replaceRegExp(/^[\x00-\x20]+/, "")
  let hasScheme = /^[a-zA-Z][a-zA-Z0-9+.\-]*:/->RegExp.test(cleaned)
  let isAllowed = /^(https?|mailto|tel):/i->RegExp.test(cleaned)
  escape(!hasScheme || isAllowed ? cleaned : "about:invalid")
}

let json = (value: JSON.t): t =>
  JSON.stringify(value)
  ->String.replaceAll("<", "\\u003c")
  ->String.replaceAll(">", "\\u003e")
  ->String.replaceAll("&", "\\u0026")
  ->String.replaceAll("\u2028", "\\u2028")
  ->String.replaceAll("\u2029", "\\u2029")

let raw = (markup: string): t => markup

let int = (value: int): t => Int.toString(value)

let empty: t = ""

let join = (parts: array<t>, ~separator: t=""): t => parts->Array.join(separator)

let html = (strings: array<string>, values: array<t>): t =>
  strings
  ->Array.mapWithIndex((string, index) => string ++ values->Array.get(index)->Option.getOr(""))
  ->Array.join("")

let toString = (html: t): string => html
