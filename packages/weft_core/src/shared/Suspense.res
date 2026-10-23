type props = SuspenseImpl.props = {fallback: Element.t, children: Element.t}

// Rendered as a `SuspenseComponent` fiber; calling it directly just renders the children.
let make: JsxCore.component<props> = props => props.children
Marker.setKind(make, Marker.suspenseKind)
