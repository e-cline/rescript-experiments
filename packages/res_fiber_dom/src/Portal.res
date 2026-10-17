type props = {container: Dom.element, children: ResFiber.Element.t}

let create = (children, ~container: Dom.element, ~key=?) =>
  ResFiber.Portal.create(~container, ~key?, children)

let make = (props: props) => create(props.children, ~container=props.container)
