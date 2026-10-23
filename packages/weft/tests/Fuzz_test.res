@@jsxConfig({version: 4, module_: "TestJsx"})

/***
Random keyed-list updates: each step renders a random selection and order of keys (with holes that
render nothing) and a random theme, then checks the output, that every surviving key kept its node,
that exactly the added keys were created and the dropped ones removed, and that every mounted
component's effects are mounted exactly once.

Half the keys render through a memoized component that reads the theme from context, so a theme
change only reaches them through context propagation.
*/

open Vitest

/** A seeded Lehmer PRNG (as in `signals`' fuzz test), so failures reproduce. */
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

module Theme = {
  let context = Context.make("none")
  module Provider = {
    let make = Context.provider(context)
  }
}

/** How many `Item`s have their effect (and layout effect) mounted. */
let liveEffects = ref(0)
let liveLayoutEffects = ref(0)

module Item = {
  @jsx.component
  let make = Memo.memo((~name: string) => {
    let theme = Hooks.useContext(Theme.context)
    Hooks.useEffect0(() => {
      liveEffects := liveEffects.contents + 1
      Some(() => liveEffects := liveEffects.contents - 1)
    })
    Hooks.useLayoutEffect0(() => {
      liveLayoutEffects := liveLayoutEffects.contents + 1
      Some(() => liveLayoutEffects := liveLayoutEffects.contents - 1)
    })
    <li id=name title=theme> {TestJsx.string(name)} </li>
  })
}

module List = {
  @jsx.component
  let make = Memo.memo((~slots: array<option<string>>, ~theme: string) =>
    <ul id="list">
      {slots
      ->Array.map(slot =>
        switch slot {
        | Some(key) if viaComponent(key) => <Item key name=key />
        | Some(key) => <li key id=key title=theme> {TestJsx.string(key)} </li>
        | None => TestJsx.null
        }
      )
      ->TestJsx.array}
    </ul>
  )
}

let view = (slots: array<option<string>>, ~theme: string) =>
  <Theme.Provider value=theme>
    <List slots theme />
  </Theme.Provider>

let expected = (keys: array<string>, ~theme: string) =>
  `<ul id="list">${keys
    ->Array.map(key => `<li id="${key}" title="${theme}">${key}</li>`)
    ->Array.join("")}</ul>`

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
        liveEffects := 0
        liveLayoutEffects := 0
        for _ in 1 to 200 {
          let slots = randomSlots(random)
          let keys = slots->Array.filterMap(slot => slot)
          let theme = Random.bool(random) ? "dark" : "light"
          TestRenderer.clearOps(renderer)
          TestRenderer.render(renderer, view(slots, ~theme))
          let ops = TestRenderer.ops(renderer)

          t->expect(TestRenderer.toString(renderer))->Expect.toBe(expected(keys, ~theme))
          let components = keys->Array.filter(viaComponent)->Array.length
          t
          ->expect((liveEffects.contents, liveLayoutEffects.contents))
          ->Expect.toEqual((components, components))

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
        TestRenderer.unmount(renderer)
        t->expect((liveEffects.contents, liveLayoutEffects.contents))->Expect.toEqual((0, 0))
      },
    )
  )
})

/***
Random interleavings of sync, default and transition updates (each appending a token), with
transition renders run a slice at a time. Whatever is on screen must be the updates in the order they
were made, possibly missing some transitions; once everything is flushed it must be all of them.
*/

let setTokens: ref<(array<string> => array<string>) => unit> = ref(_ => ())

module Tokens = {
  @jsx.component
  let make = () => {
    let (tokens, set) = Hooks.useState(() => [])
    setTokens := set
    <>
      {tokens
      ->Array.map(token => {
        // Slow enough that a transition's render spans several slices.
        TestScheduler.advanceTime(1.0)
        <b key=token> {TestJsx.string(token)} </b>
      })
      ->TestJsx.array}
    </>
  }
}

let shown = renderer =>
  TestRenderer.toString(renderer)
  ->String.replaceAll("<b>", "")
  ->String.split("</b>")
  ->Array.filter(token => token != "")

/** Whether `part` is `whole` with some elements left out, keeping the order. */
let isSubsequence = (part: array<string>, whole: array<string>) => {
  let next = ref(0)
  whole->Array.forEach(token =>
    if next.contents < Array.length(part) && part->Array.getUnsafe(next.contents) == token {
      next := next.contents + 1
    }
  )
  next.contents == Array.length(part)
}

describe("Fuzz: update order across lanes", () => {
  [3.0, 11.0, 99.0, 2024.0]->Array.forEach(seed =>
    test(
      `seed ${Float.toString(seed)}`,
      t => {
        let random = Random.make(seed)
        let renderer = TestRenderer.create()
        TestRenderer.render(renderer, <Tokens />)
        let all = []
        let urgent = []
        let append = token => {
          all->Array.push(token)
          setTokens.contents(tokens => Array.concat(tokens, [token]))
        }
        for step in 1 to 150 {
          switch Random.intBelow(random, 5) {
          | 0 => Transition.start(() => append(`t${Int.toString(step)}`))
          | 1 =>
            urgent->Array.push(`s${Int.toString(step)}`)
            TestRenderer.flushSync(() => append(`s${Int.toString(step)}`))
          | 2 =>
            // A default update: rendered by the next flush.
            urgent->Array.push(`d${Int.toString(step)}`)
            append(`d${Int.toString(step)}`)
          | 3 => TestScheduler.flushTask()->ignore
          | _ => TestRenderer.flushSync(() => ())
          }
          let screen = shown(renderer)
          t->expect((step, isSubsequence(screen, all)))->Expect.toEqual((step, true))
          if Random.intBelow(random, 4) == 0 {
            // After a flush, every urgent update so far is on screen.
            TestRenderer.flushSync(() => ())
            let screen = shown(renderer)
            t
            ->expect((step, urgent->Array.filter(token => !(screen->Array.includes(token)))))
            ->Expect.toEqual((step, []))
          }
        }
        TestRenderer.act(() => ())
        t->expect(shown(renderer))->Expect.toEqual(all)
      },
    )
  )
})
