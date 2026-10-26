@@weft.server

module Ui = WeftUi

let text = WeftDom.Jsx.string

let variants: array<Ui.Button.variant> = [#primary, #secondary, #outline, #ghost, #danger, #link]

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Button"
      summary="A button, by how much it stands out and how big it is. Busy, it shows a spinner and stops clicks, but keeps its focus."
    >
      <Specimen.Example
        caption="Each variant"
        code={`<Button variant=#primary> {text("Primary")} </Button>
<Button> {text("Secondary")} </Button>
<Button variant=#outline> {text("Outline")} </Button>
<Button variant=#ghost> {text("Ghost")} </Button>
<Button variant=#danger> {text("Danger")} </Button>
<Button variant=#link> {text("Link")} </Button>`}
      >
        <Ui.Stack direction=#row gap=#sm wrap=true align=#center>
          {variants
          ->Array.map(variant =>
            <Ui.Button key={(variant :> string)} variant> {text((variant :> string))} </Ui.Button>
          )
          ->WeftDom.Jsx.array}
        </Ui.Stack>
      </Specimen.Example>
      <Specimen.Example
        caption="Sizes, a pill, disabled, busy"
        code={`<Button size=#sm> {text("Small")} </Button>
<Button size=#lg> {text("Large")} </Button>
<Button shape=#pill variant=#outline> {text("Pill")} </Button>
<Button disabled=true> {text("Disabled")} </Button>
<Button variant=#primary busy=true> {text("Busy")} </Button>`}
      >
        <Ui.Stack direction=#row gap=#sm wrap=true align=#center>
          <Ui.Button size=#sm> {text("Small")} </Ui.Button>
          <Ui.Button> {text("Medium")} </Ui.Button>
          <Ui.Button size=#lg> {text("Large")} </Ui.Button>
          <Ui.Button shape=#pill variant=#outline> {text("Pill")} </Ui.Button>
          <Ui.Button disabled=true> {text("Disabled")} </Ui.Button>
          <Ui.Button variant=#primary busy=true> {text("Busy")} </Ui.Button>
        </Ui.Stack>
      </Specimen.Example>
      <Specimen.Example
        caption="Pressed, in an entrypoint: busy for a moment"
        code={`<Button variant=#primary busy={state == #saving} onClick={_ => setState(_ => #saving)}>
  {text(state == #saving ? "Saving…" : "Save")}
</Button>`}
      >
        <SaveDemo />
      </Specimen.Example>
      <Specimen.Example
        caption="fullWidth=true, and a link wearing Button.className()"
        code={`<Button variant=#primary fullWidth=true> {text("Place order")} </Button>
<a href className={Button.className(~variant=#outline, ())}> {text("A link")} </a>`}
      >
        <Ui.Stack gap=#sm>
          <Ui.Button variant=#primary fullWidth=true> {text("Place order")} </Ui.Button>
          <a href="#button" className={Ui.Button.className(~variant=#outline, ())}>
            {text("A link that looks like a button")}
          </a>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="IconButton"
      summary="A square button with an icon and no text: its label, which is required, names it."
    >
      <Specimen.Example
        caption="Sizes and variants"
        code={`<IconButton label="Next" variant=#secondary> {text("›")} </IconButton>
<IconButton label="Dismiss"> {text("×")} </IconButton>
<IconButton label="Save for later" size=#lg shape=#pill variant=#outline>
  {text("♡")}
</IconButton>`}
      >
        <Ui.Stack direction=#row gap=#sm align=#center>
          <Ui.IconButton label="Previous" size=#sm variant=#secondary>
            {text("‹")}
          </Ui.IconButton>
          <Ui.IconButton label="Next" variant=#secondary> {text("›")} </Ui.IconButton>
          <Ui.IconButton label="Dismiss"> {text("×")} </Ui.IconButton>
          <Ui.IconButton label="Save for later" size=#lg shape=#pill variant=#outline>
            {text("♡")}
          </Ui.IconButton>
          <Ui.IconButton label="Remove" variant=#danger> {text("−")} </Ui.IconButton>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Spinner"
      summary="Something's working, said to assistive technology unless it's said already."
    >
      <Specimen.Example
        caption="Sizes, and in a sentence"
        code={`<Spinner size=#sm />
<Spinner size=#lg label="Loading the reviews" />
<Text tone=#muted> <Spinner size=#sm announce=false /> {text(" Checking stock…")} </Text>`}
      >
        <Ui.Stack direction=#row gap=#lg align=#center>
          <Ui.Spinner size=#sm />
          <Ui.Spinner />
          <Ui.Spinner size=#lg label="Loading the reviews" />
          <Ui.Text tone=#muted>
            <Ui.Spinner size=#sm announce=false />
            {text(" Checking stock…")}
          </Ui.Text>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section name="Skeleton" summary="A placeholder in the shape of what's coming.">
      <Specimen.Example
        caption="Lines, a picture and an avatar"
        code={`<Skeleton shape=#circle width="48px" height="48px" />
<div ariaBusy="true">
  <Skeleton shape=#rect height="120px" />
  <Skeleton lines=3 />
</div>`}
      >
        <Ui.Stack direction=#row gap=#lg align=#start>
          <Ui.Skeleton shape=#circle width="48px" height="48px" />
          <div style={dict{"flex": "1"}} ariaBusy="true">
            <Ui.Stack gap=#md>
              <Ui.Skeleton shape=#rect height="120px" />
              <Ui.Skeleton lines=3 />
            </Ui.Stack>
          </div>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
