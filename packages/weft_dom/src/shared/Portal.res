type props = {container: Dom.element, children: Weft.Element.t}

let create = (children, ~container: Dom.element, ~key=?) =>
  Weft.Portal.create(~container, ~key?, children)

let make = (props: props) => create(props.children, ~container=props.container)
