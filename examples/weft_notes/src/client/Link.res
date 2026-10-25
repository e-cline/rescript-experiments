/*** A link that navigates in place (fetching the page's payload) instead of loading a new page. */

@weft.component({kind: Entrypoint})
let make = (
  ~href: string,
  ~dataId: option<string>=?,
  ~className: option<string>=?,
  ~children: Weft.Element.t,
) => {
  let navigation = WeftServer.Navigation.useNavigation()
  <a
    ?dataId
    ?className
    href
    // A plain click navigates in place; one opening a new tab or window is left to the browser.
    onClick={event => navigation->WeftServer.Navigation.followLink(event, ~href)->ignore}
  >
    children
  </a>
}
