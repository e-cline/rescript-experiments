open Vitest

describe("Html", () => {
  test("text escapes markup", t => {
    t
    ->expect(Html.text(`<script>alert("x & y's")</script>`)->Html.toString)
    ->Expect.toBe("&lt;script&gt;alert(&quot;x &amp; y&#39;s&quot;)&lt;/script&gt;")
  })

  test("raw doesn't", t => {
    t->expect(Html.raw("<b>bold</b>")->Html.toString)->Expect.toBe("<b>bold</b>")
  })

  test("the html template keeps its own markup and interpolates Html values", t => {
    let name = "<Ada>"
    let page = Html.html`<p class="greeting">Hello, ${Html.text(name)}! You are visitor ${Html.int(
      3,
    )}.</p>`
    t
    ->expect(page->Html.toString)
    ->Expect.toBe(`<p class="greeting">Hello, &lt;Ada&gt;! You are visitor 3.</p>`)
  })

  test("templates nest, and join combines a list", t => {
    let items = ["a", "<b>"]->Array.map(item => Html.html`<li>${Html.text(item)}</li>`)
    let list = Html.html`<ul>${items->Html.join}</ul>`
    t->expect(list->Html.toString)->Expect.toBe("<ul><li>a</li><li>&lt;b&gt;</li></ul>")
    t
    ->expect(items->Html.join(~separator=Html.raw("\n"))->Html.toString)
    ->Expect.toBe("<li>a</li>\n<li>&lt;b&gt;</li>")
    t->expect(Html.html`${Html.empty}`->Html.toString)->Expect.toBe("")
  })

  test("url lets through links, and nothing that runs", t => {
    let url = value => Html.url(value)->Html.toString
    t
    ->expect(url("https://example.com/a?b=1&c=2"))
    ->Expect.toBe("https://example.com/a?b=1&amp;c=2")
    t->expect(url("http://example.com"))->Expect.toBe("http://example.com")
    t->expect(url("/users/42"))->Expect.toBe("/users/42")
    t->expect(url("../up?x=1#frag"))->Expect.toBe("../up?x=1#frag")
    t->expect(url("//cdn.example/x.png"))->Expect.toBe("//cdn.example/x.png")
    t->expect(url("mailto:ada@example.com"))->Expect.toBe("mailto:ada@example.com")
    t->expect(url("tel:+15550100"))->Expect.toBe("tel:+15550100")
    t->expect(url(""))->Expect.toBe("")

    let blocked = [
      "javascript:alert(1)",
      "JavaScript:alert(1)",
      "  javascript:alert(1)",
      "java\tscript:alert(1)",
      "java\nscript:alert(1)",
      "\u0001javascript:alert(1)",
      "data:text/html,<script>alert(1)</script>",
      "vbscript:msgbox(1)",
      "file:///etc/passwd",
    ]
    t
    ->expect(blocked->Array.map(url)->Array.filter(value => value != "about:invalid"))
    ->Expect.toEqual([])
  })

  test("url escapes, so it can't close the attribute it's in", t => {
    let link = Html.html`<a href="${Html.url(`/search?q="><script>alert(1)</script>`)}">x</a>`
    t
    ->expect(link->Html.toString)
    ->Expect.toBe(`<a href="/search?q=&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;">x</a>`)
  })

  test("json can't end the script element it's in, and still parses to the same value", t => {
    let value = JSON.Encode.object(
      dict{
        "text": JSON.Encode.string("</script><script>alert(1)</script> & <!-- \u2028"),
        "n": JSON.Encode.int(1),
      },
    )
    let written = Html.json(value)->Html.toString
    t->expect(written->String.includes("<"))->Expect.toBe(false)
    t->expect(written->String.includes(">"))->Expect.toBe(false)
    t->expect(written->String.includes("&"))->Expect.toBe(false)
    t->expect(written->String.includes("\u2028"))->Expect.toBe(false)
    t->expect(JSON.parseOrThrow(written))->Expect.toEqual(value)
  })
})
