@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/*** A link that navigates in place: an entrypoint on every page. */

@weft.component({kind: Entrypoint})
let make = (~href: string, ~id: string, ~children: Weft.Element.t) => {
  let navigation = WeftServer.Navigation.useNavigation()
  <a
    id
    href
    onClick={event => {
      WeftDom.Dom.Event.preventDefault(event)
      navigation->WeftServer.Navigation.navigate(href)->ignore
    }}
  >
    children
  </a>
}
