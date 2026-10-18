/***
Assertions: the always-on
`assert_` and `fail`, and `debugAssert`, which is a no-op outside development builds.

A failed assertion throws a plain `JsError.t` (a real JS `Error` with a working
`.message`), not a dedicated assertion-error type.

Every function takes its `message` as a thunk (`unit => string`) rather than a
string, so an expensive message (e.g. one that stringifies a large value) is only
built when the assertion actually fails.
*/

/**
Whether this build resolved `@e-cline/js_env`'s `"development"` export condition
(via `Env.isDev`). Exposed mainly so tests can document/verify which variant a
given test run resolves to; ordinary call sites should reach for `debugAssert`
rather than branching on this directly.
*/
let isDev: bool

/**
Always-on assertion: throws if `condition` is `false`, with `message()` (or
`"Assertion failed"` when omitted) as the error message.
*/
let assert_: (bool, ~message: unit => string=?) => unit

/**
Unconditionally throws, with `message()` (or `"Assertion failed"` when omitted)
as the error message. For marking a branch that should be unreachable at runtime
(e.g. after a `switch` that ReScript can't itself prove exhaustive, such as one
over an `int` range).
*/
let fail: (~message: unit => string=?) => 'a

/**
Like `assert_`, but a no-op when `isDev` is `false`. In a production build `isDev`
resolves to the literal `false`, so a bundler can remove the whole check --
including any expensive `message` thunk built at the call site.
*/
let debugAssert: (bool, ~message: unit => string=?) => unit
