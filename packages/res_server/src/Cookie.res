type sameSite =
  | Strict
  | Lax
  | CrossSite

type options = {
  path?: string,
  domain?: string,
  maxAge?: int,
  expires?: Date.t,
  httpOnly?: bool,
  secure?: bool,
  sameSite?: sameSite,
  partitioned?: bool,
}

@val external decodeURIComponent: string => string = "decodeURIComponent"
@val external encodeURIComponent: string => string = "encodeURIComponent"

let decode = (value: string): string =>
  try decodeURIComponent(value) catch {
  | _ => value
  }

let unquote = (value: string): string =>
  value->String.length >= 2 && value->String.startsWith("\"") && value->String.endsWith("\"")
    ? value->String.slice(~start=1, ~end=-1)
    : value

let parse = (header: string): Map.t<string, string> => {
  let cookies = Map.make()
  header
  ->String.split(";")
  ->Array.forEach(pair =>
    switch pair->String.indexOf("=") {
    | -1 => ()
    | index =>
      let name = pair->String.slice(~start=0, ~end=index)->String.trim
      let value = pair->String.slice(~start=index + 1)->String.trim
      if name != "" && !(cookies->Map.has(name)) {
        cookies->Map.set(name, value->unquote->decode)
      }
    }
  )
  cookies
}

// An RFC 7230 token, which is what RFC 6265 requires of a cookie name.
let isValidName = (name: string): bool => /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/->RegExp.test(name)

// Printable ASCII other than `;`.
let isValidAttributeValue = (value: string): bool => /^[\x20-\x3A\x3C-\x7E]*$/->RegExp.test(value)

let checkAttribute = (attribute: string, value: string): unit =>
  if !isValidAttributeValue(value) {
    JsError.throwWithMessage(
      `Invalid cookie ${attribute}: ${JSON.stringifyAny(value)->Option.getOr("")}`,
    )
  }

let serialize = (~options: options={}, name: string, value: string): string => {
  if !isValidName(name) {
    JsError.throwWithMessage(`Invalid cookie name: ${JSON.stringifyAny(name)->Option.getOr("")}`)
  }
  let path = options.path->Option.getOr("/")
  checkAttribute("path", path)
  options.domain->Option.forEach(domain => checkAttribute("domain", domain))

  // The `__Host-` and `__Secure-` name prefixes are promises about the
  // cookie's attributes, and a browser drops one that doesn't keep them.
  let hostPrefixed = name->String.startsWith("__Host-")
  let securePrefixed = name->String.startsWith("__Secure-")
  if hostPrefixed && (path != "/" || options.domain->Option.isSome) {
    JsError.throwWithMessage(
      `Invalid cookie "${name}": a "__Host-" cookie must have the path "/" and no domain`,
    )
  }
  let sameSite = options.sameSite->Option.getOr(Lax)
  let partitioned = options.partitioned->Option.getOr(false)
  // Each of these requires `Secure`, so asking for one is asking for it.
  let secure =
    options.secure->Option.getOr(false) ||
    sameSite == CrossSite ||
    partitioned ||
    hostPrefixed ||
    securePrefixed
  let flag = (enabled: bool, attribute: string): option<string> => enabled ? Some(attribute) : None
  [
    Some(`${name}=${encodeURIComponent(value)}`),
    Some(`Path=${path}`),
    options.domain->Option.map(domain => `Domain=${domain}`),
    options.maxAge->Option.map(maxAge => `Max-Age=${maxAge->Int.toString}`),
    options.expires->Option.map(expires => `Expires=${expires->Date.toUTCString}`),
    flag(options.httpOnly->Option.getOr(true), "HttpOnly"),
    flag(secure, "Secure"),
    Some(
      switch sameSite {
      | Strict => "SameSite=Strict"
      | Lax => "SameSite=Lax"
      | CrossSite => "SameSite=None"
      },
    ),
    flag(partitioned, "Partitioned"),
  ]
  ->Array.keepSome
  ->Array.join("; ")
}

let expire = (
  ~path: option<string>=?,
  ~domain: option<string>=?,
  ~secure: option<bool>=?,
  ~partitioned: option<bool>=?,
  name: string,
): string =>
  serialize(
    name,
    "",
    ~options={?path, ?domain, ?secure, ?partitioned, maxAge: 0, expires: Date.fromTime(0.0)},
  )
