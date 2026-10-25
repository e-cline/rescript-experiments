/***
A server file (it has a server component), with a sentinel string that must never reach the client.
`instance` is new each time the module runs, so a test can tell the dev server ran it again. Its
style's definition has a sentinel too, which must reach neither bundle.
*/
open WeftCss

let secret = "SERVER_SENTINEL_7f3a"

let instance = Math.random()

let title = path => `Notes at ${path} (${Int.toString(String.length(secret))})`

let heading = Css.class({color: Var(Theme.ink), content: "\"DEFINITION_SENTINEL_NOTES\""})

@weft.component({kind: Server})
let make = (~path) => <h1 className=heading> {WeftDom.Jsx.string(title(path))} </h1>
