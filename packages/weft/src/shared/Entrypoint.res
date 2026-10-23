@set external setId: (JsxCore.component<'props>, string) => unit = "$$weftEntrypoint"
@get external getId: JsxCore.component<'props> => Nullable.t<string> = "$$weftEntrypoint"

let mark = setId
let idOf = component => getId(component)->Nullable.toOption
