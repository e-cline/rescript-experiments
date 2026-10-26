/***
A popup placed against its trigger, for `Popover`, `Menu` and `Tooltip`: an element in the top
layer (the Popover API), positioned by CSS anchor positioning, which flips it to the other side
when there's no room.
*/
open WeftCss

module Dom = WeftDom.Dom

module Styles = {
  let layer = Tokens.layer
  /** The popover's own look is the browser's (centred, bordered): this places it instead. */
  let anchored = Css.class(
    ~layer,
    {
      position: Fixed,
      inset: Auto,
      margin: Var(Tokens.spaceXs),
      padding: Zero,
      border: "none",
      overflow: Visible,
      color: Raw("inherit"),
      backgroundColor: Transparent,
      positionTryFallbacks: "flip-block, flip-inline",
    },
  )
}

type side = [#top | #bottom | #start | #end]
type align = [#start | #center | #end]

/** Where the popup goes around its trigger, as `position-area` says it. */
let area = (~side: side, ~align: align) =>
  switch (side, align) {
  | (#bottom, #start) => "block-end span-inline-end"
  | (#bottom, #center) => "block-end"
  | (#bottom, #end) => "block-end span-inline-start"
  | (#top, #start) => "block-start span-inline-end"
  | (#top, #center) => "block-start"
  | (#top, #end) => "block-start span-inline-start"
  | (#start, #start) => "inline-start span-block-end"
  | (#start, #center) => "inline-start"
  | (#start, #end) => "inline-start span-block-start"
  | (#end, #start) => "inline-end span-block-end"
  | (#end, #center) => "inline-end"
  | (#end, #end) => "inline-end span-block-start"
  }

/** The trigger's style: its `anchor-name`, with the caller's. */
let triggerStyle = (~anchor, style) => Host.style(dict{"anchor-name": anchor}, style)

/** The popup's style: placed against `anchor`, on `side`, aligned. */
let popupStyle = (~anchor, ~side, ~align, style) =>
  Host.style(dict{"position-anchor": anchor, "position-area": area(~side, ~align)}, style)

/**
Shows and hides `ref`'s popover as `open_` says, keeping `shown` (what the page has: its `toggle`
events set it, `onToggle`) in step, so a popover the browser closed (light dismiss) isn't hidden
again, nor one it opened shown again.
*/
let usePopover = (ref: Overlay.ref, ~shown: Weft.Ref.t<bool>, open_: bool) =>
  Weft.Hooks.useLayoutEffect1(() => {
    ref.current->Nullable.forEach(popup =>
      if open_ && !shown.current {
        shown.current = true
        Dom.Popover.show(popup)
      } else if !open_ && shown.current {
        shown.current = false
        Dom.Popover.hide(popup)
      }
    )
    None
  }, [open_])
