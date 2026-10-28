/***
A client module with styles that `Likes` loads only through `import()`, in a chunk of its own: the
`import()` resolves once its sheet (which uses `Theme`'s variable) has loaded too.
*/
open WeftCss

let popover = Css.class({padding: Px(8), color: Var(Theme.ink)})

let view = () => <div className=popover> {WeftDom.Jsx.string("more")} </div>
