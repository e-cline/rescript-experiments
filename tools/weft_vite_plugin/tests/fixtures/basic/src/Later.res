@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/***
An entrypoint the dev test takes away before starting the server, and then puts back, as
`rescript build -w` would write a new file.
*/

@weft.component({kind: Entrypoint})
let make = (~text: string) => <p> {WeftDom.Jsx.string(text)} </p>
