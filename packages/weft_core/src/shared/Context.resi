/***
A value passed down the tree without threading it through props.

```rescript
module Theme = {
  let context = WeftCore.Context.make(Light)
  module Provider = {
    let make = WeftCore.Context.provider(context)
  }
}

<Theme.Provider value=Dark> ... </Theme.Provider>
// and below it:
let theme = WeftCore.Hooks.useContext(Theme.context)
```

A component reading a context renders again whenever the nearest provider above it gets a value
that isn't `Object.is`-equal to the previous one, even if every component between them skipped
rendering (`Memo`, or children passed in from above).
*/

/** A context holding a `'value`. */
type t<'value>

type providerProps<'value> = {value: 'value, children: Element.t}

/** A context whose value, with no provider above, is `defaultValue`. */
let make: 'value => t<'value>

/** The context's provider component. It's created with the context, so its identity is stable. */
let provider: t<'value> => JsxCore.component<providerProps<'value>>
