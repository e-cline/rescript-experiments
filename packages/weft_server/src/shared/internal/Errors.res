/***
The errors WeftServer throws when it's misused, numbered so production builds needn't carry the
messages (as `weft_core`'s are; see its `Errors`). The codes are listed in the package README's
"Error codes" section, and stay fixed once published.
*/

let message = (code: int, devMessage: string) =>
  Common.Env.isDev
    ? devMessage
    : `WeftServer error ${Int.toString(code)} (see "Error codes" in @e-cline/weft_server's README)`

let fail = (code: int, devMessage: string) => JsError.throwWithMessage(message(code, devMessage))
