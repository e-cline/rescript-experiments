@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** A server file (it has a server component). */

let query = sql => `rows for ${sql}`

@weft.component({kind: Server})
let make = () => <p> {Weft.Jsx.string(query("select 1"))} </p>
