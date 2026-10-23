@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** One of two entrypoints sharing `Format`. */

@weft.component({kind: Entrypoint})
let make = (~text: string) => <em className="fancy"> {Weft.Jsx.string(Format.fancy(text))} </em>
