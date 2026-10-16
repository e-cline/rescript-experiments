/***
HTTP cookies: parsing a request's `Cookie` header, and building the
`Set-Cookie` header that sets one.

Handlers normally use `RequestContext.cookie` to read and `Respond.setCookie` /
`Respond.deleteCookie` to write, which call these.
*/

/** Which cross-site requests the browser sends the cookie with. */
type sameSite =
  /** Never with cross-site requests. */
  | Strict
  /** Only with cross-site top-level navigations (following a link). The default. */
  | Lax
  /**
  With every cross-site request (`SameSite=None`). Browsers require `Secure` for
  this, so it's always added.
  */
  | CrossSite

/**
A cookie's attributes. The defaults are the cautious ones: the cookie is sent
for the whole site (`path` is `/`), can't be read by scripts in the page
(`httpOnly`), and isn't sent with cross-site subrequests (`sameSite` is `Lax`).
Without `maxAge` or `expires` it lasts until the browser is closed.
*/
type options = {
  /** Default `/`. */
  path?: string,
  /** Also send the cookie to this domain's subdomains. By default, only to the host that set it. */
  domain?: string,
  /** How long the cookie lasts, in seconds. */
  maxAge?: int,
  expires?: Date.t,
  /** Hide the cookie from JavaScript in the page. Default `true`. */
  httpOnly?: bool,
  /**
  Only send the cookie over HTTPS. Default `false`, so that cookies work on
  `http://localhost`; set it in production.
  */
  secure?: bool,
  /** Default `Lax`. */
  sameSite?: sameSite,
  /** Keep a separate cookie per top-level site (CHIPS). Default `false`. */
  partitioned?: bool,
}

/**
The cookies in a `Cookie` request header, by name. Values are
percent-decoded; if a name appears more than once its first value is kept.
*/
let parse: string => Map.t<string, string>

/**
A `Set-Cookie` header value. The cookie's value is percent-encoded, so it can
be any string.

`Secure` is added, whatever `secure` says, wherever a browser would drop the
cookie without it: for `sameSite: CrossSite`, for `partitioned`, and for a
name starting `__Host-` or `__Secure-`.

Throws if `name` isn't a valid cookie name (letters, digits and
``!#$%&'*+-.^_`|~`` only), or if `path` or `domain` contain a `;` or a control
character: accepting those would let whoever supplied them add attributes of
their own. Also throws for a `__Host-` name with a `domain` or a `path` other
than `/`, which that prefix rules out.
*/
let serialize: (~options: options=?, string, string) => string

/**
A `Set-Cookie` header value that makes the browser forget a cookie. `path` and
`domain` must be the ones it was set with, and `partitioned` given if it was.
`Secure` is added where it's required, as in `serialize`.
*/
let expire: (
  ~path: string=?,
  ~domain: string=?,
  ~secure: bool=?,
  ~partitioned: bool=?,
  string,
) => string
