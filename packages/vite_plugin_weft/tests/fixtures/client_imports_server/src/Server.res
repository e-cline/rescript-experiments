/*** The server entry: it doesn't matter what it does, since the client's build fails first. */

let default = async (_request: Fetch.request) =>
  Fetch.makeResponse("ok", {headers: dict{"content-type": "text/plain"}})
