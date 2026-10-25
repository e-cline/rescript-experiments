/***
The props every host element (`<div>`, `<input>`, ...) takes. One record covers every tag, as with
`@rescript/react`'s `JsxDOM.domProps`; this is a deliberate subset, to grow as needed.

How each is applied (see `DomHost`):

- `value` and `checked` are set as properties, so a controlled input shows its prop.
- `style` is a dict of CSS properties: kebab-case names (`"background-color"`, `"--custom"`) go
  through `style.setProperty`, others (`"backgroundColor"`) are assigned. Only changed keys are
  touched.
- `on*` handlers become event listeners: `onClick` listens for `click`, `onDoubleClick` for
  `dblclick`, and the rest by lowercasing (`onKeyDown` for `keydown`). Unlike React, `onChange` is
  the DOM's own `change` event; use `onInput` to see every keystroke.
- Everything else is an attribute: `className` is `class`, `htmlFor` is `for`, and `true`/`false`
  add or remove a boolean attribute (`disabled`, `hidden`, ...).
*/

type style = dict<string>

type props = {
  id?: string,
  className?: string,
  style?: style,
  title?: string,
  role?: string,
  hidden?: bool,
  tabIndex?: int,
  @as("aria-label") ariaLabel?: string,
  @as("aria-pressed") ariaPressed?: string,
  @as("aria-checked") ariaChecked?: string,
  @as("aria-describedby") ariaDescribedby?: string,
  @as("aria-labelledby") ariaLabelledby?: string,
  @as("aria-expanded") ariaExpanded?: string,
  @as("aria-selected") ariaSelected?: string,
  @as("aria-controls") ariaControls?: string,
  @as("aria-current") ariaCurrent?: string,
  @as("aria-hidden") ariaHidden?: string,
  @as("aria-live") ariaLive?: string,
  @as("aria-modal") ariaModal?: string,
  @as("aria-busy") ariaBusy?: string,
  // Forms' and widgets' state
  @as("aria-invalid") ariaInvalid?: string,
  @as("aria-required") ariaRequired?: string,
  @as("aria-disabled") ariaDisabled?: string,
  @as("aria-readonly") ariaReadonly?: string,
  @as("aria-errormessage") ariaErrormessage?: string,
  // Popups and composite widgets
  @as("aria-haspopup") ariaHaspopup?: string,
  @as("aria-activedescendant") ariaActivedescendant?: string,
  @as("aria-autocomplete") ariaAutocomplete?: string,
  @as("aria-orientation") ariaOrientation?: string,
  @as("aria-multiselectable") ariaMultiselectable?: string,
  @as("aria-owns") ariaOwns?: string,
  @as("aria-setsize") ariaSetsize?: int,
  @as("aria-posinset") ariaPosinset?: int,
  // Ranges
  @as("aria-valuemin") ariaValuemin?: float,
  @as("aria-valuemax") ariaValuemax?: float,
  @as("aria-valuenow") ariaValuenow?: float,
  @as("aria-valuetext") ariaValuetext?: string,
  // Live regions, and the rest
  @as("aria-atomic") ariaAtomic?: string,
  @as("aria-relevant") ariaRelevant?: string,
  @as("aria-roledescription") ariaRoledescription?: string,
  @as("aria-level") ariaLevel?: int,
  @as("aria-sort") ariaSort?: string,
  @as("data-testid") dataTestId?: string,
  /** A name for tests to find the element by, where an `id` would be there only for them. */
  @as("data-id") dataId?: string,
  // A component's state, for styles to select on where ARIA has no attribute for it (`open` or
  // `closed`, a popup's side, a variant's name, ...).
  @as("data-state") dataState?: string,
  @as("data-orientation") dataOrientation?: string,
  @as("data-highlighted") dataHighlighted?: bool,
  @as("data-side") dataSide?: string,
  @as("data-variant") dataVariant?: string,
  // The document
  lang?: string,
  dir?: string,
  inert?: bool,
  // Disclosure and popups: `<details>`' and `<dialog>`'s `open`, and the Popover API's attributes
  @as("open") open_?: bool,
  popover?: string,
  popoverTarget?: string,
  popoverTargetAction?: string,
  // Links and media
  href?: string,
  target?: string,
  rel?: string,
  src?: string,
  alt?: string,
  width?: string,
  height?: string,
  // Forms
  @as("type") type_?: string,
  name?: string,
  value?: string,
  checked?: bool,
  disabled?: bool,
  placeholder?: string,
  readOnly?: bool,
  autoFocus?: bool,
  required?: bool,
  autoComplete?: string,
  inputMode?: string,
  maxLength?: int,
  htmlFor?: string,
  min?: string,
  max?: string,
  step?: string,
  rows?: int,
  cols?: int,
  colSpan?: int,
  rowSpan?: int,
  scope?: string,
  headers?: string,
  minLength?: int,
  pattern?: string,
  multiple?: bool,
  size?: int,
  form?: string,
  // Events
  onClick?: Dom.event => unit,
  onDoubleClick?: Dom.event => unit,
  onMouseDown?: Dom.event => unit,
  onMouseUp?: Dom.event => unit,
  onMouseEnter?: Dom.event => unit,
  onMouseLeave?: Dom.event => unit,
  onKeyDown?: Dom.event => unit,
  onKeyUp?: Dom.event => unit,
  onInput?: Dom.event => unit,
  onChange?: Dom.event => unit,
  onSubmit?: Dom.event => unit,
  onFocus?: Dom.event => unit,
  onBlur?: Dom.event => unit,
  // Focus moving in or out of an element or anything in it (they bubble; `focus` and `blur` don't)
  onFocusIn?: Dom.event => unit,
  onFocusOut?: Dom.event => unit,
  onPointerDown?: Dom.event => unit,
  onPointerUp?: Dom.event => unit,
  onPointerMove?: Dom.event => unit,
  onPointerEnter?: Dom.event => unit,
  onPointerLeave?: Dom.event => unit,
  // A `<details>` or popover opening or closing (`beforetoggle` before, `toggle` after)
  onToggle?: Dom.event => unit,
  onBeforeToggle?: Dom.event => unit,
  // A `<dialog>` closing, and asked to close (Escape)
  onClose?: Dom.event => unit,
  onCancel?: Dom.event => unit,
  // The element itself, from commit until removal.
  ref?: Weft.Ref.t<Nullable.t<Dom.element>>,
  children?: Weft.Element.t,
}

// The rules for applying props, which the DOM host (`DomHost`, setting them on nodes) and the HTML
// renderer (`Html`, writing them as markup) share, so the server writes what the client would set.

external toNullable: unknown => Nullable.t<unknown> = "%identity"
external toBool: unknown => bool = "%identity"
external fromBool: bool => unknown = "%identity"
@val external stringify: unknown => string = "String"

/** Whether `name` is an event handler's prop: `on` and a capital (`onClick`). */
let isEventProp = (name: string) =>
  name->String.startsWith("on") &&
  String.length(name) > 2 && {
    let third = name->String.charAt(2)
    third == String.toUpperCase(third)
  }

/** The DOM event an `on*` prop listens for. */
let eventName = (prop: string) =>
  switch prop {
  | "onDoubleClick" => "dblclick"
  | _ => prop->String.slice(~start=2)->String.toLowerCase
  }

/** The attribute a prop is written as. */
let attributeName = (prop: string) =>
  switch prop {
  | "className" => "class"
  | "htmlFor" => "for"
  | "tabIndex" => "tabindex"
  | "readOnly" => "readonly"
  | "autoFocus" => "autofocus"
  | "colSpan" => "colspan"
  | "rowSpan" => "rowspan"
  | "minLength" => "minlength"
  | "popoverTarget" => "popovertarget"
  | "popoverTargetAction" => "popovertargetaction"
  | "autoComplete" => "autocomplete"
  | "inputMode" => "inputmode"
  | "maxLength" => "maxlength"
  | name => name
  }

/** Whether a prop's value is absent (`undefined` or `null`). */
let isNothing = (value: unknown) => Nullable.isNullable(toNullable(value))

/**
What an attribute prop's value is written as, or `None` to leave the attribute out: absent and
`false` leave it out, `true` is the empty string (a boolean attribute), anything else its string.
*/
let attributeValue = (value: unknown): option<string> =>
  if isNothing(value) || value === fromBool(false) {
    None
  } else if value === fromBool(true) {
    Some("")
  } else {
    Some(stringify(value))
  }

/**
A `style` key as CSS writes it: one with a `-` already is (`background-color`, `--custom`), and
camel case becomes kebab case (`backgroundColor` as `background-color`, `WebkitTransform` as
`-webkit-transform`, `msTransform` as `-ms-transform`).
*/
let cssName = (name: string) =>
  if name->String.includes("-") {
    name
  } else {
    let kebab = name->String.replaceRegExp(/[A-Z]/g, "-$&")->String.toLowerCase
    kebab->String.startsWith("ms-") ? "-" ++ kebab : kebab
  }
