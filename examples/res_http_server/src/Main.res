/***
Starts the server on Node. Run with `vp run start` (or, after a build,
`node src/Main.res.js`).

- `PORT` is the port to listen on, 3000 by default.
- `HOST` is the address to listen on, `127.0.0.1` by default: this machine
  only. Set it to `0.0.0.0` to accept connections from other machines.
*/

@val @scope(("process", "env")) external portEnv: option<string> = "PORT"
@val @scope(("process", "env")) external hostEnv: option<string> = "HOST"

let port = portEnv->Option.flatMap(Int.fromString(_))->Option.getOr(3000)

let _server =
  Routes.make(~log=Console.log)->ResServer.NodeServer.serve(
    ~port,
    ~hostname=?hostEnv,
    ~onListen=address =>
      Console.log(`Listening on http://${address.address}:${address.port->Int.toString}`),
  )
