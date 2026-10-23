@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** The other entrypoint sharing `Format`. */

@weft.component({kind: Entrypoint})
let make = (~text: string) => <span className="plain"> {Weft.Jsx.string(Format.plain(text))} </span>
