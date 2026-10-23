/*** An entrypoint in a ReScript dependency of the app, which declares an RPC too. */

@weft.rpc({id: "widgets.press"})
let press: WeftServer.Rpc.t<string, string, unit, unit> = WeftServer.Rpc.make(
  ~request=WeftServer.Rpc.Codec.string,
)

@weft.component({kind: Entrypoint})
let make = (~name: string) => <p> {WeftDom.Jsx.string("widget " ++ name)} </p>
