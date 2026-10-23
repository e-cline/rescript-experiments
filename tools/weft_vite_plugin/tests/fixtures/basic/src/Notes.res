/***
A server file (it has a server component), with a sentinel string that must never reach the client.
`instance` is new each time the module runs, so a test can tell the dev server ran it again.
*/

let secret = "SERVER_SENTINEL_7f3a"

let instance = Math.random()

let title = path => `Notes at ${path} (${Int.toString(String.length(secret))})`

@weft.component({kind: Server})
let make = (~path) => <h1> {WeftDom.Jsx.string(title(path))} </h1>
