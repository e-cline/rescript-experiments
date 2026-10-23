@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
Server components: a synchronous one, which compiles as written, and async ones, which the PPX
rewrites to return a `Lazy` element around their body's promise. The file starts with the
`'use weft server'` directive.
*/

module Title = {
  @weft.component({kind: Server})
  let make = (~title: string) => <h2> {Weft.TestJsx.string(title)} </h2>
}

/** Stands in for a database: what `Note` awaits. Tests replace it. */
let fetchNote: ref<string => promise<string>> = ref(id => Promise.resolve(`Note ${id}`))

module Note = {
  @weft.component({kind: Server})
  let make = async (~id: string) => {
    let text = await fetchNote.contents(id)
    <article id>
      <Title title=text />
    </article>
  }
}

/** An async component with a return type and a child, both still allowed. */
module Section = {
  @weft.component({kind: Server})
  let make = async (~heading: string, ~children: Weft.Element.t): Weft.Element.t => {
    let heading = await Promise.resolve(heading)
    <section>
      <Title title=heading />
      children
    </section>
  }
}
