/***
The casts the reconciler needs to keep heterogeneous values (props, state, host instances) in one
fiber record. Every use is paired with the code that stored the value, so the types line up at
runtime even though the compiler can't see it.
*/

external toUnknown: 'a => unknown = "%identity"
external fromUnknown: unknown => 'a = "%identity"

/** A `null` stored in an `unknown` field, meaning "nothing here yet". */
let nothing: unknown = toUnknown(Nullable.null)

let isNothing = (value: unknown): bool => Nullable.isNullable(fromUnknown(value))
