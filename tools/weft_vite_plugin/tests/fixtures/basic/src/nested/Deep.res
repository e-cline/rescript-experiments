/*** An entrypoint in a subdirectory. */

@weft.component({kind: Entrypoint})
let make = (~depth: int) => <p> {WeftDom.Jsx.string(`deep ${Int.toString(depth)}`)} </p>
