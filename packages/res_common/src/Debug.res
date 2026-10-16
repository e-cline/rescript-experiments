// Helpers a TypeScript assertion library would typically carry are left out
// deliberately. A `checkExhaustive(x: never)` exists to paper over TS's weaker
// exhaustiveness checking; ReScript's own `switch` already gives real,
// compiler-enforced exhaustiveness warnings on variant matches, so there's
// nothing for a runtime helper to add. Type guards (`isString`, `isObject`,
// `assertType`, ...) exist to recover static typing from `unknown`/runtime
// values in a structurally-typed language with no real sum types; ReScript's
// `option`/variants make most of that unnecessary at the type level, and the
// few genuinely dynamic cases (e.g. narrowing a `JSON.t`) belong in a
// JSON-specific module, not here.
//
// `message` is always a thunk (`unit => string`), not a
// `string | (() => string)` union: ReScript's optional labeled arguments don't
// overload cleanly over a union the way a TS parameter type can, so there's one
// signature. A call site with a cheap static message just writes
// `~message=() => "text"`.

let isDev = Env.isDev

let defaultMessage = "Assertion failed"

let resolveMessage = (message: option<unit => string>): string =>
  switch message {
  | Some(toMessage) => toMessage()
  | None => defaultMessage
  }

/**
Throws a plain `JsError.t` with the given message. Unlike TS's dedicated `AssertionError` class,
that's all a failed assertion is here: a hand-rolled ReScript `exception` doesn't compile to a real
JS `Error` (it has a payload, not a `.message` property), so it wouldn't work with anything --
including Vitest's own `toThrow(~message)` matcher -- that expects a normal thrown error; and
nothing in this package needs to distinguish "an assertion failed" from any other error by its
exception identity, so there's no real cost to not having one.
*/
let raiseAssertionError = (message: string): 'a => message->JsError.make->JsError.throw

let assert_ = (condition: bool, ~message: option<unit => string>=?): unit =>
  if !condition {
    raiseAssertionError(resolveMessage(message))
  }

let fail = (~message: option<unit => string>=?): 'a => raiseAssertionError(resolveMessage(message))

// `Env.isDev` binds to `@e-cline/js_env`'s export-condition trick (see
// `Env.res`'s header comment), so in a production build `isDev` resolves to the
// literal `false` and a bundler can constant-fold this whole `if` away, taking
// `resolveMessage`'s call (and therefore any expensive message thunk a call
// site built) with it.
let debugAssert = (condition: bool, ~message: option<unit => string>=?): unit =>
  if isDev {
    assert_(condition, ~message?)
  }
