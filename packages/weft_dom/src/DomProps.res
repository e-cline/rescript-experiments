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
  @as("data-testid") dataTestId?: string,
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
  htmlFor?: string,
  min?: string,
  max?: string,
  step?: string,
  rows?: int,
  cols?: int,
  colSpan?: int,
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
  // The element itself, from commit until removal.
  ref?: WeftCore.Ref.t<Nullable.t<Dom.element>>,
  children?: WeftCore.Element.t,
}
