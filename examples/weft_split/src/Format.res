/***
A module two entrypoints (`Fancy` and `Plain`) use: the build puts it in a chunk of its own that
both import, rather than a copy in each.
*/

let fancy = text => `~ ${text} ~`

let plain = text => String.trim(text)
