/***
The basics: `@prettyPrint` on a type declaration makes the PPX add a
`<type>_prettyPrint` function (the value as a string) and a `<type>_toDoc`
function (the value as a `PrettyPrint.doc`, which is what printers compose
with) right after it.
*/

/** A record. */
@prettyPrint
type point = {x: float, y: float}

/** A variant, with and without payloads. */
@prettyPrint
type color =
  | Red
  | Green
  | Rgb(int, int, int)

/**
A type using other `@prettyPrint` types: the generated `shape_toDoc` calls
`point_toDoc` and `color_toDoc`. (Leave the annotation off `point` and this
fails to compile with "The value point_toDoc can't be found", pointing at the
`point` below.)
*/
@prettyPrint
type rec shape =
  | Circle({center: point, radius: float})
  | Polygon(array<point>)
  | Colored(color, shape)
