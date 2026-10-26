/***
A product's variants (sizes, say), and the offer for the one picked: its price, stock and the add to
cart button, rendered on the server, as `children`. Picking another variant fetches its offer
(`useRefetchable`, from the offer's own route), showing the old one, marked pending, until the new
one is ready; the add to cart button inside keeps the quantity chosen.
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
  </WeftUi.Stack>
}
