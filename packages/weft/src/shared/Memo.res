external toDict: 'props => dict<unknown> = "%identity"

let shallowEqual = (a: 'props, b: 'props): bool =>
  Object.is(a, b) || {
    let a = toDict(a)
    let b = toDict(b)
    let keys = Dict.keysToArray(a)
    Array.length(keys) == Array.length(Dict.keysToArray(b)) &&
      keys->Array.every(key =>
        switch (a->Dict.get(key), b->Dict.get(key)) {
        | (Some(x), Some(y)) => Object.is(x, y)
        | (None, None) => true
        | _ => false
        }
      )
  }

let memoCustomComparison = (component: JsxCore.component<'props>, equal) => {
  // Rendered as a `MemoComponent` fiber, which calls `component` itself; calling the wrapper
  // directly just renders.
  let wrapper: JsxCore.component<'props> = props => component(props)
  Marker.setKind(wrapper, Marker.memoKind)
  Marker.setMemoInner(wrapper, component)
  Marker.setMemoCompare(wrapper, equal)
  wrapper
}

let memo = component => memoCustomComparison(component, shallowEqual)
