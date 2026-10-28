/*** A rail of cards (rendered on the server, as `children`), a page of four at a time. */

module Jsx = WeftDom.Jsx

let pageSize = 4

open WeftCss

module Styles = {
  /** How far the track is moved: a page (100%) for each page before the one shown. */
  let offset = Css.var("0%")
  let head = Css.class({display: Flex, justifyContent: SpaceBetween, alignItems: Center})
  let window = Css.class({overflow: Hidden})
  let track = Css.class({
    display: Grid,
    gridAutoFlow: "column",
    gridAutoColumns: "calc(25% - 12px)",
    gap: Px(16),
    transform: `translateX(${Theme.value(offset)})`,
    transition: "transform .3s",
    media: [Css.media(~query="(max-width: 720px)", {gridAutoColumns: "calc(50% - 8px)"})],
  })
}

@weft.component({kind: Entrypoint})
let make = (~id: string, ~title: string, ~count: int, ~children: Weft.Element.t) => {
  let (page, setPage) = Weft.Hooks.useState(() => 0)
  let pages = Math.Int.max(1, (count + pageSize - 1) / pageSize)
  // The rail can shrink under the page it was on (a refetch with fewer cards).
  let page = Math.Int.min(page, pages - 1)
  let first = page * pageSize
  <div dataId={`carousel-${id}`}>
    <div className={Styles.head}>
      <WeftUi.Heading level=#h2 size=#lg> {Jsx.string(title)} </WeftUi.Heading>
      {pages > 1
        ? <WeftUi.Stack direction=#row gap=#sm align=#center>
            <WeftUi.IconButton
              label="Previous"
              variant=#secondary
              size=#sm
              dataId={`prev-${id}`}
              disabled={page == 0}
              onClick={_ => setPage(_ => page - 1)}
            >
              {Jsx.string("‹")}
            </WeftUi.IconButton>
            <WeftUi.Text as_=#span tone=#muted size=#sm numeric=true dataId={`position-${id}`}>
              {Jsx.string(
                `${Int.toString(first + 1)}–${Int.toString(
                    Math.Int.min(count, first + pageSize),
                  )} of ${Int.toString(count)}`,
              )}
            </WeftUi.Text>
            <WeftUi.IconButton
              label="Next"
              variant=#secondary
              size=#sm
              dataId={`next-${id}`}
              disabled={page == pages - 1}
              onClick={_ => setPage(_ => page + 1)}
            >
              {Jsx.string("›")}
            </WeftUi.IconButton>
          </WeftUi.Stack>
        : Jsx.null}
    </div>
    <div className={Styles.window}>
      <div
        className={Styles.track}
        style={Css.vars([(Styles.offset, `-${Int.toString(page * 100)}%`)])}
      >
        children
      </div>
    </div>
  </div>
}
