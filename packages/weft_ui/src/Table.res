/***
A table: for data in rows and columns (a cart's lines, a list of orders), so assistive technology
can read each cell with its row and column.

```rescript
<Table.Root scrollLabel="Your cart">
  <Table.Caption hidden=true> {text("Items in your cart")} </Table.Caption>
  <Table.Head>
    <Table.Row>
      <Table.HeaderCell> {text("Item")} </Table.HeaderCell>
      <Table.HeaderCell align=#end> {text("Total")} </Table.HeaderCell>
    </Table.Row>
  </Table.Head>
  <Table.Body> ... <Table.Cell numeric=true> ... </Table.Cell> ... </Table.Body>
</Table.Root>
```

A table wider than its place scrolls sideways. With `scrollLabel`, its scrolling box is a labelled
region that takes the keyboard's focus, so it can be scrolled without a pointer.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let scroll = Css.class(
    ~layer,
    {overflowX: Auto, maxInlineSize: Pct(100.), focusVisible: Tokens.focusVisible()},
  )
  let table = Css.class(
    ~layer,
    {
      inlineSize: Pct(100.),
      borderCollapse: "collapse",
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.fg),
      // Column headings: muted, at the bottom of the header row. Row headings are as their row.
      selectors: [
        (
          "thead th",
          Css.style({color: Var(Tokens.fgMuted), verticalAlign: "bottom", whiteSpace: Nowrap}),
        ),
      ],
    },
  )
  /** The cells' padding, by density. */
  let cellPadding = Css.var("10px 12px")
  let compact = Css.class(~layer, {vars: [(cellPadding, "6px 8px")]})
  let striped = Css.class(
    ~layer,
    {
      selectors: [
        ("tbody tr:nth-child(even)", Css.style({backgroundColor: Var(Tokens.surfaceMuted)})),
      ],
    },
  )
  let caption = Css.class(
    ~layer,
    {
      paddingBlockEnd: Var(Tokens.spaceSm),
      color: Var(Tokens.fgMuted),
      textAlign: Start,
    },
  )
  let captionHidden = Css.class(~layer, VisuallyHidden.rules)
  let row = Css.class(
    ~layer,
    {
      borderBottom: `1px solid ${Tokens.value(Tokens.border)}`,
      selectors: [
        ("&[data-state=\"selected\"]", Css.style({backgroundColor: Var(Tokens.accentSoft)})),
      ],
    },
  )
  let headerCell = Css.class(
    ~layer,
    {
      padding: Raw(Tokens.value(cellPadding)),
      textAlign: Start,
      fontWeight: 600,
      verticalAlign: "middle",
    },
  )
  let cell = Css.class(
    ~layer,
    {padding: Raw(Tokens.value(cellPadding)), textAlign: Start, verticalAlign: "middle"},
  )
  let center = Css.class(~layer, {textAlign: Center})
  let end_ = Css.class(~layer, {textAlign: End})
  let numeric = Css.class(~layer, {textAlign: End, fontVariantNumeric: TabularNums})
}

type align = [#start | #center | #end]

let alignClass = (align: align) =>
  switch align {
  | #start => []
  | #center => [Styles.center]
  | #end => [Styles.end_]
  }

module Root = {
  @weft.component
  let make = (
    ~density: [#comfortable | #compact]=#comfortable,
    ~striped=false,
    ~scrollLabel: option<string>=?,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~ariaLabel=?,
    ~ariaLabelledby=?,
    ~attrs: WeftDom.DomProps.props={},
    ~children=?,
  ) =>
    <div
      className=Styles.scroll
      role=?{scrollLabel->Option.map(_ => "region")}
      ariaLabel=?scrollLabel
      tabIndex=?{scrollLabel->Option.map(_ => 0)}
    >
      <table
        {...attrs}
        ?id
        className={Host.classes(
          Array.concat(
            density == #compact ? [Styles.table, Styles.compact] : [Styles.table],
            striped ? [Styles.striped] : [],
          ),
          className,
        )}
        ?style
        ?dataId
        ?ariaLabel
        ?ariaLabelledby
        ?children
      />
    </div>
}

module Caption = {
  /** The table's name. `hidden` keeps it for assistive technology only. */
  @weft.component
  let make = (~hidden=false, ~id=?, ~className=?, ~children=?) =>
    <caption
      ?id
      className={Host.classes([hidden ? Styles.captionHidden : Styles.caption], className)}
      ?children
    />
}

module Head = {
  @weft.component
  let make = (~className=?, ~children=?) => <thead className=?className ?children />
}

module Body = {
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) =>
    <tbody className=?className ?dataId ?children />
}

module Foot = {
  @weft.component
  let make = (~className=?, ~children=?) => <tfoot className=?className ?children />
}

module Row = {
  /** A row. `selected` marks it (`data-state="selected"`), for its look. */
  @weft.component
  let make = (~selected=false, ~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <tr
      ?id
      className={Host.classes([Styles.row], className)}
      ?dataId
      dataState=?{selected ? Some("selected") : None}
      ?children
    />
}

module HeaderCell = {
  /** A column's heading (or, `scope=#row`, a row's). */
  @weft.component
  let make = (
    ~scope: [#col | #row]=#col,
    ~align: align=#start,
    ~numeric=false,
    ~colSpan=?,
    ~ariaSort=?,
    ~id=?,
    ~className=?,
    ~dataId=?,
    ~children=?,
  ) =>
    <th
      ?id
      scope={(scope :> string)}
      className={Host.classes(
        Array.concat([Styles.headerCell], numeric ? [Styles.numeric] : alignClass(align)),
        className,
      )}
      ?colSpan
      ?ariaSort
      ?dataId
      ?children
    />
}

module Cell = {
  /** A cell. `numeric` aligns it at the end, in figures of one width. */
  @weft.component
  let make = (
    ~align: align=#start,
    ~numeric=false,
    ~colSpan=?,
    ~id=?,
    ~className=?,
    ~dataId=?,
    ~children=?,
  ) =>
    <td
      ?id
      className={Host.classes(
        Array.concat([Styles.cell], numeric ? [Styles.numeric] : alignClass(align)),
        className,
      )}
      ?colSpan
      ?dataId
      ?children
    />
}
