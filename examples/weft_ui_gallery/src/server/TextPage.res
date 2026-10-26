@@weft.server

module Ui = WeftUi

let text = WeftDom.Jsx.string

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Heading" summary="A heading: its level is its element, its size how big it looks."
    >
      <Specimen.Example
        caption="Each level, at its own size"
        code={`<Heading level=#h1> {text("A page's title")} </Heading>
<Heading level=#h3 size=#xl> {text("An h3 that looks like an h2")} </Heading>`}
      >
        <Ui.Stack gap=#sm>
          <Ui.Heading level=#h3 size=#xxl> {text("The h1 size (xxl)")} </Ui.Heading>
          <Ui.Heading level=#h3 size=#xl> {text("The h2 size (xl)")} </Ui.Heading>
          <Ui.Heading level=#h3> {text("An h3 (lg)")} </Ui.Heading>
          <Ui.Heading level=#h4> {text("An h4 (md)")} </Ui.Heading>
          <Ui.Heading level=#h5> {text("An h5 (sm)")} </Ui.Heading>
          <Ui.Heading level=#h6> {text("An h6 (xs)")} </Ui.Heading>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section name="Text" summary="Text in a tone, size and weight.">
      <Specimen.Example
        caption="Tones"
        code={`<Text tone=#muted> {text("Muted")} </Text>
<Text tone=#danger> {text("Danger")} </Text>`}
      >
        <Ui.Stack gap=#xs>
          {([#default, #muted, #accent, #success, #warning, #danger]: array<Ui.Text.tone>)
          ->Array.map(tone =>
            <Ui.Text key={(tone :> string)} tone> {text(`tone=#${(tone :> string)}`)} </Ui.Text>
          )
          ->WeftDom.Jsx.array}
        </Ui.Stack>
      </Specimen.Example>
      <Specimen.Example
        caption="Sizes, weights and the rest"
        code={`<Text size=#sm weight=#semibold> ... </Text>
<Text numeric=true> {text("1,111.11")} </Text>
<Text truncate=true> ... </Text>
<Text as_=#span italic=true> ... </Text>`}
      >
        <Ui.Stack gap=#xs>
          <Ui.Text size=#xs> {text("size=#xs")} </Ui.Text>
          <Ui.Text size=#sm> {text("size=#sm")} </Ui.Text>
          <Ui.Text size=#md> {text("size=#md")} </Ui.Text>
          <Ui.Text size=#lg> {text("size=#lg")} </Ui.Text>
          <Ui.Text weight=#semibold> {text("weight=#semibold")} </Ui.Text>
          <Ui.Text italic=true> {text("italic")} </Ui.Text>
          <Ui.Text numeric=true> {text("numeric: 1,111.11 and 9,999.99 line up")} </Ui.Text>
          <div style={dict{"width": "16rem"}}>
            <Ui.Text truncate=true>
              {text("truncate: a sentence far too long for the box it's in, cut off")}
            </Ui.Text>
          </div>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Link"
      summary="A link, in a tone and with its underline always, on hover, or never. An app's navigating links wear Link.className()."
    >
      <Specimen.Example
        caption="Tones and underlines"
        code={`<Link href> {text("Accent")} </Link>
<Link href tone=#muted underline=#hover> {text("Muted, on hover")} </Link>
<Link href external_=true> {text("External")} </Link>`}
      >
        <Ui.Stack direction=#row gap=#lg wrap=true>
          <Ui.Link href="#link"> {text("Accent")} </Ui.Link>
          <Ui.Link href="#link" tone=#muted underline=#hover> {text("Muted, on hover")} </Ui.Link>
          <Ui.Link href="#link" tone=#inherit underline=#none> {text("Inherit, none")} </Ui.Link>
          <Ui.Link href="https://www.w3.org/WAI/ARIA/apg/" external_=true>
            {text("External")}
          </Ui.Link>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="VisuallyHidden"
      summary="Text for assistive technology only, or shown while it has focus."
    >
      <Specimen.Example
        caption="A hidden label beside a symbol, and a skip link (tab to it)"
        code={`<span ariaHidden="true"> {text("★★★★☆")} </span>
<VisuallyHidden> {text("4 out of 5 stars")} </VisuallyHidden>
<VisuallyHidden focusable=true> <Link href="#main"> {text("Skip to content")} </Link> </VisuallyHidden>`}
      >
        <Ui.Stack direction=#row gap=#lg align=#center>
          <span>
            <span ariaHidden="true"> {text("★★★★☆")} </span>
            <Ui.VisuallyHidden> {text("4 out of 5 stars")} </Ui.VisuallyHidden>
          </span>
          <Ui.VisuallyHidden focusable=true>
            <Ui.Link href="#main"> {text("Skip to content")} </Ui.Link>
          </Ui.VisuallyHidden>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
