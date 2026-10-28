/***
The size guide: a table, loaded only when the shopper opens it (`ProductOffer` imports it with
`import()`), so it's in a chunk of its own. Its module waits for its stylesheet before it runs, so the
table never shows without it.
*/

open WeftCss

module Styles = {
  let guide = Css.class({
    borderCollapse: "collapse",
    fontSize: Rem(0.875),
    selectors: [
      ("th, td", Css.style({padding: Pair(Px(4), Px(10)), borderBottom: Theme.hairline()})),
      ("th", Css.style({textAlign: Left, color: Var(Theme.muted), fontWeight: 600})),
    ],
  })
}

let sizes = [("7", "24.5", "40"), ("8", "25.5", "41"), ("9", "26.5", "42.5"), ("10", "27.5", "44")]

let view = () =>
  <table dataId="size-guide" className=Styles.guide>
    <thead>
      <tr>
        <th> {WeftDom.Jsx.string("US")} </th>
        <th> {WeftDom.Jsx.string("Foot (cm)")} </th>
        <th> {WeftDom.Jsx.string("EU")} </th>
      </tr>
    </thead>
    <tbody>
      {sizes
      ->Array.map(((us, cm, eu)) =>
        <tr key=us>
          <td> {WeftDom.Jsx.string(us)} </td>
          <td> {WeftDom.Jsx.string(cm)} </td>
          <td> {WeftDom.Jsx.string(eu)} </td>
        </tr>
      )
      ->WeftDom.Jsx.array}
    </tbody>
  </table>
