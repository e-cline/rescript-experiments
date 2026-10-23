@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** A link that navigates in place: an entrypoint on every page. */

@weft.component({kind: Entrypoint})
let make = (~href: string, ~id: string, ~children: Weft.element) => {
  let navigation = WeftServer.Navigation.useNavigation()
  <a
    id
    href
    onClick={event => {
      Weft.Dom.Event.preventDefault(event)
      navigation->WeftServer.Navigation.navigate(href)->ignore
    }}
  >
    children
  </a>
}
