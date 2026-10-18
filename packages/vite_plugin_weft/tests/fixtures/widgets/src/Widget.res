@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** An entrypoint in a ReScript dependency of the app. */

@weft.component({kind: Entrypoint})
let make = (~name: string) => <p> {Weft.Jsx.string("widget " ++ name)} </p>
