/***
A product's variants (sizes, say), and the offer for the one picked: its price, stock and the add to
cart button, rendered on the server, as `children`. Picking another variant fetches its offer
(`useRefetchable`, from the offer's own route), showing the old one, marked pending, until the new
one is ready; the add to cart button inside keeps the quantity chosen.
*/

open Types

open WeftCss

module Styles = {
  let variants = Css.class({display: Flex, flexWrap: Wrap, gap: Px(6), margin: Pair(Px(10), Zero)})
  let variant = Css.class({
    selectors: [
      (
        "&[aria-pressed=\"true\"]",
        Css.style({backgroundColor: Var(Theme.ink), color: Named("white")}),
      ),
    ],
  })
}

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
  <div dataId="product-offer">
    {Array.length(variants) > 1
      ? <div dataId="variants" className=Styles.variants role="group" ariaLabel="Variant">
          {variants
          ->Array.map(variant =>
            <button
              key=variant.sku
              dataId={`variant-${variant.sku}`}
              className={Styles.variant}
              ariaPressed={variant.sku == sku ? "true" : "false"}
              onClick={_ => {
                setSku(_ => variant.sku)
                offer.refetch(~url=`/p/${slug}/offer?sku=${variant.sku}`)->ignore
              }}
            >
              {WeftDom.Jsx.string(variant.label)}
            </button>
          )
          ->WeftDom.Jsx.array}
        </div>
      : WeftDom.Jsx.null}
    <div
      dataId="offer"
      ariaBusy={offer.isPending ? "true" : "false"}
      className={offer.isPending ? Theme.stale : ""}
    >
      {offer.element}
    </div>
  </div>
}
