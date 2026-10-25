@@weft.server

/*** The frame around every page: the header, the sidebar's groups, and the page's content. */

open WeftCss
module Ui = WeftUi

let text = WeftDom.Jsx.string

module Styles = {
  let header = Css.class({
    borderBottom: `1px solid ${Ui.Tokens.value(Ui.Tokens.border)}`,
    paddingBlock: Var(Ui.Tokens.spaceMd),
  })
  let logo = Css.class({fontWeight: 700, fontSize: Var(Ui.Tokens.textLg)})
  let sidebar = Css.class({
    paddingBlock: Var(Ui.Tokens.spaceXl),
    media: [
      Css.media(~query="(min-width: 769px)", {position: Sticky, top: Zero, alignSelf: Start}),
    ],
  })
  let main = Css.class({paddingBlock: Var(Ui.Tokens.spaceXl), minWidth: Zero})
}

@weft.component({kind: Server})
let make = (~current: option<string>=?, ~children) =>
  <div className=Theme.root>
    <header className=Styles.header>
      <Ui.Container size=#xl>
        <Ui.Stack direction=#row align=#center justify=#between>
          <NavLink
            href="/"
            dataId="home-link"
            className={Ui.Link.className(~tone=#inherit, ~underline=#none, ())}
          >
            <span className=Styles.logo> {text("weft_ui")} </span>
          </NavLink>
          <Ui.Text tone=#muted size=#sm> {text("Components for Weft")} </Ui.Text>
        </Ui.Stack>
      </Ui.Container>
    </header>
    <Ui.Container size=#xl>
      <Ui.Grid template="200px minmax(0, 1fr)" gap=#xl stackBelow=#md>
        <nav className=Styles.sidebar ariaLabel="Components">
          <Ui.List.Root gap=#xs>
            {Groups.all
            ->Array.map(group =>
              <Ui.List.Item key=group.slug>
                <NavLink
                  href={`/${group.slug}`}
                  dataId={`nav-${group.slug}`}
                  current={current == Some(group.slug)}
                  className={Ui.Link.className(~tone=#muted, ~underline=#hover, ())}
                >
                  {text(group.title)}
                </NavLink>
              </Ui.List.Item>
            )
            ->WeftDom.Jsx.array}
          </Ui.List.Root>
        </nav>
        <main dataId="main" className=Styles.main> children </main>
      </Ui.Grid>
    </Ui.Container>
  </div>
