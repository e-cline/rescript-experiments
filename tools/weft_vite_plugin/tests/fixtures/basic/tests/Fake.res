@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/*** An entrypoint in a dev source: not part of the app, so not scanned. */

@weft.component({kind: Entrypoint})
let make = () => <p> {WeftDom.Jsx.string("fake")} </p>
