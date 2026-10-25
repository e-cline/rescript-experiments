/***
Around every block of a server-driven page: an error boundary (a block whose service failed shows
why, with a Retry button, and the rest of the page is unaffected), and the block refetched by itself
(`useRefetchable`, from the block's own route): on Retry, and every `refreshEvery` seconds for a
block the server says is live.

Retry refetches the block, then resets the boundary once the refetched block has rendered (not when
`refetch` resolves, which is when its render starts: a reset then would render the failed block
again), so what renders is the newly fetched block: another failure is caught again.
*/

open WeftCss

module Styles = {
  let block = Css.class({
    margin: Four(Zero, Zero, Px(28), Zero),
    selectors: [("&[aria-busy=\"true\"]", Css.style({opacity: 0.7, transition: "opacity .2s"}))],
  })
  let error = Css.class({
    padding: Px(12),
    border: "1px solid #f0c8c4",
    backgroundColor: Hex("fdf1f0"),
    borderRadius: Px(8),
  })
}

@weft.component({kind: Entrypoint})
let make = (~id: string, ~src: string, ~refreshEvery: option<int>=?, ~children: Weft.Element.t) => {
  let block = WeftServer.Navigation.useRefetchable(~src, children)
  // Retry's reset, waiting for the refetch to have rendered.
  let (retrying, setRetrying) = Weft.Hooks.useState(() => false)
  let reset = Weft.Hooks.useRef(() => ())
  Weft.Hooks.useEffect2(() => {
    if retrying && !block.isPending {
      setRetrying(_ => false)
      reset.current()
    }
    None
  }, (retrying, block.isPending))
  // The interval calls the latest `refetch`.
  let refetch = Weft.Hooks.useRef(block.refetch)
  refetch.current = block.refetch
  Weft.Hooks.useEffect2(() =>
    switch refreshEvery {
    | Some(seconds) =>
      let timer = setInterval(
        () => refetch.current()->Promise.catch(_ => Promise.resolve())->ignore,
        seconds * 1000,
      )
      Some(() => clearInterval(timer))
    | None => None
    }
  , (refreshEvery, src))
  <section
    id={`block-${id}`}
    className={Styles.block}
    ariaBusy={block.isPending ? "true" : "false"}
    title={block.isPending ? "pending" : "idle"}
  >
    <Weft.ErrorBoundary
      fallback={(~error, ~reset as resetBoundary) => {
        reset.current = resetBoundary
        <div className={Styles.error} id={`block-error-${id}`} role="alert">
          <p> {WeftDom.Jsx.string("Couldn't load this: " ++ Weft.ErrorBoundary.message(error))} </p>
          <button
            id={`retry-${id}`}
            disabled=retrying
            onClick={_ => {
              setRetrying(_ => true)
              refetch.current()->Promise.catch(_ => Promise.resolve())->ignore
            }}
          >
            {WeftDom.Jsx.string(retrying ? "Retrying…" : "Retry")}
          </button>
        </div>
      }}
    >
      {block.element}
    </Weft.ErrorBoundary>
  </section>
}
