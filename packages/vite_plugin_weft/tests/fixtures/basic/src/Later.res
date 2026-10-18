@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
An entrypoint the dev test takes away before starting the server, and then puts back, as
`rescript build -w` would write a new file.
*/

@weft.component({kind: Entrypoint})
let make = (~text: string) => <p> {Weft.Jsx.string(text)} </p>
