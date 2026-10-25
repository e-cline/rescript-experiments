/***
Extraction: the stylesheets of the files whose top levels ran while recording.

```rescript
Extract.start()
// import the style files (the Vite plugin does, in a module runner of its own)
let sheets = Extract.finish()
```

One sheet per file, named by its sheet id (`SheetId`): its variables, on `:root`, and its globals in
the layer `weft.base` (unless given another), then its classes and keyframes in `weft.components`,
each layer's rules in the order the file declares them.
*/

type sheet = {
  /** The file's sheet id. */
  id: string,
  css: string,
  /** The other sheets its rules name (their variables or animations), each once. */
  dependencies: array<string>,
}

/** Starts recording the registrations of the files whose top levels run from now on. */
let start: unit => unit

/**
Stops recording, and gives the sheets of what was recorded, in the order each was first seen.
Throws for a definition that throws (saying which), and for a name registered twice.
*/
let finish: unit => array<sheet>

/** The sheets of some registrations, as `finish` makes them. */
let sheets: array<Css.Internal.registration> => array<sheet>

let baseLayer: string
let componentsLayer: string
