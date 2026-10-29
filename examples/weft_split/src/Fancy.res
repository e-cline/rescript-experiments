/*** One of two entrypoints sharing `Format`. */

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (~text: string) => <em className="fancy"> {Jsx.string(Format.fancy(text))} </em>
