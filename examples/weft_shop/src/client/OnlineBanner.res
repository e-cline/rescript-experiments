/***
A banner while the browser is offline: `navigator.onLine`, read with `useSyncExternalStore`, whose
server snapshot (online) is what the HTML shows, and the first render hydrating it.
*/

module Jsx = WeftDom.Jsx

@val external navigatorOnLine: bool = "navigator.onLine"
@val external addWindowListener: (string, unit => unit) => unit = "addEventListener"
@val external removeWindowListener: (string, unit => unit) => unit = "removeEventListener"

let subscribe = onChange => {
  addWindowListener("online", onChange)
  addWindowListener("offline", onChange)
  () => {
    removeWindowListener("online", onChange)
    removeWindowListener("offline", onChange)
  }
}

open WeftCss

module Styles = {
  let offline = Css.class({position: Sticky, top: Zero, zIndex: 10, borderRadius: Zero})
}

@weft.component
let make = () => {
  let online = Weft.Hooks.useSyncExternalStore(
    ~subscribe,
    ~getSnapshot=() => navigatorOnLine,
    ~getServerSnapshot=() => true,
  )
  online
    ? Jsx.null
    : <WeftUi.Alert.Root tone=#warning dataId="offline" className=Styles.offline>
        <WeftUi.Alert.Description>
          {Jsx.string("You're offline: prices and stock may be out of date.")}
        </WeftUi.Alert.Description>
      </WeftUi.Alert.Root>
}
