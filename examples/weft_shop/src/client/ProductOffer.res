/***
A product's variants (sizes, say), and the offer for the one picked: its price, stock and the add to
cart button, rendered on the server, as `children`. Picking another variant fetches its offer
(`useRefetchable`, from the offer's own route), showing the old one, marked pending, until the new
one is ready; the add to cart button inside keeps the quantity chosen. The size guide is loaded
(`import()`) the first time it's opened, and shown once it and its stylesheet are in.
*/

open Types

@weft.component({kind: Entrypoint})
let make = (
  ~slug: string,
  ~variants: array<variant>,
  ~selected: string,
  ~children: Weft.Element.t,
) => {
  let (sku, setSku) = Weft.Hooks.useState(() => selected)
  // Made once, when first opened: a new lazy element would load (and suspend) again.
  let (guide, setGuide) = Weft.Hooks.useState((): option<Weft.Element.t> => None)
  let (guideOpen, setGuideOpen) = Weft.Hooks.useState(() => false)
  let toggleGuide = _ => {
    if Option.isNone(guide) {
      setGuide(_ => Some(
        Weft.Lazy.fromPromise(import(SizeGuide.view)->Promise.thenResolve(view => view())),
      ))
    }
    setGuideOpen(open_ => !open_)
  }
  let offer = WeftServer.Navigation.useRefetchable(
    ~src=`/p/${slug}/offer?sku=${selected}`,
    children,
  )
  <WeftUi.Stack gap=#md dataId="product-offer" align=#start>
    {Array.length(variants) > 1
      ? <WeftUi.ToggleGroup.Root
          label="Variant"
          dataId="variants"
          value=[sku]
          onValueChange={values =>
            values
            ->Array.get(0)
            ->Option.forEach(next => {
              setSku(_ => next)
              offer.refetch(~url=`/p/${slug}/offer?sku=${next}`)->ignore
            })}
        >
          {variants
          ->Array.map(variant =>
            <WeftUi.ToggleGroup.Item
              key=variant.sku value=variant.sku dataId={`variant-${variant.sku}`}
            >
              {WeftDom.Jsx.string(variant.label)}
            </WeftUi.ToggleGroup.Item>
          )
          ->WeftDom.Jsx.array}
        </WeftUi.ToggleGroup.Root>
      : WeftDom.Jsx.null}
    <WeftUi.Stack
      gap=#sm
      dataId="offer"
      className={offer.isPending ? Theme.stale : ""}
      attrs={{ariaBusy: offer.isPending ? "true" : "false"}}
    >
      {offer.element}
    </WeftUi.Stack>
    <button
      dataId="size-guide-button"
      type_="button"
      ariaExpanded={guideOpen ? "true" : "false"}
      onClick=toggleGuide
    >
      {WeftDom.Jsx.string("Size guide")}
    </button>
    {switch (guideOpen, guide) {
    | (true, Some(guide)) =>
      <Weft.Suspense
        fallback={<p dataId="size-guide-loading" className=Theme.placeholder>
          {WeftDom.Jsx.string("Loading the size guide…")}
        </p>}
      >
        guide
      </Weft.Suspense>
    | _ => WeftDom.Jsx.null
    }}
  </WeftUi.Stack>
}
