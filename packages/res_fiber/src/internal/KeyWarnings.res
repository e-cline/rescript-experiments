/***
Development-build warnings about keys in a list of children, as React gives: two children with the
same key, and children without one in a list built at runtime (`Jsx.array`).

A `Jsx.array` list and the static children of `<ul> <li /> <li /> </ul>` (which the JSX transform
passes to `jsxs` as an array) look the same at runtime, so `jsxs` records its children here
(`markStatic`), and only a list it didn't record is checked for missing keys: static children never
reorder, so they don't need keys. Duplicate keys are checked in every list.

Callers check `Env.isDev` first, so a production bundle drops this module's work entirely.
*/

let staticLists: WeakSet.t<array<Element.t>> = WeakSet.make()

/** Records `children` as written out in JSX (passed to `jsxs`), so they don't need keys. */
let markStatic = (children: array<Element.t>) => staticLists->WeakSet.add(children)->ignore

/**
Where warnings go: `console.error`, as React's do. Tests replace it to capture them.
*/
let warn: ref<string => unit> = ref(message => Console.error(message))

@get external functionName: unknown => string = "name"

/** A component's name: its `make` function's, which the compiler names after its module. */
let componentName = (fiber: Fiber.t): string => {
  let make =
    fiber.tag == MemoComponent
      ? Unsafe.toUnknown(Marker.memoInner(fiber.elementType))
      : fiber.elementType
  functionName(make)->String.replaceAll("$", ".")
}

/** The nearest component at or above `fiber`, whose render produced the list. */
let rec owner = (fiber: option<Fiber.t>): option<string> =>
  switch fiber {
  | Some(fiber) if Fiber.isFunctionLike(fiber) => Some(componentName(fiber))
  | Some(fiber) => owner(fiber.parent)
  | None => None
  }

/** Where a list is, for a warning: its host element if it's directly inside one, and its owner. */
let describe = (returnFiber: Fiber.t): string => {
  let host =
    returnFiber.tag == HostComponent ? ` in <${Unsafe.fromUnknown(returnFiber.elementType)}>` : ""
  let owner = switch owner(Some(returnFiber)) {
  | Some(name) => ` rendered by ${name}`
  | None => ""
  }
  `${host}${owner}`
}

/**
Warns (at most once each) if `children`, about to be reconciled as `returnFiber`'s children, has two
children with the same key, or is a list built at runtime (not static `jsxs` children) of more
than one child with an element that has no key.
*/
let check = (returnFiber: Fiber.t, children: array<Element.t>) => {
  let checkMissing = Array.length(children) > 1 && !(staticLists->WeakSet.has(children))
  let missing = ref(false)
  let duplicate = ref(None)
  let seen = Set.make()
  children->Array.forEach(child =>
    switch Element.classify(child) {
    | Node({key}) =>
      switch Nullable.toOption(key) {
      | Some(key) =>
        if seen->Set.has(key) {
          if Option.isNone(duplicate.contents) {
            duplicate := Some(key)
          }
        } else {
          seen->Set.add(key)
        }
      | None =>
        if checkMissing {
          missing := true
        }
      }
    | Text(_) | List(_) | Empty => ()
    }
  )
  switch duplicate.contents {
  | Some(key) =>
    let where = describe(returnFiber)
    warn.contents(
      [
        `ResFiber: Encountered two children with the same key, "${key}",${where}.`,
        "Keys should be unique so that children keep their identity across updates;",
        "with duplicates, children may be duplicated or omitted.",
      ]->Array.join(" "),
    )
  | None => ()
  }
  if missing.contents {
    let where = describe(returnFiber)
    warn.contents(
      [
        `ResFiber: Each child in a list should have a unique "key" prop.`,
        `The list${where} has children without one.`,
      ]->Array.join(" "),
    )
  }
}
