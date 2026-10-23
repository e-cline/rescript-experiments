/*** The other entrypoint sharing `Format`. */

@weft.component({kind: Entrypoint})
let make = (~text: string) =>
  <span className="plain"> {WeftDom.Jsx.string(Format.plain(text))} </span>
