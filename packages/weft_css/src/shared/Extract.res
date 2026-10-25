type sheet = {
  id: string,
  css: string,
  dependencies: array<string>,
}

let baseLayer = "weft.base"
let componentsLayer = "weft.components"

let fail = message => JsError.throwWithMessage(`weft_css: ${message}`)

let nameOf = (registration: Css.Internal.registration) =>
  switch registration {
  | Class({name}) | Global({name}) | Var({name}) | Keyframes({name}) => name
  }

/** `define()`, saying whose definition it was if it throws. */
let defined = (name, define) =>
  try define() catch {
  | JsExn(error) =>
    fail(`the definition of ${name} threw: ${error->JsExn.message->Option.getOr("an exception")}`)
  | _ => fail(`the definition of ${name} threw`)
  }

let sheet = (id, registrations: array<Css.Internal.registration>) => {
  // Each layer's rules, layers in the order first used, `weft.base` first.
  let layers: array<(string, array<string>)> = [(baseLayer, [])]
  let rulesOf = layer =>
    switch layers->Array.find(((name, _)) => name === layer) {
    | Some((_, rules)) => rules
    | None =>
      let rules = []
      layers->Array.push((layer, rules))
      rules
    }
  let vars = []
  registrations->Array.forEach(registration =>
    switch registration {
    | Var({name, initial}) => vars->Array.push((name, defined(name, initial)))
    | Global({name, selector, layer, define}) =>
      rulesOf(layer->Option.getOr(baseLayer))->Array.push(
        Serialize.rules(~selector, defined(name, define)),
      )
    | Class({name, layer, define}) =>
      rulesOf(layer->Option.getOr(componentsLayer))->Array.push(
        Serialize.rules(~selector=`.${name}`, defined(name, define)),
      )
    | Keyframes({name, layer, define}) =>
      rulesOf(layer->Option.getOr(componentsLayer))->Array.push(
        Serialize.keyframes(~name, defined(name, define)),
      )
    }
  )
  rulesOf(baseLayer)->Array.unshift(Serialize.root(vars))
  let css =
    layers
    ->Array.filterMap(((name, rules)) =>
      switch rules->Array.join("") {
      | "" => None
      | text => Some(Serialize.layer(~name, text))
      }
    )
    ->Array.join("")
  {id, css, dependencies: SheetId.inText(css)->Array.filter(other => other !== id)}
}

let sheets = registrations => {
  let order = []
  let bySheet = Dict.make()
  let names = Set.make()
  registrations->Array.forEach(registration => {
    let name = nameOf(registration)
    if names->Set.has(name) {
      fail(`${name} is registered twice`)
    }
    names->Set.add(name)
    switch SheetId.ofName(name) {
    | Some(id) =>
      switch bySheet->Dict.get(id) {
      | Some(found) => found->Array.push(registration)
      | None =>
        order->Array.push(id)
        bySheet->Dict.set(id, [registration])
      }
    | None => fail(`${name} doesn't end in a sheet id: was it written by hand, not by ppx_weft?`)
    }
  })
  order->Array.map(id => sheet(id, bySheet->Dict.getUnsafe(id)))
}

let start = Css.Internal.record

let finish = () => sheets(Css.Internal.recorded())
