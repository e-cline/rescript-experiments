/***
Where toasts show (`Toast.Viewport`, on the default manager), for a server component's layout to
render once: client code anywhere then calls `Toast.add`.
*/

@weft.component({kind: Entrypoint})
let make = (
  ~placement: [#bottom | #top]=#bottom,
  ~label="Notifications",
  ~dataId: option<string>=?,
) => <Toast.Viewport placement label ?dataId />
