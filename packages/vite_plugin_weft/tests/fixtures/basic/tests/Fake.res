@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** An entrypoint in a dev source: not part of the app, so not scanned. */

@weft.component({kind: Entrypoint})
let make = () => <p> {Weft.Jsx.string("fake")} </p>
