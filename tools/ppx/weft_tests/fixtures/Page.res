@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
Uses every fixture through JSX, which only compiles if each `@weft.component` became
`@jsx.component` before the JSX transform ran: otherwise the components would have no `props` type.
*/

@weft.component
let make = () =>
  <Shared.ViaWeft name="page">
    <Kinds.Server title="Kinds" />
    <Kinds count=3 />
    <Kinds.Nested label="Go" />
    <Kinds.Error message="Oops" />
    <WithInterface greeting="Hello" name="Weft" />
  </Shared.ViaWeft>
