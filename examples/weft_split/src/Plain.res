/*** The other entrypoint sharing `Format`. */

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (~text: string) => <span className="plain"> {Jsx.string(Format.plain(text))} </span>
