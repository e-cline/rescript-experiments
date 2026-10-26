@@weft.server

module Ui = WeftUi

let text = WeftDom.Jsx.string

@weft.component({kind: Server})
let make = () =>
  <Specimen.Page
    title="weft_ui"
    summary="Accessible, styled components for Weft, each in every variant. Every page is rendered on the server; the interactive parts hydrate."
  >
    <Ui.Grid minItemWidth="240px" gap=#lg>
      {Groups.all
      ->Array.map(group =>
        <Ui.Card.Root key=group.slug as_=#article interactive=true dataId={`group-${group.slug}`}>
          <Ui.Card.Header>
            <Ui.Card.Title level=#h2>
              <NavLink
                href={`/${group.slug}`}
                className={Ui.Link.className(~tone=#inherit, ~underline=#hover, ())}
              >
                {text(group.title)}
              </NavLink>
            </Ui.Card.Title>
            <Ui.Card.Description> {text(group.summary)} </Ui.Card.Description>
          </Ui.Card.Header>
          <Ui.Card.Footer>
            {group.components
            ->Array.map(name =>
              <Ui.Badge key=name size=#sm shape=#rounded> {text(name)} </Ui.Badge>
            )
            ->WeftDom.Jsx.array}
          </Ui.Card.Footer>
        </Ui.Card.Root>
      )
      ->WeftDom.Jsx.array}
    </Ui.Grid>
  </Specimen.Page>
