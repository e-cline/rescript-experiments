/***
Values attached to a request, each under a typed key.

A key is made once, usually by the module that owns the value, and is the
only way to get at it. A middleware attaches a value to the request under
the key (`RequestContext.set`), and anything later in the request reads it
back (`RequestContext.get`), with the type the key was declared with:

```rescript
let userKey: Context.Key.t<user> = Context.Key.make(~name="user")
```

A context can hold values for any number of keys, of any types, so
middleware from separate libraries don't need to know about each other, and
adding one doesn't change the type of the request or of the handlers behind
it.

A request carries one of these as `ctx.context`. The functions here work on
the context itself; handlers and middleware normally use the ones in
`RequestContext`, which work on the request.
*/

module Key: {
  /**
  A key for a value of type `'a`. Two keys are never the same key, even with
  the same name.
  */
  type t<'a>

  /**
  A new key. `name` says what the value is, for error messages (see
  `RequestContext.getOrThrow`).

  Give the binding a type, as in the example above: the type of the values is
  whatever the key's own type says.
  */
  let make: (~name: string) => t<'a>

  let name: t<'a> => string
}

/** The values, by key. Immutable: `set` returns a new context. */
type t

/** A context with no values. */
let empty: t

/** The value under `key`, if there is one. */
let get: (t, Key.t<'a>) => option<'a>

/** The same context with `value` under `key`, replacing any value already there. */
let set: (t, Key.t<'a>, 'a) => t
