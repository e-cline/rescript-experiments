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
    <WeftUi.Stack gap=#md dataId="reviews" className={isPending ? Theme.stale : ""} align=#start>
      <WeftUi.Text dataId="review-summary" weight=#medium>
        {WeftDom.Jsx.string(
          `${Float.toFixed(average, ~digits=1)} out of 5, from ${Int.toString(
              Array.length(reviews),
            )} reviews`,
        )}
      </WeftUi.Text>
      <WeftUi.Field label="Sort reviews">
        <WeftUi.Select
          size=#sm
          dataId="review-order"
          value=order
          onChange={event => {
            let value = WeftDom.Dom.Event.targetValue(event)
            startTransition(() => setOrder(_ => value))
          }}
        >
          <WeftUi.Select.Option value="newest">
            {WeftDom.Jsx.string("Newest")}
          </WeftUi.Select.Option>
          <WeftUi.Select.Option value="highest">
            {WeftDom.Jsx.string("Highest rated")}
          </WeftUi.Select.Option>
          <WeftUi.Select.Option value="lowest">
            {WeftDom.Jsx.string("Lowest rated")}
          </WeftUi.Select.Option>
        </WeftUi.Select>
      </WeftUi.Field>
      <WeftUi.List.Root divided=true dataId="review-list">
        {shown
        ->Array.map(review =>
          <WeftUi.List.Item key=review.id dataId={`review-${review.id}`}>
            <b>
              <span ariaHidden="true">
                {WeftDom.Jsx.string("★"->String.repeat(review.stars))}
              </span>
              <WeftUi.VisuallyHidden>
                {WeftDom.Jsx.string(`${Int.toString(review.stars)} out of 5 stars, `)}
              </WeftUi.VisuallyHidden>
              {WeftDom.Jsx.string(` ${review.author}`)}
            </b>
            {WeftDom.Jsx.string(": " ++ review.text)}
          </WeftUi.List.Item>
        )
        ->WeftDom.Jsx.array}
      </WeftUi.List.Root>
      {!all && Array.length(reviews) > 3
        ? <WeftUi.Button size=#sm dataId="all-reviews" onClick={_ => setAll(_ => true)}>
            {WeftDom.Jsx.string(`Show all ${Int.toString(Array.length(reviews))}`)}
          </WeftUi.Button>
        : WeftDom.Jsx.null}
    </WeftUi.Stack>
  }
}

@weft.component({kind: Entrypoint})
let make = (~reviews: promise<array<review>>) =>
  <Weft.Suspense
    fallback={<WeftUi.Text tone=#muted italic=true dataId="reviews-loading">
      {WeftDom.Jsx.string("Loading reviews…")}
    </WeftUi.Text>}
  >
    <Items reviews />
  </Weft.Suspense>
