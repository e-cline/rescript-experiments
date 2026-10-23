@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
Uses every fixture through JSX, which only compiles if each `@weft.component` became
`@jsx.component` before the JSX transform ran: otherwise the components would have no `props` type.
*/

@weft.component
let make = () =>
  <Shared.ViaWeft name="page">
    <ServerComponents.Title title="Kinds" />
    <Entrypoints count=3 />
    <Entrypoints.Nested label="Go" />
    <Entrypoints.Outer.Inner label="Press" pressed=true />
    <Entrypoints.Error message="Oops" />
    <Entrypoints.Shared text="shared" />
    <WithInterface greeting="Hello" name="Weft" />
  </Shared.ViaWeft>
