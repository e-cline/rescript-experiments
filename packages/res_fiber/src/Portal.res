type props = {children: Element.t}

let create = (~container, ~key=?, children) =>
  Element.fromNode({
    kind: Portal,
    elementType: Unsafe.toUnknown(container),
    key: switch key {
    | Some(key) => Nullable.make(key)
    | None => Nullable.null
    },
    props: Unsafe.toUnknown({children: children}),
  })
