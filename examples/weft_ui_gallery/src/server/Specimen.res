@@weft.server

/***
A component on show: its name, what it's for, and examples of it, each in a frame of its own, with
a caption saying what it shows.
*/

open WeftCss
module Ui = WeftUi

let text = WeftDom.Jsx.string

module Styles = {
  let frame = Css.class({
    padding: Var(Ui.Tokens.spaceXl),
    border: `1px solid ${Ui.Tokens.value(Ui.Tokens.border)}`,
    borderRadius: Var(Ui.Tokens.radiusLg),
    backgroundColor: Var(Ui.Tokens.surface),
    overflowX: Auto,
  })
}

/** A component's name as an `id`: `DescriptionList` as `description-list`. */
let slug = name => name->String.replaceRegExp(/([a-z])([A-Z])/g, "$1-$2")->String.toLowerCase

module Section = {
  @weft.component({kind: Server})
  let make = (~name: string, ~summary: string, ~children) =>
    <section dataId={`specimen-${slug(name)}`} ariaLabelledby={slug(name)}>
      <Ui.Stack gap=#md>
        <Ui.Stack gap=#xs>
          <Ui.Heading level=#h2 id={slug(name)}> {text(name)} </Ui.Heading>
          <Ui.Text tone=#muted> {text(summary)} </Ui.Text>
        </Ui.Stack>
        children
      </Ui.Stack>
    </section>
}

module Example = {
  /** One example: what it shows, then it, in a frame. */
  @weft.component({kind: Server})
  let make = (~caption: string, ~children) =>
    <Ui.Stack gap=#sm>
      <Ui.Text as_=#p size=#sm weight=#medium> {text(caption)} </Ui.Text>
      <div className=Styles.frame> children </div>
    </Ui.Stack>
}

/** A group's page: its title and summary, then its components. */
module Page = {
  @weft.component({kind: Server})
  let make = (~title: string, ~summary: string, ~children) =>
    <Ui.Stack gap=#xxl>
      <Ui.Stack gap=#xs>
        <Ui.Heading level=#h1 dataId="page-title"> {text(title)} </Ui.Heading>
        <Ui.Text tone=#muted size=#lg> {text(summary)} </Ui.Text>
      </Ui.Stack>
      children
    </Ui.Stack>
}
