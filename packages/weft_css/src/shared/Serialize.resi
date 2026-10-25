/***
CSS text from `Css.t`s: what extraction writes into a file's stylesheet. Readable rather than small
(two-space indents, a declaration a line): the Vite plugin's CSS pipeline minifies it.
*/

/** `css`'s own declarations, `property: value`, in the order `Css.t` declares its fields. */
let declarations: Css.t => array<string>

/**
The rules for `css` at `selector`: its declarations, then its nested blocks, each a rule of its own
(at-rules wrapping theirs). Empty rules are left out.
*/
let rules: (~selector: string, Css.t) => string

/**
A nested selector made from `parent` and `child`, both possibly lists: each `&` in `child` is the
parent; a child without one is a descendant (`child` `li` under `.a` is `.a li`).
*/
let nest: (~parent: string, string) => string

/** `@keyframes name { ... }`. */
let keyframes: (~name: string, array<Css.frame>) => string

/** `--name: value;` declarations on `:root`. */
let root: array<(string, string)> => string

/** `text` in `@layer name { ... }`, indented. */
let layer: (~name: string, string) => string
