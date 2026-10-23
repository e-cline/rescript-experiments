@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/***
A component written against `WeftDom.Jsx`, the JSX module apps use, to check the PPX works the same
with DOM host elements.
*/

@weft.component({kind: Entrypoint})
let make = (~label: string) => <button type_="button"> {WeftDom.Jsx.string(label)} </button>
