/***
The bootstrap: what a real one does with these is phase 5's. This one puts them where a test can
find them.
*/

@module("virtual:weft/client") external loadModule: string => promise<unknown> = "loadModule"

type refresh = {file: string}
@module("virtual:weft/client") external onRefresh: (refresh => unit) => unit => unit = "onRefresh"

@val external global: dict<unknown> = "globalThis"

global->Dict.set("__weftLoadModule", loadModule->Obj.magic)

let _stop = onRefresh(data => global->Dict.set("__weftRefreshed", data.file->Obj.magic))
