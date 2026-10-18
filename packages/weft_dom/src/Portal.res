type props = {container: Dom.element, children: WeftCore.Element.t}

let create = (children, ~container: Dom.element, ~key=?) =>
  WeftCore.Portal.create(~container, ~key?, children)

let make = (props: props) => create(props.children, ~container=props.container)
