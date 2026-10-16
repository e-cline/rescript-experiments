open Vitest

describe("Query", () => {
  let query = Query.fromString("?name=Ada&tag=a&tag=b&n=42&ratio=1.5&on=true&off=0&flag&blank=")

  test("get returns the first value, or None", t => {
    t->expect(query->Query.get("name"))->Expect.toEqual(Some("Ada"))
    t->expect(query->Query.get("tag"))->Expect.toEqual(Some("a"))
    t->expect(query->Query.get("missing"))->Expect.toEqual(None)
    t->expect(query->Query.get("blank"))->Expect.toEqual(Some(""))
  })

  test("getAll, has and getOr", t => {
    t->expect(query->Query.getAll("tag"))->Expect.toEqual(["a", "b"])
    t->expect(query->Query.getAll("missing"))->Expect.toEqual([])
    t->expect(query->Query.has("flag"))->Expect.toBe(true)
    t->expect(query->Query.has("missing"))->Expect.toBe(false)
    t->expect(query->Query.getOr("name", "world"))->Expect.toBe("Ada")
    t->expect(query->Query.getOr("missing", "world"))->Expect.toBe("world")
  })

  test("getInt accepts only integers", t => {
    t->expect(query->Query.getInt("n"))->Expect.toEqual(Some(42))
    t->expect(Query.fromString("n=-7")->Query.getInt("n"))->Expect.toEqual(Some(-7))
    t->expect(query->Query.getInt("ratio"))->Expect.toEqual(None)
    t->expect(query->Query.getInt("name"))->Expect.toEqual(None)
    t->expect(query->Query.getInt("blank"))->Expect.toEqual(None)
    t->expect(query->Query.getInt("missing"))->Expect.toEqual(None)
    t->expect(Query.fromString("n=12px")->Query.getInt("n"))->Expect.toEqual(None)
    t->expect(Query.fromString("n=1e3")->Query.getInt("n"))->Expect.toEqual(None)
    t->expect(Query.fromString("n=0x10")->Query.getInt("n"))->Expect.toEqual(None)
    t->expect(Query.fromString("n=%2012")->Query.getInt("n"))->Expect.toEqual(None)
    t->expect(Query.fromString("n=2147483647")->Query.getInt("n"))->Expect.toEqual(Some(2147483647))
    t->expect(Query.fromString("n=2147483648")->Query.getInt("n"))->Expect.toEqual(None)
  })

  test("getFloat accepts only finite numbers", t => {
    t->expect(query->Query.getFloat("ratio"))->Expect.toEqual(Some(1.5))
    t->expect(query->Query.getFloat("n"))->Expect.toEqual(Some(42.0))
    t->expect(Query.fromString("x=-1e3")->Query.getFloat("x"))->Expect.toEqual(Some(-1000.0))
    t->expect(query->Query.getFloat("blank"))->Expect.toEqual(None)
    t->expect(Query.fromString("x=1.5kg")->Query.getFloat("x"))->Expect.toEqual(None)
    t->expect(Query.fromString("x=1e999")->Query.getFloat("x"))->Expect.toEqual(None)
    t->expect(Query.fromString("x=Infinity")->Query.getFloat("x"))->Expect.toEqual(None)
    t->expect(Query.fromString("x=NaN")->Query.getFloat("x"))->Expect.toEqual(None)
  })

  test("getBool", t => {
    t->expect(query->Query.getBool("on"))->Expect.toEqual(Some(true))
    t->expect(query->Query.getBool("off"))->Expect.toEqual(Some(false))
    t->expect(query->Query.getBool("flag"))->Expect.toEqual(Some(true))
    t->expect(Query.fromString("x=TRUE")->Query.getBool("x"))->Expect.toEqual(Some(true))
    t->expect(query->Query.getBool("name"))->Expect.toEqual(None)
    t->expect(query->Query.getBool("missing"))->Expect.toEqual(None)
  })

  test("values are decoded", t => {
    let query = Query.fromString("q=a%20b+c%26d&%C3%A9=1")
    t->expect(query->Query.get("q"))->Expect.toEqual(Some("a b c&d"))
    t->expect(query->Query.get("é"))->Expect.toEqual(Some("1"))
  })

  test("toArray keeps every pair; toMap keeps each name's first value", t => {
    let query = Query.fromPairs([("a", "1"), ("b", "2"), ("a", "3")])
    t->expect(query->Query.toArray)->Expect.toEqual([("a", "1"), ("b", "2"), ("a", "3")])
    t->expect(query->Query.toMap)->Expect.toEqual(Map.fromArray([("a", "1"), ("b", "2")]))
    t->expect(query->Query.toString)->Expect.toBe("a=1&b=2&a=3")
  })

  test("names that are also properties of every object are ordinary names", t => {
    let query = Query.fromString("toString=1&__proto__=2&constructor=3&toString=4")
    t
    ->expect(query->Query.toMap->Map.entries->Iterator.toArray)
    ->Expect.toEqual([("toString", "1"), ("__proto__", "2"), ("constructor", "3")])
    t->expect(query->Query.get("toString"))->Expect.toEqual(Some("1"))

    // And aren't found when they weren't sent.
    let other = Query.fromString("a=1")
    t->expect(other->Query.toMap->Map.get("constructor"))->Expect.toEqual(None)
    t->expect(other->Query.get("constructor"))->Expect.toEqual(None)
    t->expect(other->Query.has("toString"))->Expect.toBe(false)
  })

  test("isEmpty", t => {
    t->expect(Query.fromString("")->Query.isEmpty)->Expect.toBe(true)
    t->expect(query->Query.isEmpty)->Expect.toBe(false)
  })
})
