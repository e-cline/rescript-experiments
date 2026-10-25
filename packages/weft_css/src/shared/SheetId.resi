/***
Sheet ids: which stylesheet a class (or variable, or animation) is in, from its name alone.

Every name `ppx_weft` gives ends in its file's sheet id, `_w` and six base-36 digits
(`AddToCart-Styles-button_wk3f9a`), so the server can tell which sheets a page uses from the class
names it renders, with no table of classes, and the extraction which sheets a sheet's rules refer
to (another file's variables, say).
*/

/**
The sheet id of a file, from its id (`<package name>/<path from the package root>`, as entrypoints
are named): `w`, then a 32-bit FNV-1a hash of it, modulo 36⁶, in six base-36 digits. `ppx_weft`
computes the same.
*/
let ofFileId: string => string

/** The sheet id a name ends in, if it ends in one. */
let ofName: string => option<string>

/** The sheet ids of the names in a class list (`className`), each once, in order. */
let ofClassList: string => array<string>

/** Every sheet id a CSS text's names end in, each once, in order. */
let inText: string => array<string>
