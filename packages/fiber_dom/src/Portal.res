type props = {container: Dom.element, children: Fiber.Element.t}

let create = (children, ~container: Dom.element, ~key=?) =>
  Fiber.Portal.create(~container, ~key?, children)

let make = (props: props) => create(props.children, ~container=props.container)
