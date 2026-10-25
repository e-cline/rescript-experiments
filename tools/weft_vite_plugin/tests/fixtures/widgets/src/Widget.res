/*** An entrypoint in a ReScript dependency of the app, which declares an RPC, and has styles. */
open WeftCss

let widget = Css.class({padding: Px(4)})

@weft.rpc({id: "widgets.press"})
let press: WeftServer.Rpc.t<string, string, unit, unit> = WeftServer.Rpc.make(
  ~request=WeftServer.Rpc.Codec.string,
)

@weft.component({kind: Entrypoint})
let make = (~name: string) => <p className=widget> {WeftDom.Jsx.string("widget " ++ name)} </p>
