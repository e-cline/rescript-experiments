/*** A rail of cards (rendered on the server, as `children`), a page of four at a time. */

let pageSize = 4

@weft.component({kind: Entrypoint})
let make = (~id: string, ~title: string, ~count: int, ~children: Weft.Element.t) => {
  let (page, setPage) = Weft.Hooks.useState(() => 0)
  let pages = Math.Int.max(1, (count + pageSize - 1) / pageSize)
  // The rail can shrink under the page it was on (a refetch with fewer cards).
  let page = Math.Int.min(page, pages - 1)
  let first = page * pageSize
  <div className="carousel" id={`carousel-${id}`}>
    <div className="carousel-head">
      <h2> {WeftDom.Jsx.string(title)} </h2>
      {pages > 1
        ? <div className="carousel-controls">
            <button
              id={`prev-${id}`}
              ariaLabel="Previous"
              disabled={page == 0}
              onClick={_ => setPage(_ => page - 1)}
            >
              {WeftDom.Jsx.string("‹")}
            </button>
            <span className="carousel-position" id={`position-${id}`}>
              {WeftDom.Jsx.string(
                `${Int.toString(first + 1)}–${Int.toString(
                    Math.Int.min(count, first + pageSize),
                  )} of ${Int.toString(count)}`,
              )}
            </span>
            <button
              id={`next-${id}`}
              ariaLabel="Next"
              disabled={page == pages - 1}
              onClick={_ => setPage(_ => page + 1)}
            >
              {WeftDom.Jsx.string("›")}
            </button>
          </div>
        : WeftDom.Jsx.null}
    </div>
    <div className="carousel-window">
      <div
        className="carousel-track"
        style={Dict.fromArray([("transform", `translateX(-${Int.toString(page * 100)}%)`)])}
      >
        children
      </div>
    </div>
  </div>
}
