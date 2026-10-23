@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
Refetching, fuzzed. Each seed generates a sequence of random trees of host elements, text, Suspense
boundaries, server components (sync, or async with random delays, keyed or not) and stateful
entrypoints (with element children). The trees go through the server and the client, in random
chunks, each rendered over the last in a transition, with every counter bumped in between.

The oracle is the reconciler itself: the same trees, with the server components evaluated in place
(a keyed one's output in a fragment with its key, as the renderer writes it), rendered directly.
After every step the screens must be identical (counts included, so state was kept exactly where
the direct render kept it), and the same DOM nodes must have been kept.
*/

open Vitest
open Support

/** A seeded Lehmer PRNG (as in `weft`'s fuzz test), so failures reproduce. */
module Random = {
  type t = ref<float>
  let make = (seed: float): t => ref(seed)
  let next = (state: t): float => {
    let product = state.contents *. 48271.0
    state := product -. 2147483647.0 *. Math.floor(product /. 2147483647.0)
    state.contents
  }
  let intBelow = (state: t, bound: int): int => mod(Float.toInt(next(state)), bound)
  let pick = (state: t, items: array<'a>): 'a =>
    items->Array.getUnsafe(intBelow(state, Array.length(items)))
}

type rec spec =
  | Host(string, option<string>, array<spec>)
  | Text(string)
  | Server(option<string>, int, spec)
  | Entry(option<string>, string, option<spec>)
  | Boundary(option<string>, spec)

/** A server component: its child, after `delay` macrotasks (0: synchronously). */
module FuzzServer = {
  @jsx.component
  let make = (~delay: int, ~child: Weft.Element.t) =>
    delay == 0
      ? child
      : Weft.Lazy.fromPromise(
          (
            async () => {
              for _ in 1 to delay {
                await Testing.tick()
              }
              child
            }
          )(),
        )
}

let tags = ["div", "p", "ul"]
let keys = ["k1", "k2", "k3", "k4"]

/** A random tree, depth at most `depth`, taking entrypoint labels from `labels` (each used once). */
let rec generate = (random, ~depth, ~labels: array<string>, ~key) =>
  switch Random.intBelow(random, depth <= 0 ? 2 : 6) {
  | 0 => Text(Random.pick(random, ["x", "y", "z"]))
  | 1 =>
    switch labels->Array.pop {
    | Some(label) =>
      let children =
        Random.intBelow(random, 3) == 0 && depth > 0
          ? Some(generate(random, ~depth=depth - 1, ~labels, ~key=None))
          : None
      Entry(key, label, children)
    | None => Text("no label left")
    }
  | 2 | 3 =>
    let count = Random.intBelow(random, 4)
    // Children keyed or not, at random; keys unique among siblings.
    let keyed = Random.intBelow(random, 2) == 0
    let available = keys->Array.copy
    let children = Array.fromInitializer(~length=count, _ => {
      let key = if keyed && Array.length(available) > 0 {
        let index = Random.intBelow(random, Array.length(available))
        let picked = available->Array.getUnsafe(index)
        available->Array.splice(~start=index, ~remove=1, ~insert=[])
        Some(picked)
      } else {
        None
      }
      generate(random, ~depth=depth - 1, ~labels, ~key)
    })
    Host(Random.pick(random, tags), key, children)
  | 4 =>
    Server(key, Random.intBelow(random, 3), generate(random, ~depth=depth - 1, ~labels, ~key=None))
  | _ => Boundary(key, generate(random, ~depth=depth - 1, ~labels, ~key=None))
  }

type hostProps = Weft.TestJsx.Elements.props

/** `spec` as elements: with server components (`~server`), or evaluated in place (the oracle). */
let rec toElement = (spec, ~server: bool): Weft.Element.t =>
  switch spec {
  | Text(value) => text(value)
  | Host(tag, key, children) =>
    let props: hostProps = {
      children: TestJsx.array(children->Array.map(child => toElement(child, ~server))),
    }
    Weft.JsxCore.hostJsxsKeyed(tag, props, ~key?, ())
  | Entry(key, label, children) =>
    Weft.JsxCore.jsxKeyed(
      Counter.make,
      {label, children: ?(children->Option.map(child => toElement(child, ~server)))},
      ~key?,
      (),
    )
  | Boundary(key, child) =>
    Weft.JsxCore.jsxKeyed(
      Weft.Suspense.make,
      {fallback: loading, children: toElement(child, ~server)},
      ~key?,
      (),
    )
  | Server(key, delay, child) =>
    let child = toElement(child, ~server)
    switch (server, key) {
    | (true, _) => Weft.JsxCore.jsxKeyed(FuzzServer.make, {delay, child}, ~key?, ())
    | (false, Some(key)) =>
      Weft.JsxCore.jsxKeyed(Weft.JsxCore.Fragment.make, {children: child}, ~key, ())
    | (false, None) => child
    }
  }

let rec labelsOf = spec =>
  switch spec {
  | Text(_) => []
  | Host(_, _, children) => children->Array.flatMap(labelsOf)
  | Entry(_, label, children) => [label, ...children->Option.mapOr([], labelsOf)]
  | Boundary(_, child) | Server(_, _, child) => labelsOf(child)
  }

let settleFully = async () =>
  for _ in 1 to 3 {
    await settle()
  }

/** What one step left on screen, and which entrypoints' nodes it kept from the step before. */
type step = {screen: string, kept: array<(string, bool)>}

let uidOf = (renderer, label) =>
  TestRenderer.findById(renderer, label)->Option.map(TestRenderer.uid)

/** Renders `specs` in turn with `render`, bumping every counter between steps. */
let run = async (specs: array<spec>, ~render) => {
  resetCounts()
  let renderer = TestRenderer.create()
  let steps = []
  let previous = ref(Dict.make())
  for index in 0 to Array.length(specs) - 1 {
    let spec = specs->Array.getUnsafe(index)
    await render(renderer, spec, ~first=index == 0)
    await settleFully()
    let labels = labelsOf(spec)
    let uids = Dict.fromArray(labels->Array.map(label => (label, uidOf(renderer, label))))
    let kept =
      labels
      ->Array.filter(label => previous.contents->Dict.has(label))
      ->Array.map(label => (
        label,
        previous.contents->Dict.getUnsafe(label) == uids->Dict.getUnsafe(label),
      ))
    steps->Array.push({screen: TestRenderer.toString(renderer), kept})
    previous := uids
    labels->Array.forEach(label =>
      if setCounts->Dict.has(label) {
        bump(label)
      }
    )
  }
  steps
}

let seeds = Array.fromInitializer(~length=60, index => index + 1)

describe("refetching, fuzzed", () => {
  seeds->Array.forEach(seed =>
    testAsync(
      `seed ${Int.toString(seed)}`,
      async t => {
        let random = Random.make(Float.fromInt(seed * 7919))
        let specs = Array.fromInitializer(
          ~length=4,
          _ => generate(random, ~depth=3, ~labels=["a", "b", "c", "d", "e", "f"], ~key=None),
        )
        let chunkings =
          specs->Array.map(
            _ =>
              Random.intBelow(random, 3) == 0
                ? Testing.AsWritten
                : Testing.EveryBytes(1 + Random.intBelow(random, 40)),
          )
        let client = makeClient()
        let viaServer = await run(
          specs,
          ~render=async (renderer, spec, ~first) => {
            let index = specs->Array.findIndex(candidate => candidate === spec)
            let element = await roundTrip(
              ~client,
              ~chunking=chunkings->Array.getUnsafe(index),
              toElement(spec, ~server=true),
            )
            if first {
              TestRenderer.render(renderer, element)
            } else {
              Weft.Transition.start(() => TestRenderer.scheduleRender(renderer, element))
            }
          },
        )
        let direct = await run(
          specs,
          ~render=async (renderer, spec, ~first) => {
            let element = toElement(spec, ~server=false)
            if first {
              TestRenderer.render(renderer, element)
            } else {
              Weft.Transition.start(() => TestRenderer.scheduleRender(renderer, element))
            }
          },
        )
        t->expect(viaServer)->Expect.toEqual(direct)
      },
    )
  )
})
