@@weft.server

open WeftCss
module Ui = WeftUi

let text = WeftDom.Jsx.string

module Styles = {
  /** A box to lay out, so the layout shows. */
  let box = Css.class({
    padding: Pair(Var(Ui.Tokens.spaceSm), Var(Ui.Tokens.spaceMd)),
    borderRadius: Var(Ui.Tokens.radiusMd),
    backgroundColor: Var(Ui.Tokens.accentSoft),
    color: Var(Ui.Tokens.accentSoftFg),
    fontSize: Var(Ui.Tokens.textSm),
    textAlign: Center,
  })
  let tall = Css.class({paddingBlock: Var(Ui.Tokens.spaceXl)})
  let band = Css.class({
    backgroundColor: Var(Ui.Tokens.surfaceMuted),
    paddingBlock: Var(Ui.Tokens.spaceMd),
  })
}

let box = (~tall=false, label) =>
  <div className={tall ? Css.cx([Styles.box, Styles.tall]) : Styles.box}> {text(label)} </div>

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Stack" summary="Children in a column or a row, a gap apart from the space scale."
    >
      <Specimen.Example caption="A column (the default), gap=#md">
        <Ui.Stack>
          {box("One")}
          {box("Two")}
          {box("Three")}
        </Ui.Stack>
      </Specimen.Example>
      <Specimen.Example caption="A row, aligned to the centre, spaced between, wrapping">
        <Ui.Stack direction=#row align=#center justify=#between wrap=true>
          {box("Short")}
          {box(~tall=true, "Tall")}
          {box("Short")}
        </Ui.Stack>
      </Specimen.Example>
      <Specimen.Example caption="Every gap, from #none to #xxl">
        <Ui.Stack gap=#lg>
          {([#none, #xs, #sm, #md, #lg, #xl, #xxl]: array<Ui.Variants.space>)
          ->Array.map(gap =>
            <Ui.Stack key={(gap :> string)} direction=#row gap align=#center>
              <Ui.Text as_=#span size=#sm tone=#muted> {text((gap :> string))} </Ui.Text>
              {box("A")}
              {box("B")}
              {box("C")}
            </Ui.Stack>
          )
          ->WeftDom.Jsx.array}
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Grid"
      summary="Equal columns, columns at least so wide (as many as fit), or a template; one column on a narrow screen with stackBelow."
    >
      <Specimen.Example caption="columns=3">
        <Ui.Grid columns=3>
          {box("1")}
          {box("2")}
          {box("3")}
          {box("4")}
          {box("5")}
        </Ui.Grid>
      </Specimen.Example>
      <Specimen.Example caption="minItemWidth=\"140px\": as many as fit">
        <Ui.Grid minItemWidth="140px">
          {Array.fromInitializer(~length=7, index =>
            <div key={Int.toString(index)}> {box(Int.toString(index + 1))} </div>
          )->WeftDom.Jsx.array}
        </Ui.Grid>
      </Specimen.Example>
      <Specimen.Example caption="template=\"200px 1fr\", stackBelow=#md">
        <Ui.Grid template="200px 1fr" stackBelow=#md>
          {box("Sidebar")}
          {box("Content")}
        </Ui.Grid>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Container" summary="The page's column: centred, at most a width, with a gutter."
    >
      <Specimen.Example caption="size=#sm, in a band the width of the frame">
        <div className=Styles.band>
          <Ui.Container size=#sm> {box("At most Tokens.containerSm wide")} </Ui.Container>
        </div>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section name="Separator" summary="A line between things: a separator, or decorative.">
      <Specimen.Example caption="Horizontal, and vertical in a row">
        <Ui.Stack>
          <Ui.Text> {text("Above")} </Ui.Text>
          <Ui.Separator />
          <Ui.Stack direction=#row align=#stretch>
            <Ui.Text> {text("Left")} </Ui.Text>
            <Ui.Separator orientation=#vertical />
            <Ui.Text> {text("Right")} </Ui.Text>
          </Ui.Stack>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
