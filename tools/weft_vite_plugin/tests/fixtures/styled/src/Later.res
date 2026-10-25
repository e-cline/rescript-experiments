/*** Loaded lazily (`Main` imports it dynamically), so its sheet goes with its own chunk. */
open WeftCss

let later = Css.class({fontStyle: Italic})

let view = () => <p className=later> {WeftDom.Jsx.string("later")} </p>
