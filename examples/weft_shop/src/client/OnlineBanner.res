/***
A banner while the browser is offline: `navigator.onLine`, read with `useSyncExternalStore`, whose
server snapshot (online) is what the HTML shows, and the first render hydrating it.
*/

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

@weft.component
let make = () => {
  let online = Weft.Hooks.useSyncExternalStore(
    ~subscribe,
    ~getSnapshot=() => navigatorOnLine,
    ~getServerSnapshot=() => true,
  )
  online
    ? WeftDom.Jsx.null
    : <p id="offline" role="alert">
        {WeftDom.Jsx.string("You're offline: prices and stock may be out of date.")}
      </p>
}
