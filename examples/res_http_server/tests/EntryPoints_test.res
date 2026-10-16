/***
The two ways of starting the server, `src/Main.res` and `serve.mjs`, run as
they would be from the command line: each in a process of its own, on a port
the system picks, and called over HTTP.
*/

open Vitest

type stream
type child = {stdout: stream, stderr: stream}

type spawnOptions = {env: dict<string>}

@module("node:child_process")
external spawn: (string, array<string>, spawnOptions) => child = "spawn"
@send external onData: (stream, @as("data") _, 'chunk => unit) => unit = "on"
@send external onExit: (child, @as("exit") _, unit => unit) => unit = "on"
@send external kill: child => bool = "kill"
@send external toString: 'chunk => string = "toString"
@val @scope("process") external execPath: string = "execPath"
@val @scope("process") external env: dict<string> = "env"

/**
Runs `script` with Node until it says where it's listening, gives that to `f`, and stops it.
*/
let withServer = async (script: string, f: string => promise<'result>): 'result => {
  let environment = env->Dict.copy
  // Any free port, so that this doesn't depend on 3000 being available.
  environment->Dict.set("PORT", "0")
  environment->Dict.delete("HOST")
  let child = spawn(execPath, [script], {env: environment})
  let exited = Promise.make((resolve, _reject) => child->onExit(() => resolve()))
  let output = ref("")
  let listening = Promise.make((resolve, reject) => {
    let read = chunk => {
      output := output.contents ++ chunk->toString
      switch /Listening on (http:\/\/[0-9.]+:[0-9]+)/->RegExp.exec(output.contents) {
      | Some(result) =>
        result->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)->Option.forEach(resolve)
      | None => ()
      }
    }
    child.stdout->onData(read)
    child.stderr->onData(read)
    exited
    ->Promise.thenResolve(() =>
      reject(
        JsError.make(`${script} exited before listening:\n${output.contents}`)->JsError.toJsExn,
      )
    )
    ->ignore
  })
  let result = try Ok(await f(await listening)) catch {
  | error => Error(error)
  }
  child->kill->ignore
  await exited
  switch result {
  | Ok(value) => value
  | Error(error) => throw(error)
  }
}

let exercise = async (base: string): (string, int, array<string>) => {
  let hello = await (await Fetch.fetch(`${base}/hello/Ada`))->Response.text
  let missing = (await Fetch.fetch(`${base}/nope`)).status
  let events = await (await Fetch.fetch(`${base}/events?count=2&intervalMs=1`))->Response.text
  (
    hello,
    missing,
    events
    ->String.trim
    ->String.split("\n")
    ->Array.map(line => line->String.slice(~start=0, ~end=10)),
  )
}

let expected = ("Hello, Ada!\n", 404, [`{"index":0`, `{"index":1`])

describe("the server's entry points", () => {
  testAsync("src/Main.res starts the server, on this machine only", async t => {
    let (base, result) = await withServer(
      "src/Main.res.js",
      async base => (base, await exercise(base)),
    )
    t->expect(result)->Expect.toEqual(expected)
    t->expect(base)->Expect.String.toMatch(/^http:\/\/127\.0\.0\.1:\d+$/)
  })

  testAsync("serve.mjs starts the same server from JavaScript", async t => {
    let (base, result) = await withServer("serve.mjs", async base => (base, await exercise(base)))
    t->expect(result)->Expect.toEqual(expected)
    t->expect(base)->Expect.String.toMatch(/^http:\/\/127\.0\.0\.1:\d+$/)
  })
})
