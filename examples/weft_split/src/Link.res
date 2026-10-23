/*** A link that navigates in place: an entrypoint on every page. */

@weft.component({kind: Entrypoint})
let make = (~href: string, ~id: string, ~children: Weft.Element.t) => {
  let navigation = WeftServer.Navigation.useNavigation()
  <a
    id
    href
    // A plain click navigates in place; one opening a new tab or window is left to the browser.
    onClick={event => navigation->WeftServer.Navigation.followLink(event, ~href)->ignore}
  >
    children
  </a>
}
