/*** The data the server sends the client: types only, so both sides can share them. */

type comment = {id: string, author: string, text: string}

type note = {id: string, title: string, body: string, savedAt: string, likes: int}
