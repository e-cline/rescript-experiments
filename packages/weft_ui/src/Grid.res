/***
A grid: a number of equal columns, columns as wide as they can be but at least `minItemWidth`
(as many as fit), or a template of your own. Below a breakpoint (`stackBelow`), one column.

```rescript
<Grid minItemWidth="200px" gap=#lg> {cards} </Grid>
<Grid template="220px 1fr" stackBelow=#md> <Filters /> <Results /> </Grid>
```

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  /** The columns, set per grid (`style`): a template, a count, or a minimum width. */
  let template = Css.var("none")
  let columns = Css.var("1")
  let minItemWidth = Css.var("200px")

  let grid = Css.class(~layer, {display: Grid, minWidth: Zero})
  let byTemplate = Css.class(~layer, {gridTemplateColumns: Tokens.value(template)})
  let byCount = Css.class(
    ~layer,
    {gridTemplateColumns: `repeat(${Tokens.value(columns)}, minmax(0, 1fr))`},
  )
  let byWidth = Css.class(
    ~layer,
    {
      gridTemplateColumns: `repeat(auto-fill, minmax(min(${Tokens.value(
          minItemWidth,
        )}, 100%), 1fr))`,
    },
  )
  let stackBelowSm = Css.class(
    ~layer,
    {media: [Css.media(~query="(max-width: 640px)", {gridTemplateColumns: "minmax(0, 1fr)"})]},
  )
  let stackBelowMd = Css.class(
    ~layer,
    {media: [Css.media(~query="(max-width: 768px)", {gridTemplateColumns: "minmax(0, 1fr)"})]},
  )
}

@weft.component
let make = (
  ~as_: [#div | #section | #ul | #ol]=#div,
  ~columns: option<int>=?,
  ~minItemWidth: option<string>=?,
  ~template: option<string>=?,
  ~gap: Variants.space=#md,
  ~stackBelow: [#sm | #md | #never]=#never,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~ariaLabel=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) => {
  let (layout, vars) = switch (template, minItemWidth, columns) {
  | (Some(template), _, _) => (Styles.byTemplate, [(Styles.template, template)])
  | (None, Some(width), _) => (Styles.byWidth, [(Styles.minItemWidth, width)])
  | (None, None, columns) => (
      Styles.byCount,
      [(Styles.columns, Int.toString(columns->Option.getOr(1)))],
    )
  }
  Host.element(
    ~attrs,
    (as_ :> string),
    {
      ?id,
      className: Host.classes(
        Array.concat(
          [Styles.grid, layout, Stack.gapClass(gap)],
          switch stackBelow {
          | #sm => [Styles.stackBelowSm]
          | #md => [Styles.stackBelowMd]
          | #never => []
          },
        ),
        className,
      ),
      style: Host.style(Css.vars(vars), style),
      ?dataId,
      ?ariaLabel,
      ?children,
    },
  )
}
