/***
A product's reviews, which arrive as a promise (the server sends the page without waiting for them):
read with `Hooks.use` under this component's own fallback. Sorting them is a transition (the list
re-sorts without blocking the select), and a few show until "Show all".
*/

open Types

module Items = {
  @weft.component
  let make = (~reviews: promise<array<review>>) => {
    let reviews = Weft.Hooks.use(reviews)
    let (order, setOrder) = Weft.Hooks.useState(() => "newest")
    let (all, setAll) = Weft.Hooks.useState(() => false)
    let (isPending, startTransition) = Weft.Hooks.useTransition()
    let sorted = switch order {
    | "highest" => reviews->Array.toSorted((a, b) => Int.toFloat(b.stars - a.stars))
    | "lowest" => reviews->Array.toSorted((a, b) => Int.toFloat(a.stars - b.stars))
    | _ => reviews
    }
    let shown = all ? sorted : sorted->Array.slice(~start=0, ~end=3)
    let average =
      reviews->Array.reduce(0, (total, review) => total + review.stars)->Int.toFloat /.
        Int.toFloat(Math.Int.max(1, Array.length(reviews)))
    <div id="reviews" className={isPending ? "pending" : ""}>
      <p id="review-summary">
        {WeftDom.Jsx.string(
          `${Float.toFixed(average, ~digits=1)} out of 5, from ${Int.toString(
              Array.length(reviews),
            )} reviews`,
        )}
      </p>
      <select
        id="review-order"
        ariaLabel="Sort reviews"
        value=order
        onChange={event => {
          let value = WeftDom.Dom.Event.targetValue(event)
          startTransition(() => setOrder(_ => value))
        }}
      >
        <option value="newest"> {WeftDom.Jsx.string("Newest")} </option>
        <option value="highest"> {WeftDom.Jsx.string("Highest rated")} </option>
        <option value="lowest"> {WeftDom.Jsx.string("Lowest rated")} </option>
      </select>
      <ul id="review-list">
        {shown
        ->Array.map(review =>
          <li key=review.id id={`review-${review.id}`}>
            <b> {WeftDom.Jsx.string(`${"★"->String.repeat(review.stars)} ${review.author}`)} </b>
            {WeftDom.Jsx.string(": " ++ review.text)}
          </li>
        )
        ->WeftDom.Jsx.array}
      </ul>
      {!all && Array.length(reviews) > 3
        ? <button id="all-reviews" onClick={_ => setAll(_ => true)}>
            {WeftDom.Jsx.string(`Show all ${Int.toString(Array.length(reviews))}`)}
          </button>
        : WeftDom.Jsx.null}
    </div>
  }
}

@weft.component({kind: Entrypoint})
let make = (~reviews: promise<array<review>>) =>
  <Weft.Suspense
    fallback={<p id="reviews-loading"> {WeftDom.Jsx.string("Loading reviews…")} </p>}
  >
    <Items reviews />
  </Weft.Suspense>
