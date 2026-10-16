/***
HTTP request methods, as a variant so routes can pattern-match on them.
*/

type t =
  | GET
  | HEAD
  | POST
  | PUT
  | PATCH
  | DELETE
  | OPTIONS
  /** Any other method, upper-cased (e.g. `Other("PROPFIND")`). */
  | Other(string)

let fromString = (method: string): t =>
  switch method->String.toUpperCase {
  | "GET" => GET
  | "HEAD" => HEAD
  | "POST" => POST
  | "PUT" => PUT
  | "PATCH" => PATCH
  | "DELETE" => DELETE
  | "OPTIONS" => OPTIONS
  | other => Other(other)
  }

let toString = (method: t): string =>
  switch method {
  | GET => "GET"
  | HEAD => "HEAD"
  | POST => "POST"
  | PUT => "PUT"
  | PATCH => "PATCH"
  | DELETE => "DELETE"
  | OPTIONS => "OPTIONS"
  | Other(other) => other
  }
