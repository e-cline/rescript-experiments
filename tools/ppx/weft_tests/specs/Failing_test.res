/***
Files that mustn't compile, each with the error it should give, compiled with `bsc` directly:

- `errors/`, through the PPX: each misuse of `@weft.component`.
- `canaries/`, without it: compiler behaviours the PPX's design depends on (see "What was verified
  before writing this" in docs/weft_server_components_plan.md). If a ReScript upgrade changes one,
  its test fails here, by name.

Each `<Name>.res.in` (`.in`, so neither the ReScript build nor the formatter picks it up) is
compiled from a fresh temporary directory, so nothing is written in this package. The error is
compared with `<Name>.expected` after removing colours and the temporary path; run the tests with
`-u` to rewrite the `.expected` files after an intended change.
*/

open Vitest

@send
external toMatchFileSnapshot: (Vitest_Types.expected<string>, string) => promise<unit> =
  "toMatchFileSnapshot"

let bsc = NodeSupport.join(NodeSupport.packageRoot, "node_modules/.bin/bsc")
let ppx = NodeSupport.join(NodeSupport.packageRoot, "node_modules/@e-cline/ppx_weft/ppx")

let ansi = /\x1b\[[0-9;]*m/g

/** Compiles `<dir>/<name>.in` as `<name>`, returning the exit status and what bsc printed. */
let compile = (~dir, ~withPpx, name) => {
  let source = NodeSupport.readFileSync(
    NodeSupport.join(NodeSupport.packageRoot, `${dir}/${name}.in`),
  )
  let workDir = NodeSupport.mkdtempSync(NodeSupport.join(NodeSupport.tmpdir(), "ppx-weft-"))
  let file = NodeSupport.join(workDir, name)
  NodeSupport.writeFileSync(file, source)
  let ppxArgs = withPpx ? ["-ppx", ppx] : []
  let result = NodeSupport.spawnSync(
    bsc,
    [...ppxArgs, "-bs-jsx", "4", file],
    // A compile that hangs would block the test runner too (this call is synchronous).
    {cwd: workDir, encoding: "utf8", timeout: 60_000},
  )
  let output =
    (result.stdout ++ result.stderr)
    ->String.replaceRegExp(ansi, "")
    ->String.replaceAll(file, name)
  (result.status->Nullable.toOption, output)
}

let suite = (~dir, ~withPpx) =>
  NodeSupport.readdirSync(NodeSupport.join(NodeSupport.packageRoot, dir))
  ->Array.filter(file => file->String.endsWith(".in"))
  ->Array.forEach(file => {
    let name = file->String.slice(~start=0, ~end=-3)
    testAsync(name, async t => {
      let (status, output) = compile(~dir, ~withPpx, name)
      t->expect(status != Some(0))->Expect.toBe(true)
      await t
      ->expect(output)
      ->toMatchFileSnapshot(
        `../${dir}/${name->String.replace(".resi", "")->String.replace(".res", "")}.expected`,
      )
    })
  })

describe("misuses of @weft.component", () => suite(~dir="errors", ~withPpx=true))
describe("compiler canaries", () => suite(~dir="canaries", ~withPpx=false))
