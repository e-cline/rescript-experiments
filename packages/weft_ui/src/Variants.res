/*** The variants components share. */

/** A step on the space scale (`Tokens.spaceXs` ... `Tokens.spaceXxl`). */
type space = [#none | #xs | #sm | #md | #lg | #xl | #xxl]

/** A heading's level: its element. */
type level = [#h1 | #h2 | #h3 | #h4 | #h5 | #h6]

/** A colour's meaning. */
type tone = [#neutral | #accent | #success | #warning | #danger]

/** A control's size. */
type size = [#sm | #md | #lg]

/** Where things sit along an axis. */
type align = [#start | #center | #end | #stretch | #baseline]

type orientation = [#horizontal | #vertical]

external levelTag: level => string = "%identity"
external orientationName: orientation => string = "%identity"
