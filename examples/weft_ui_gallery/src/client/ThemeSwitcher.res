/***
The header's theme switcher: weft_ui's defaults, or a demo app's palette, as tokens on the outermost
element. Picking one puts its class there at once, and keeps it in a cookie, so the server renders
the next page (navigated to or reloaded) in it.
*/

module Ui = WeftUi

/** Puts `theme` on the page's outermost element, and keeps it in the cookie. */
let apply: (string, string, string) => unit = %raw(`(theme, className, cookieName) => {
  document.querySelector('[data-id=gallery]')?.setAttribute('class', className);
  document.cookie = cookieName + '=' + theme + '; path=/; max-age=31536000; samesite=lax';
}`)

@weft.component({kind: Entrypoint})
let make = (~current: string) => {
  let (theme, setTheme) = Weft.Hooks.useState(() => current)
  let choose = values =>
    switch values[0] {
    | Some(picked) =>
      setTheme(_ => picked)
      apply(picked, Theme.rootClass(picked), Theme.cookieName)
    | None => ()
    }
  <Ui.ToggleGroup.Root
    label="Theme" value=[theme] onValueChange=choose size=#sm variant=#ghost dataId="theme"
  >
    {Theme.themes
    ->Array.map(((name, title)) =>
      <Ui.ToggleGroup.Item key=name value=name dataId={`theme-${name}`}>
        {WeftDom.Jsx.string(title)}
      </Ui.ToggleGroup.Item>
    )
    ->WeftDom.Jsx.array}
  </Ui.ToggleGroup.Root>
}
