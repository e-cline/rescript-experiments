/***
The errors ResFiber throws when it's misused, numbered so production builds needn't carry the
messages.

Each call site passes its code and `ResCommon.Env.isDev ? "ResFiber: the message" : ""`. In
development that's the message; a production build resolves `isDev` to `false`, so the minifier
folds the condition and drops the text, leaving `ResFiber error <code>`. (Passing the message
unconditionally wouldn't work: a minifier won't drop an argument just because the function ignores
it.) The codes are listed in the package README's "Error codes" section, and stay fixed once
published: a new error gets the next number.
*/

/** The message for error `code`: `devMessage` in development, the code in production. */
let message = (code: int, devMessage: string) =>
  ResCommon.Env.isDev
    ? devMessage
    : `ResFiber error ${Int.toString(code)} (see "Error codes" in @e-cline/res_fiber's README)`

let fail = (code: int, devMessage: string) => JsError.throwWithMessage(message(code, devMessage))
