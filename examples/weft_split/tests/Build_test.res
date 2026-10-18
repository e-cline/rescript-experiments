/***
The build, with the real compiler and PPX output: the app built with its own config, checked
through the client's manifest and files, and the built server's payloads decoded with the built
chunks. `BuildSupport.mjs` does the building and reading.
*/

open Vitest

type chunk = {file: string, imports?: array<string>, isEntry?: bool, isDynamicEntry?: bool}
type build

@module("./BuildSupport.mjs") external build: unit => promise<build> = "build"
@module("./BuildSupport.mjs") external remove: build => unit = "remove"
@module("./BuildSupport.mjs") external chunk: (build, string) => chunk = "chunk"
@module("./BuildSupport.mjs") external manifestKeys: build => array<string> = "manifestKeys"
@module("./BuildSupport.mjs") external entries: build => array<string> = "entries"
@module("./BuildSupport.mjs") external code: (build, string) => string = "code"
@module("./BuildSupport.mjs")
external clientFilesContaining: (build, string) => array<string> = "clientFilesContaining"
@module("./BuildSupport.mjs") external serverCode: build => string = "serverCode"
@module("./BuildSupport.mjs") external page: (build, string) => promise<string> = "page"
@module("./BuildSupport.mjs")
external loadedFor: (build, string) => promise<array<string>> = "loadedFor"

let built = ref(None)
beforeAllAsync(~timeout=60_000, async () => built := Some(await build()))
afterAll(() => built.contents->Option.forEach(remove))
let built = () => built.contents->Option.getOrThrow

let source = name => `src/${name}.res.js`
let entrypointFiles = ["Chart", "Counter", "Fancy", "Outer", "Plain", "Widgets"]->Array.map(source)
let imports = key => chunk(built(), key).imports->Option.getOr([])

describe("the client build", () => {
  test("has the bootstrap as its one entry, and each entrypoint file as a chunk of its own", t => {
    t->expect(entries(built()))->Expect.toEqual([source("Client")])
    t
    ->expect(entrypointFiles->Array.map(key => chunk(built(), key).isDynamicEntry))
    ->Expect.toEqual(entrypointFiles->Array.map(_ => Some(true)))
    let files = entrypointFiles->Array.map(key => chunk(built(), key).file)
    t->expect(Set.fromArray(files)->Set.size)->Expect.toBe(Array.length(entrypointFiles))
  })

  test("puts the module two entrypoints share in a chunk both import, and in neither's", t => {
    let shared =
      imports(source("Fancy"))->Array.filter(key => imports(source("Plain"))->Array.includes(key))
    let format = shared->Array.filter(key => code(built(), key)->String.includes("function fancy("))
    t->expect(Array.length(format))->Expect.toBe(1)
    t
    ->expect(code(built(), source("Fancy"))->String.includes("function fancy("))
    ->Expect.toBe(false)
    t
    ->expect(code(built(), source("Plain"))->String.includes("function plain("))
    ->Expect.toBe(false)
  })

  test("has an entrypoint rendering another import the other's chunk", t => {
    t->expect(imports(source("Outer"))->Array.includes(source("Counter")))->Expect.toBe(true)
  })

  test("keeps the large module in the chunk of the one entrypoint using it", t => {
    t
    ->expect(clientFilesContaining(built(), "WEFT_SPLIT_CLIENT_SENTINEL"))
    ->Expect.toEqual([chunk(built(), source("Chart")).file])
  })

  test("has none of the server, and no directives", t => {
    t->expect(clientFilesContaining(built(), "WEFT_SPLIT_SERVER_SENTINEL"))->Expect.toEqual([])
    t->expect(clientFilesContaining(built(), "use weft"))->Expect.toEqual([])
    t
    ->expect(
      manifestKeys(built())->Array.filter(
        key => ["Pages", "Secrets", "Server"]->Array.some(name => key == source(name)),
      ),
    )
    ->Expect.toEqual([])
  })

  test("exports the modules the ids walk through, `Error` as `$$Error`", t => {
    let widgets = code(built(), source("Widgets"))
    t->expect(widgets->String.includes("$$Error"))->Expect.toBe(true)
    t->expect(widgets->String.includes("Toggle"))->Expect.toBe(true)
  })
})

describe("the server build", () => {
  testAsync("answers a page with the shell, loading the built bootstrap", async t => {
    let html = await page(built(), "/")
    let script = `<script type="module" src="/${chunk(built(), source("Client")).file}"></script>`
    t->expect(html->String.includes(script))->Expect.toBe(true)
    t->expect(html->String.includes(`<div id="root"></div>`))->Expect.toBe(true)
  })

  test("has the server code, without its directives", t => {
    t->expect(serverCode(built())->String.includes("WEFT_SPLIT_SERVER_SENTINEL"))->Expect.toBe(true)
    t->expect(serverCode(built())->String.includes("use weft"))->Expect.toBe(false)
  })

  testAsync("answers `/` with a payload using every entrypoint file but the chart's", async t => {
    t
    ->expect(await loadedFor(built(), "/"))
    ->Expect.toEqual(entrypointFiles->Array.filter(key => key != source("Chart")))
  })

  testAsync("answers `/other` with a payload using the chart's and the counter's only", async t => {
    t
    ->expect(await loadedFor(built(), "/other"))
    ->Expect.toEqual([source("Chart"), source("Counter")])
  })
})
