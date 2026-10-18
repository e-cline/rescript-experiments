/***
A greeting component that explores three things at once: `@rescript/react`'s JSX authoring, CSS
Modules imported from a `.res` file, and a third-party ReScript library from npm (`rescript-webapi`,
providing `Webapi.Base64.btoa` -- an ordinary global `btoa`/`atob` binding, chosen because it needs
no DOM and so works the same under Vitest's default `node` test environment as in a real browser).
*/

/**
The shape of `Greeting.module.css`'s default export (its class names).

CSS Modules has no first-class ReScript syntax; this is the standard hand-written binding shape (see
rescript-lang.org's React styling docs): declare the shape of the default export, then bind to it
with `@module`. `vp pack` (via tsdown's built-in Lightning CSS integration -- see pack.md's "CSS
Bundling" section) processes the `.module.css` import the compiled `Greeting.res.jsx` makes of this
file the same way it would for a `.tsx` component that imported CSS Modules directly.
*/
type styles = {"greeting": string}
@module("./Greeting.module.css") external styles: styles = "default"

/**
Renders `Hello, <name>! (base64: <name, base64-encoded>)` in a `<div>` styled by the CSS Module's
`greeting` class.
*/
@genType @jsx.component
let make = (~name: string) => {
  let encoded = Webapi.Base64.btoa(name)
  <div className={styles["greeting"]}> {React.string(`Hello, ${name}! (base64: ${encoded})`)} </div>
}
