@@jsxConfig({version: 4, module_: "TestJsx"})

/***
Random keyed-list updates: each step renders a random selection and order of keys (with holes that
render nothing), then checks the output, that every surviving key kept its node, and that exactly
the added keys were created and the dropped ones removed.
*/

open Vitest

/** A seeded Lehmer PRNG (as in `res_signals`' fuzz test), so failures reproduce. */
module Random = {
  type t = ref<float>
  let make = (seed: float): t => ref(seed)
  let next = (state: t): float => {
    let product = state.contents *. 48271.0
    state := product -. 2147483647.0 *. Math.floor(product /. 2147483647.0)
    state.contents
  }
  let intBelow = (state: t, bound: int): int => mod(Float.toInt(next(state)), bound)
  let bool = (state: t) => intBelow(state, 2) == 0
}

let pool = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]

/** Keys after "e" render through a component, the rest as host elements: each key's type is fixed. */
let viaComponent = key => key > "e"

module Item = {
  @jsx.component
  let make = (~name: string) => <li id=name> {TestJsx.string(name)} </li>
}

let view = (slots: array<option<string>>) =>
  <ul id="list">
    {slots
    ->Array.map(slot =>
      switch slot {
      | Some(key) if viaComponent(key) => <Item key name=key />
      | Some(key) => <li key id=key> {TestJsx.string(key)} </li>
      | None => TestJsx.null
      }
    )
    ->TestJsx.array}
  </ul>

let expected = (keys: array<string>) =>
  `<ul id="list">${keys->Array.map(key => `<li id="${key}">${key}</li>`)->Array.join("")}</ul>`

/** A random selection of keys in a random order, with random holes. */
let randomSlots = (random: Random.t): array<option<string>> => {
  let keys = pool->Array.filter(_ => Random.bool(random))
  // Fisher-Yates.
  for i in Array.length(keys) - 1 downto 1 {
    let j = Random.intBelow(random, i + 1)
    let tmp = keys->Array.getUnsafe(i)
    keys->Array.setUnsafe(i, keys->Array.getUnsafe(j))
    keys->Array.setUnsafe(j, tmp)
  }
  keys->Array.flatMap(key => Random.intBelow(random, 4) == 0 ? [None, Some(key)] : [Some(key)])
}

let countMatching = (ops: array<string>, prefix: string) =>
  ops->Array.filter(op => op->String.startsWith(prefix))->Array.length

describe("Fuzz: keyed lists", () => {
  [1.0, 7.0, 42.0, 1234.0]->Array.forEach(seed =>
    test(
      `seed ${Float.toString(seed)}`,
      t => {
        let random = Random.make(seed)
        let renderer = TestRenderer.create()
        let uids: dict<int> = Dict.make()
        let previous = ref([])
        for _ in 1 to 200 {
          let slots = randomSlots(random)
          let keys = slots->Array.filterMap(slot => slot)
          TestRenderer.clearOps(renderer)
          TestRenderer.render(renderer, view(slots))
          let ops = TestRenderer.ops(renderer)

          t->expect(TestRenderer.toString(renderer))->Expect.toBe(expected(keys))

          let added = keys->Array.filter(key => !(previous.contents->Array.includes(key)))
          let removed = previous.contents->Array.filter(key => !(keys->Array.includes(key)))
          t->expect(countMatching(ops, "create li"))->Expect.toBe(Array.length(added))
          t->expect(countMatching(ops, "remove li"))->Expect.toBe(Array.length(removed))

          keys->Array.forEach(
            key => {
              let uid = switch TestRenderer.findById(renderer, key) {
              | Some(node) => TestRenderer.uid(node)
              | None => -1
              }
              if previous.contents->Array.includes(key) {
                t->expect((key, uid))->Expect.toEqual((key, uids->Dict.getUnsafe(key)))
              }
              uids->Dict.set(key, uid)
            },
          )
          previous := keys
        }
      },
    )
  )
})
