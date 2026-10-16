/***
The runtime half of the `@prettyPrint` PPX (see ../ppx_src/ppx_pretty_print.ml): the functions the
code it generates calls. Fine to use directly too -- e.g. to hand-write a `<type>_toDoc` printer for
a type the PPX can't derive one for.
*/

/**
A value's printed form, before deciding where its line breaks go. Built by the
functions below; turned into a string by `render`.
*/
type doc

/**
Lays `doc` out as ReScript-like syntax. Anything that fits within `width`
columns (default 80) stays on one line; a record, constructor, array, ... that
doesn't is broken into one indented line per element.
*/
let render: (~width: int=?, doc) => string

/** `s`, verbatim -- the building block for hand-written printers. */
let text: string => doc

let int: int => doc
let float: float => doc
let string: string => doc
let bool: bool => doc
let bigint: bigint => doc
let unit: unit => doc

/*
Printers for types with parameters take a printer per type parameter, then the
value -- the same shape the PPX derives for a user-defined `type t<'a>`.
*/

let option: ('a => doc, option<'a>) => doc
let array: ('a => doc, array<'a>) => doc
let list: ('a => doc, list<'a>) => doc
let dict: ('a => doc, dict<'a>) => doc
let result: ('ok => doc, 'error => doc, result<'ok, 'error>) => doc

/** `<fun>` -- what a function-typed value prints as. */
let function_: 'a => doc

/** `<opaque>` -- what a value marked `@prettyPrint.opaque` prints as. */
let opaque: 'a => doc

/** `(a, b)` */
let tuple: array<doc> => doc

/** `Name(a, b)`, or just `Name` without arguments. */
let constructor: (string, array<doc>) => doc

/** One `name: value` entry of a record, or nothing (an unset optional field). */
type field

let field: (string, doc) => field

/** A record's `name?: typ` field: printed as `name: value` when set, left out when not. */
let optionalField: (string, 'a => doc, option<'a>) => field

/** `{a: 1, b: 2}` */
let record: array<field> => doc
