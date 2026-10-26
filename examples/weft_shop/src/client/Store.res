/***
The client's own state, in `signals` atoms, which entrypoints anywhere on the page read and write:
the cart an RPC last answered with, and whether the sign-in dialog is open. Toasts are weft_ui's.

These are module-level, so they outlive a page (in a browser, a navigation; in the tests, a page
opened after another in the same document), and on the server they'd be shared by every request:
nothing writes them there (only handlers and effects do, which don't run on the server), and the
cart is tagged with the `ShopShell` that wrote it, so a shell only believes its own.
*/

open Types

/** The cart, and which shell's it is. */
let cart: Signals.Atom.t<option<(float, cart)>, unit> = Signals.Atom.make(None)

/** Takes `next` for shell `owner`, unless it already has a newer cart for that shell. */
let offerCart = (~owner, next: cart) =>
  cart->Signals.Atom.update(current =>
    switch current {
    | Some((found, current)) if found == owner && current.version >= next.version =>
      Some((found, current))
    | _ => Some((owner, next))
    }
  )

/** The cart an RPC answered with, for whichever shell is showing. */
let setCart = (next: cart) =>
  cart->Signals.Atom.update(current =>
    switch current {
    | Some((owner, current)) if current.version > next.version => Some((owner, current))
    | Some((owner, _)) => Some((owner, next))
    | None => Some((0.0, next))
    }
  )

/** A toast (weft_ui's, which `ToastViewport`, in the shell, shows). */
let toast = text => WeftUi.Toast.add(~title=text, ())->ignore

let signInOpen: Signals.Atom.t<bool, unit> = Signals.Atom.make(false)

let openSignIn = () => signInOpen->Signals.Atom.set(true)
let closeSignIn = () => signInOpen->Signals.Atom.set(false)
