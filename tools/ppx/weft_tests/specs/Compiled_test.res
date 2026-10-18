/***
Assertions on the compiled output of the fixtures, for what phase 2 will build on. (The output is
committed, so any other change to it shows up in review, and CI fails if a build changes it.)
*/

open Vitest

let compiled = name =>
  NodeSupport.readFileSync(NodeSupport.join(NodeSupport.packageRoot, `fixtures/${name}.res.js`))

describe("the compiled fixtures", () => {
  test("a file's @@directive is its first line, as written", t => {
    let firstLine = compiled("Directive")->String.split("\n")->Array.get(0)
    t->expect(firstLine)->Expect.toBe(Some("'use canary'"))
  })

  test("a file-level component is exported as `make`, and nested ones by module name", t => {
    let js = compiled("Kinds")
    t->expect(js->String.includes("  make,\n"))->Expect.toBe(true)
    t->expect(js->String.includes("  Nested,\n"))->Expect.toBe(true)
  })

  test("a module named after a JavaScript global is exported as `$$<name>`", t => {
    t->expect(compiled("Kinds")->String.includes("  $$Error,\n"))->Expect.toBe(true)
  })
})
