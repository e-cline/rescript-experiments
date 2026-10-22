@@weft.server

/***
A server-only file without server components (an RPC's handlers, a database module): `@@weft.server`
marks it `'use weft server'`, so the client can't import it.
*/

let save = WeftServer.RpcServer.handler(Rpcs.save, async (_, ~http as _) => Ok())
