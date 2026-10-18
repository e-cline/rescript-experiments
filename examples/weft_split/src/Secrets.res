/***
A server-only module: only server components use it, so nothing in it may reach the client build.
The build test looks for `sentinel` in the client's files, and must not find it.
*/

let sentinel = "WEFT_SPLIT_SERVER_SENTINEL"

/** What the home page says, as if read from somewhere only the server can reach. */
let motto = async () => `Kept on the server: ${sentinel}`
