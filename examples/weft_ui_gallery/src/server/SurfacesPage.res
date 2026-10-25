@@weft.server

module Ui = WeftUi

let text = WeftDom.Jsx.string

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Card" summary="A surface for one thing, with a header, content and a footer."
    >
      <Specimen.Example caption="Each variant">
        <Ui.Grid minItemWidth="220px" gap=#lg>
          {[#outline, #elevated, #ghost]
          ->Array.map(variant =>
            <Ui.Card.Root key={(variant :> string)} as_=#article variant>
              <Ui.Card.Header>
                <Ui.Card.Title> {text("Wool scarf")} </Ui.Card.Title>
                <Ui.Card.Description>
                  {text(`variant=#${(variant :> string)}`)}
                </Ui.Card.Description>
              </Ui.Card.Header>
              <Ui.Card.Content>
                <Ui.Text size=#sm>
                  {text("Merino, hand-dyed, and long enough to wrap twice.")}
                </Ui.Text>
              </Ui.Card.Content>
              <Ui.Card.Footer>
                <Ui.Badge tone=#success> {text("In stock")} </Ui.Badge>
                <Ui.Text as_=#span weight=#semibold numeric=true> {text("$48.00")} </Ui.Text>
              </Ui.Card.Footer>
            </Ui.Card.Root>
          )
          ->WeftDom.Jsx.array}
        </Ui.Grid>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Alert"
      summary="A message in a box. Danger and warning are alerts, announced at once; the rest are statuses."
    >
      <Specimen.Example caption="Each tone, one with an action">
        <Ui.Stack gap=#sm>
          <Ui.Alert.Root tone=#info role=#none>
            <Ui.Alert.Title> {text("Heads up")} </Ui.Alert.Title>
            <Ui.Alert.Description> {text("tone=#info: worth knowing.")} </Ui.Alert.Description>
          </Ui.Alert.Root>
          <Ui.Alert.Root tone=#success role=#none>
            <Ui.Alert.Title> {text("Saved")} </Ui.Alert.Title>
            <Ui.Alert.Description> {text("tone=#success: it worked.")} </Ui.Alert.Description>
          </Ui.Alert.Root>
          <Ui.Alert.Root tone=#warning role=#none>
            <Ui.Alert.Description>
              {text("tone=#warning, with no title: you're offline, so prices may be out of date.")}
            </Ui.Alert.Description>
          </Ui.Alert.Root>
          <Ui.Alert.Root tone=#danger role=#none>
            <Ui.Alert.Title> {text("Couldn't load this")} </Ui.Alert.Title>
            <Ui.Alert.Description>
              {text("tone=#danger: the reviews service is down.")}
            </Ui.Alert.Description>
            <Ui.Alert.Action>
              <Ui.Button size=#sm> {text("Retry")} </Ui.Button>
            </Ui.Alert.Action>
          </Ui.Alert.Root>
          <Ui.Alert.Root tone=#neutral role=#none>
            <Ui.Alert.Description> {text("tone=#neutral: a note.")} </Ui.Alert.Description>
          </Ui.Alert.Root>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Badge"
      summary="A small label, in a tone and variant; Badge.className() makes a link a chip."
    >
      <Specimen.Example caption="Each tone, in each variant">
        <Ui.Stack gap=#sm>
          {[#soft, #solid, #outline]
          ->Array.map(variant =>
            <Ui.Stack key={(variant :> string)} direction=#row gap=#sm wrap=true>
              {([#neutral, #accent, #success, #warning, #danger]: array<Ui.Variants.tone>)
              ->Array.map(tone =>
                <Ui.Badge key={(tone :> string)} tone variant>
                  {text(`${(variant :> string)} ${(tone :> string)}`)}
                </Ui.Badge>
              )
              ->WeftDom.Jsx.array}
            </Ui.Stack>
          )
          ->WeftDom.Jsx.array}
        </Ui.Stack>
      </Specimen.Example>
      <Specimen.Example caption="Small and rounded, and links as chips">
        <Ui.Stack direction=#row gap=#sm wrap=true align=#center>
          <Ui.Badge size=#sm shape=#rounded tone=#accent> {text("New")} </Ui.Badge>
          <Ui.Badge size=#sm tone=#danger variant=#solid> {text("3")} </Ui.Badge>
          <a href="#badge" className={Ui.Badge.className(~variant=#outline, ~link=true, ())}>
            {text("Merino")}
          </a>
          <a href="#badge" className={Ui.Badge.className(~variant=#outline, ~link=true, ())}>
            {text("Hand-dyed")}
          </a>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="EmptyState" summary="What a place shows when there's nothing in it yet."
    >
      <Specimen.Example caption="bordered=true, with an action">
        <Ui.EmptyState.Root bordered=true>
          <Ui.EmptyState.Title> {text("Your cart is empty")} </Ui.EmptyState.Title>
          <Ui.EmptyState.Description>
            {text("Anything you add shows up here, ready for checkout.")}
          </Ui.EmptyState.Description>
          <Ui.EmptyState.Action>
            <a href="#empty-state" className={Ui.Button.className(~variant=#primary, ())}>
              {text("Keep shopping")}
            </a>
          </Ui.EmptyState.Action>
        </Ui.EmptyState.Root>
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
