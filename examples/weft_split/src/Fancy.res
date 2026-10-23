@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/*** One of two entrypoints sharing `Format`. */

@weft.component({kind: Entrypoint})
let make = (~text: string) => <em className="fancy"> {WeftDom.Jsx.string(Format.fancy(text))} </em>
