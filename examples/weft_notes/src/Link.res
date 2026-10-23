@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/*** A link that navigates in place (fetching the page's payload) instead of loading a new page. */

@weft.component({kind: Entrypoint})
let make = (~href: string, ~id: option<string>=?, ~children: Weft.Element.t) => {
  let navigation = WeftServer.Navigation.useNavigation()
  <a
    ?id
    href
    onClick={event => {
      WeftDom.Dom.Event.preventDefault(event)
      navigation->WeftServer.Navigation.navigate(href)->ignore
    }}
  >
    children
  </a>
}
