@@directive("'use canary'")

/***
A compiler canary for phase 2's file markers: `@@directive` writes its string as the compiled file's
first line exactly as given, so a JavaScript directive needs its own quotes.
*/

let value = 1
