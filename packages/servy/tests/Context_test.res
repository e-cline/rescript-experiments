open Vitest

type user = {name: string, admin: bool}

let userKey: Context.Key.t<user> = Context.Key.make(~name="user")
let countKey: Context.Key.t<int> = Context.Key.make(~name="count")
let noteKey: Context.Key.t<option<string>> = Context.Key.make(~name="note")

describe("Context", () => {
  test("a key reads back what was set under it, with its type", t => {
    let context =
      Context.empty->Context.set(userKey, {name: "Ada", admin: true})->Context.set(countKey, 2)
    t->expect(context->Context.get(userKey))->Expect.toEqual(Some({name: "Ada", admin: true}))
    t
    ->expect(context->Context.get(countKey)->Option.map(count => count + 1))
    ->Expect.toEqual(Some(3))
  })

  test("a key that hasn't been set is None", t => {
    t->expect(Context.empty->Context.get(countKey))->Expect.toEqual(None)
    t->expect(Context.empty->Context.set(countKey, 1)->Context.get(userKey))->Expect.toEqual(None)
  })

  test("set replaces the value, in a new context", t => {
    let one = Context.empty->Context.set(countKey, 1)
    let two = one->Context.set(countKey, 2)
    t->expect(two->Context.get(countKey))->Expect.toEqual(Some(2))
    t->expect(one->Context.get(countKey))->Expect.toEqual(Some(1))
    t->expect(Context.empty->Context.get(countKey))->Expect.toEqual(None)
  })

  test("two keys are different, even with the same name and type", t => {
    let first: Context.Key.t<int> = Context.Key.make(~name="same")
    let second: Context.Key.t<int> = Context.Key.make(~name="same")
    let context = Context.empty->Context.set(first, 1)
    t->expect(context->Context.get(first))->Expect.toEqual(Some(1))
    t->expect(context->Context.get(second))->Expect.toEqual(None)
    let context = context->Context.set(second, 2)
    t->expect(context->Context.get(first))->Expect.toEqual(Some(1))
    t->expect(context->Context.get(second))->Expect.toEqual(Some(2))
  })

  test("a value that is itself None is set, not missing", t => {
    t->expect(Context.empty->Context.get(noteKey))->Expect.toEqual(None)
    t
    ->expect(Context.empty->Context.set(noteKey, None)->Context.get(noteKey))
    ->Expect.toEqual(Some(None))
    t
    ->expect(Context.empty->Context.set(noteKey, Some("hi"))->Context.get(noteKey))
    ->Expect.toEqual(Some(Some("hi")))
  })

  test("name", t => {
    t->expect(userKey->Context.Key.name)->Expect.toBe("user")
  })
})
