@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
A component written against `Weft.Jsx`, the JSX module apps use, to check the PPX works the same
with DOM host elements.
*/

@weft.component({kind: Entrypoint})
let make = (~label: string) => <button type_="button"> {Weft.Jsx.string(label)} </button>
