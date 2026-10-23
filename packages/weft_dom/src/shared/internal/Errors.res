/***
The errors WeftDom throws when it's misused, numbered so production builds needn't carry the
messages (as `weft`'s are). The codes are listed in the package README's "Error codes"
section, and stay fixed once published.
*/

let message = (code: int, devMessage: string) =>
  Common.Env.isDev
    ? devMessage
    : `WeftDom error ${Int.toString(code)} (see "Error codes" in @e-cline/weft_dom's README)`

let fail = (code: int, devMessage: string) => JsError.throwWithMessage(message(code, devMessage))
