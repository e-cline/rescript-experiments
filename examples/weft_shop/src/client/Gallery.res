/*** A product's pictures (gradients standing in for photos): a main view and thumbnails, or the arrow keys. */

let views = ["Front", "Side", "Back", "Detail"]

let picture = (~hue, ~index) =>
  Dict.fromArray([
    (
      "background",
      `linear-gradient(${Int.toString(135 + index * 40)}deg, hsl(${Int.toString(
          hue,
        )} 45% 70%), hsl(${Int.toString(hue + 30)} 35% 40%))`,
    ),
  ])

open WeftCss

module Styles = {
  let main = Css.class({display: Flex, alignItems: End, padding: Px(10), color: Named("white")})
  let thumbnails = Css.class({display: Flex, gap: Px(8), marginTop: Px(8)})
  let thumbnail = Css.class({
    width: Px(56),
    height: Px(42),
    borderRadius: Px(6),
    selectors: [
      ("&[aria-pressed=\"true\"]", Css.style({outline: `2px solid ${Theme.value(Theme.ink)}`})),
    ],
  })
}

@weft.component({kind: Entrypoint})
let make = (~name: string, ~hue: int) => {
  let (selected, setSelected) = Weft.Hooks.useState(() => 0)
  let count = Array.length(views)
  <div
    id="gallery"
    tabIndex=0
    ariaLabel={`Pictures of the ${name}`}
    onKeyDown={event =>
      switch WeftDom.Dom.Event.key(event) {
      | "ArrowRight" => setSelected(index => mod(index + 1, count))
      | "ArrowLeft" => setSelected(index => mod(index + count - 1, count))
      | _ => ()
      }}
  >
    <div
      id="main-picture"
      className={Css.cx(["picture", Theme.picture, Styles.main])}
      style={picture(~hue, ~index=selected)}
    >
      <span id="view-label"> {WeftDom.Jsx.string(views->Array.getUnsafe(selected))} </span>
    </div>
    <div className={Css.cx(["thumbnails", Styles.thumbnails])}>
      {views
      ->Array.mapWithIndex((view, index) =>
        <button
          key=view
          id={`thumb-${Int.toString(index)}`}
          className={Css.cx(["thumbnail", Styles.thumbnail])}
          ariaLabel=view
          ariaPressed={index == selected ? "true" : "false"}
          style={picture(~hue, ~index)}
          onClick={_ => setSelected(_ => index)}
        />
      )
      ->WeftDom.Jsx.array}
    </div>
  </div>
}
