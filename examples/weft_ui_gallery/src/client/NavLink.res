/***
A link that navigates in place (fetching the page's payload), in weft_ui's link look, or a recipe
the server gives it (`className`). `current` marks the page it goes to as the one shown.
*/

@weft.component({kind: Entrypoint})
let make = (
  ~href: string,
  ~className: option<string>=?,
  ~current=false,
  ~dataId: option<string>=?,
  ~children: Weft.Element.t,
) => {
  let navigation = WeftServer.Navigation.useNavigation()
  <a
    href
    ?dataId
    className={className->Option.getOr(WeftUi.Link.className())}
    ariaCurrent=?{current ? Some("page") : None}
    // A plain click navigates in place; one opening a new tab or window is left to the browser.
    onClick={event => navigation->WeftServer.Navigation.followLink(event, ~href)->ignore}
  >
    children
  </a>
}
