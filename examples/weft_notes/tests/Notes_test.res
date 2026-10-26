/***
The app's scenarios, through the plugin's harness: the server (with its fake database) in a worker,
each page in jsdom, and the server's responses handed over when the test says. The database's
queries wait on gates the test opens, so the order things stream in is the test's choice.
*/

open Vitest
open NotesSupport

let app = useApp()

beforeEachAsync(async () => await reset(app()))

let note1Fallbacks = [
  "[data-id=body-loading]",
  "[data-id=comment-list-loading]",
  "[data-id=related-loading]",
]

describe("the first page", () => {
  testAsync(
    "comes in one request: the shell and the first row, then each boundary as its gate opens",
    async t => {
      let page = app()->open_("/notes/1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=title]"))
      t->expect(text(page, "[data-id=title]"))->Expect.toBe("Groceries")
      t->expect(note1Fallbacks->Array.every(selector => has(page, selector)))->Expect.toBe(true)
      await hydratedAsServed(page, ~replaced=errorBoxPart)
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1"])
      // Related notes first, then the body, then the comments.
      await app()->release("related:1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=related]"))
      t->expect(has(page, "[data-id=body-loading]"))->Expect.toBe(true)
      t->expect(has(page, "[data-id=comment-list-loading]"))->Expect.toBe(true)
      await app()->release("body:1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=note-body]"))
      t->expect(text(page, "[data-id=note-body]"))->Expect.toBe("Milk, eggs, bread.")
      t->expect(has(page, "[data-id=comment-list-loading]"))->Expect.toBe(true)
      await app()->release("comments:1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list]"))
      t->expect(text(page, "[data-id=comment-list]"))->Expect.toBe("Ada: Don't forget coffee.")
      // The page's HTML, once it has all come: the shell, then the rows (taken out), with a
      // preload for each entrypoint's chunk before the first row using it.
      let shell = await page->WeftTesting.shell
      // The page's own HTML, rendered on the server: the title, and each boundary's content once
      // its gate opened (swapped in by the page's runtime).
      t->expect(shell->String.includes(`<div id="root" data-weft-html="">`))->Expect.toBe(true)
      t
      ->expect(
        shell->String.includes(`data-id="title"`) && shell->String.includes(`>Groceries</h1>`),
      )
      ->Expect.toBe(true)
      t->expect(shell->String.includes(`<template id="ws:`))->Expect.toBe(true)
      t->expect(shell->String.endsWith(`</body></html>`))->Expect.toBe(true)
      t->expect(shell->String.includes("(self.__weft||=[])"))->Expect.toBe(false)
      t
      ->expect(
        shell->String.includes(`<link rel="modulepreload" href="/src/client/LikeButton.res.js">`),
      )
      ->Expect.toBe(true)
    },
  )
})

/** Opens every gate the note page waits on, for tests that aren't about streaming. */
let openGates = async (~note="1") => {
  await app()->release(`body:${note}`)
  await app()->release(`comments:${note}`)
  await app()->release(`related:${note}`)
}

/** Opens note `note`'s page with every gate open, once it has all rendered, and hydrated. */
let openNote = async (~note="1", ~delivery=?) => {
  await openGates(~note)
  let page = app()->open_(~delivery?, `/notes/${note}`)
  await page->WeftTesting.waitFor(() =>
    has(page, "[data-id=note-body]") &&
    has(page, "[data-id=comment-list]") &&
    has(page, "[data-id=related]") &&
    has(page, "[data-id=like]")
  )
  await hydratedAsServed(page, ~replaced=errorBoxPart)
  page
}

let likeButton = "@e-cline/weft_notes_example/src/client/LikeButton.res#"
let commentForm = "@e-cline/weft_notes_example/src/client/CommentForm.res#"

describe("hydrating the first page", () => {
  testAsync(
    "isn't needed to read it: the title, then each boundary as its gate opens, with nothing working",
    async t => {
      let page = app()->open_(~bootstrap=false, "/notes/1")
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=title]") && has(page, "[data-id=like]"),
      )
      t->expect(text(page, "[data-id=title]"))->Expect.toBe("Groceries")
      t->expect(text(page, "[data-id=like]"))->Expect.toBe("3 likes")
      t->expect(note1Fallbacks->Array.every(selector => has(page, selector)))->Expect.toBe(true)
      await openGates()
      await page->WeftTesting.waitFor(
        () =>
          has(page, "[data-id=note-body]") &&
          has(page, "[data-id=comment-list]") &&
          has(page, "[data-id=related]"),
      )
      t->expect(text(page, "[data-id=note-body]"))->Expect.toBe("Milk, eggs, bread.")
      t->expect(text(page, "[data-id=comment-list]"))->Expect.toBe("Ada: Don't forget coffee.")
      // The failed part shows the server's fallback: the error box is the client's to render.
      t->expect(has(page, "[data-id=broken-loading]"))->Expect.toBe(true)
      t->expect(has(page, "[data-id=error-box]"))->Expect.toBe(false)
      page->WeftTesting.click("[data-id=like]")
      await page->WeftTesting.idle
      t->expect(text(page, "[data-id=like]"))->Expect.toBe("3 likes")
      t->expect(page->WeftTesting.renderCount(likeButton))->Expect.toBe(0)
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1"])
    },
  )

  testAsync(
    "hydrates what was swapped in before the bootstrap ran, and what's swapped in after",
    async t => {
      let page = app()->open_(~bootstrap=false, "/notes/1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=title]"))
      await app()->release("body:1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=note-body]"))
      // The bootstrap's chunk loading late: the body's already there, and hydrated with the rest.
      page->WeftTesting.startBootstrap
      await hydratedAsServed(page, ~replaced=errorBoxPart)
      t->expect(has(page, "[data-id=comment-list-loading]"))->Expect.toBe(true)
      await app()->release("comments:1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list]"))
      let swapped = page->WeftTesting.snapshot
      await page->WeftTesting.settle
      // The comments, from their segment: kept, not rendered again.
      t->expect(page->WeftTesting.removedSince(swapped))->Expect.toEqual([])
      t->expect(text(page, "[data-id=comment-list]"))->Expect.toBe("Ada: Don't forget coffee.")
      page->WeftTesting.click("[data-id=like]")
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=like]") == "3 likes (you liked this)",
      )
      t->expect(page->WeftTesting.warnings)->Expect.toEqual([])
    },
  )

  testAsync(
    "does what was clicked and typed before the bootstrap ran, once it has, in order",
    async t => {
      await openGates()
      let page = app()->open_(~bootstrap=false, "/notes/1")
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=like]") && has(page, "[data-id=comment-list]"),
      )
      page->WeftTesting.click("[data-id=like]")
      page->WeftTesting.input("[data-id=comment-author]", "Early")
      page->WeftTesting.input("[data-id=comment-text]", "Before the JavaScript")
      page->WeftTesting.click("[data-id=post-comment]")
      await page->WeftTesting.idle
      // Nothing's happened yet: no handler is there to run.
      t->expect(text(page, "[data-id=like]"))->Expect.toBe("3 likes")
      t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1"])
      page->WeftTesting.startBootstrap
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=comment-list]")->String.includes("Early: Before the JavaScript"),
      )
      // Liked (the comment's refresh brought the server's count with it).
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=like]") == "4 likes (you liked this)",
      )
      t->expect(await app()->likes(~noteId="1"))->Expect.toBe(4)
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual([
        "/notes/1",
        "/_weft/rpc/notes.like",
        "/_weft/rpc/notes.addComment",
        "/notes/1",
      ])
      t->expect(page->WeftTesting.warnings)->Expect.toEqual([])
    },
  )

  testAsync(
    "hydrates the rest while an entrypoint's chunk loads, and a boundary arriving meanwhile, then it",
    async t => {
      await app()->release("comments:1")
      await app()->release("related:1")
      let page = app()->open_("/notes/1")
      page->WeftTesting.holdLoads(~matching="LikeButton")
      await page->WeftTesting.waitFor(
        () => has(page, "[data-id=title]") && has(page, "[data-id=like]"),
      )
      await page->WeftTesting.hydrated
      // The server's button, while its chunk loads.
      t->expect(text(page, "[data-id=like]"))->Expect.toBe("3 likes")
      t->expect(has(page, "[data-id=likes-loading]"))->Expect.toBe(false)
      t->expect(page->WeftTesting.renderCount(likeButton))->Expect.toBe(0)
      // The editor is hydrated: it refuses an empty title.
      page->WeftTesting.input("[data-id=title-input]", "   ")
      page->WeftTesting.click("[data-id=save]")
      await page->WeftTesting.waitFor(
        () => fieldError(page, "[data-id=title-input]")->Option.isSome,
      )
      await app()->release("body:1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=note-body]"))
      page->WeftTesting.releaseLoads
      await hydratedAsServed(page, ~replaced=errorBoxPart)
      page->WeftTesting.click("[data-id=like]")
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=like]") == "3 likes (you liked this)",
      )
      t
      ->expect(page->WeftTesting.loads->Array.filter(id => id->String.includes("LikeButton")))
      ->Expect.toEqual(["@e-cline/weft_notes_example/src/client/LikeButton.res"])
    },
  )

  testAsync(
    "links the comment's hint by an ID that's the same in the HTML and once hydrated",
    async t => {
      let page = await openNote()
      let attribute = (selector, name) =>
        page
        ->WeftTesting.query(selector)
        ->Option.flatMap(element => WeftDom.Dom.getAttribute(element, name)->Nullable.toOption)
      let hint = attribute("[data-id=comment-text]", "aria-describedby")
      t->expect(Option.isSome(hint))->Expect.toBe(true)
      let hint = Option.getUnsafe(hint)
      t->expect(text(page, `[id="${hint}"]`))->Expect.toBe("At most 500 characters.")
      // As the server wrote it (`openNote` checked hydration warned of no attribute differing).
      let shell = await page->WeftTesting.shell
      t->expect(shell->String.includes(`aria-describedby="${hint}"`))->Expect.toBe(true)
      t->expect(shell->String.includes(`id="${hint}"`))->Expect.toBe(true)
    },
  )

  testAsync("renders the failing component's error box on the client, and only that", async t => {
    let page = await openNote()
    t
    ->expect(text(page, "[data-id=error-box]"))
    ->Expect.toBe("Couldn't show this: the recommendations service is down")
    t
    ->expect(
      page
      ->WeftTesting.removedSince(page->WeftTesting.htmlNodes)
      ->Array.every(node => errorBoxPart->Array.includes(node)),
    )
    ->Expect.toBe(true)
  })

  testAsync("patches a text the client renders differently, and warns about it", async t => {
    await openGates()
    let serverDay = today()
    // The browser's clock says another day than the server's.
    let restore = turnClockBack(400)
    let clientDay = today()
    let page = app()->open_("/notes/1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=note-body]"))
    let fromServer = page->WeftTesting.query("[data-id=today]")
    await page->WeftTesting.hydrated
    restore()
    t->expect((await page->WeftTesting.shell)->String.includes(serverDay))->Expect.toBe(true)
    t->expect(text(page, "[data-id=today]"))->Expect.toBe(clientDay)
    t->expect(page->WeftTesting.query("[data-id=today]") === fromServer)->Expect.toBe(true)
    t
    ->expect(page->WeftTesting.warnings)
    ->Expect.toEqual([
      `Weft: the server's HTML doesn't match the client's render: the text "${serverDay}" is "${clientDay}" on the client`,
    ])
  })
})

describe("the first page, in any order", () => {
  testAsync("streams the boundaries in whichever order their gates open", async t => {
    let page = app()->open_("/notes/1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=title]"))
    await app()->release("comments:1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list]"))
    t
    ->expect(has(page, "[data-id=body-loading]") && has(page, "[data-id=related-loading]"))
    ->Expect.toBe(true)
    await app()->release("body:1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=note-body]"))
    t->expect(has(page, "[data-id=related-loading]"))->Expect.toBe(true)
    await app()->release("related:1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=related]"))
  })

  testAsync("ends up the same however the HTML is cut up, or if it all comes at once", async t => {
    let finals = []
    for size in 0 to 3 {
      await reset(app())
      let delivery = switch size {
      | 0 => WeftTesting.Immediate
      | 1 => EveryBytes(1)
      | 2 => EveryBytes(7)
      | _ => EveryBytes(4096)
      }
      let page = await openNote(~delivery)
      await page->WeftTesting.settle
      finals->Array.push(page->WeftTesting.html)
    }
    t->expect(finals->Array.every(html => html == finals->Array.getUnsafe(0)))->Expect.toBe(true)
    t->expect(finals->Array.getUnsafe(0)->String.includes("Milk, eggs, bread."))->Expect.toBe(true)
  })

  testAsync("shows the comments' own fallback until the promise they come as resolves", async t => {
    let page = app()->open_("/notes/1")
    // The list is an entrypoint, rendered with the page; what it's given is a promise of the
    // comments, whose fallback is the list's own.
    await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list-loading]"))
    t->expect(has(page, "[data-id=comment-list]"))->Expect.toBe(false)
    await app()->release("comments:1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list]"))
    t->expect(has(page, "[data-id=comment-list-loading]"))->Expect.toBe(false)
  })

  testAsync(
    "shows a failing component's error in its error box, and the rest of the page",
    async t => {
      let page = await openNote()
      t
      ->expect(text(page, "[data-id=error-box]"))
      ->Expect.toBe("Couldn't show this: the recommendations service is down")
      t->expect(text(page, "[data-id=title]"))->Expect.toBe("Groceries")
    },
  )
})

describe("navigating", () => {
  testAsync("keeps the like button's state across notes and a refresh", async t => {
    await openGates(~note="2")
    let page = await openNote()
    page->WeftTesting.click("[data-id=like]")
    await page->WeftTesting.waitFor(
      () => text(page, "[data-id=like]")->String.includes("you liked this"),
    )
    await page->WeftTesting.navigate("/notes/2")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=title]") == "Ideas")
    t->expect(text(page, "[data-id=like]"))->Expect.toBe("5 likes (you liked this)")
    await page->WeftTesting.refresh
    await page->WeftTesting.settle
    t->expect(text(page, "[data-id=like]"))->Expect.toBe("5 likes (you liked this)")
  })

  testAsync("by a link, fetches the payload, not the page", async t => {
    let page = app()->open_("/")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=note-link-2]"))
    await hydratedAsServed(page)
    page->WeftTesting.click("[data-id=note-link-2]")
    await page->WeftTesting.waitFor(() => text(page, "[data-id=title]") == "Ideas")
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/", "/notes/2"])
  })

  testAsync(
    "away from a page still streaming cancels its response: its queries are abandoned, and none of its rows land",
    async t => {
      let page = app()->open_("/")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=notes]"))
      await page->WeftTesting.navigate("/notes/1")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=title]") == "Groceries")
      let waitingOn1 =
        (await waiting(app()))->Array.filter(
          id => id->String.endsWith(":1") || id->String.includes(":1#"),
        )
      t->expect(Array.length(waitingOn1))->Expect.toBe(3)
      await page->WeftTesting.navigate("/notes/2")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=title]") == "Ideas")
      // The server saw note 1's queries abandoned when the client went away.
      let rec abandonedOn1 = async tries => {
        let found = (await abandoned(app()))->Array.filter(id => id->String.includes(":1#"))
        Array.length(found) == 3 || tries == 0
          ? found
          : {
              await page->WeftTesting.idle
              await abandonedOn1(tries - 1)
            }
      }
      t->expect(Array.length(await abandonedOn1(50)))->Expect.toBe(3)
      await openGates(~note="1")
      await page->WeftTesting.settle
      t->expect(page->WeftTesting.html->String.includes("Milk, eggs, bread."))->Expect.toBe(false)
      t->expect(text(page, "[data-id=title]"))->Expect.toBe("Ideas")
    },
  )
})

describe("posting", () => {
  testAsync("a comment, then refreshing, shows it, and keeps the form's other state", async t => {
    let page = await openNote()
    page->WeftTesting.input("[data-id=comment-author]", "Me")
    page->WeftTesting.input("[data-id=comment-text]", "Hello!")
    page->WeftTesting.click("[data-id=post-comment]")
    await page->WeftTesting.waitFor(
      () => text(page, "[data-id=comment-list]")->String.includes("Me: Hello!"),
    )
    t
    ->expect(page->WeftTesting.query("[data-id=comment-author]")->Option.map(Doc.value))
    ->Expect.toEqual(Some("Me"))
    t
    ->expect(page->WeftTesting.query("[data-id=comment-text]")->Option.map(Doc.value))
    ->Expect.toEqual(Some(""))
  })

  testAsync(
    "a new title refetches the saved title alone: the draft, focus and selection kept, nothing else touched",
    async t => {
      let page = await openNote()
      let input = page->WeftTesting.query("[data-id=title-input]")->Option.getOrThrow
      let likeRenders = page->WeftTesting.renderCount(likeButton)
      let formRenders = page->WeftTesting.renderCount(commentForm)
      page->WeftTesting.input("[data-id=title-input]", "Groceries!")
      input->Doc.focus
      input->Doc.setSelectionRange(2, 5)
      let before = page->WeftTesting.snapshot
      page->WeftTesting.click("[data-id=save]")
      await page->WeftTesting.waitFor(() => text(page, "[data-id=saved-at]") == "Saved: revision 1")
      await page->WeftTesting.settle
      t->expect(text(page, "[data-id=title]"))->Expect.toBe("Groceries!")
      t->expect(page->WeftTesting.query("[data-id=title-input]") === Some(input))->Expect.toBe(true)
      t->expect(Doc.value(input))->Expect.toBe("Groceries!")
      t->expect(Doc.activeElement() === input)->Expect.toBe(true)
      t->expect((Doc.selectionStart(input), Doc.selectionEnd(input)))->Expect.toEqual((2, 5))
      t->expect(page->WeftTesting.removedSince(before))->Expect.toEqual([])
      t->expect(page->WeftTesting.renderCount(likeButton))->Expect.toBe(likeRenders)
      t->expect(page->WeftTesting.renderCount(commentForm))->Expect.toBe(formRenders)
      t
      ->expect(page->WeftTesting.pageRequests)
      ->Expect.toEqual(["/notes/1", "/_weft/rpc/notes.saveTitle", "/notes/1/title"])
    },
  )

  testAsync("an empty title is refused on the client, and nothing is sent", async t => {
    let page = await openNote()
    page->WeftTesting.input("[data-id=title-input]", "   ")
    page->WeftTesting.click("[data-id=save]")
    await page->WeftTesting.waitFor(() => fieldError(page, "[data-id=title-input]")->Option.isSome)
    t
    ->expect(fieldError(page, "[data-id=title-input]"))
    ->Expect.toEqual(Some("A title can't be empty."))
    t->expect(text(page, "[data-id=title]"))->Expect.toBe("Groceries")
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1"])
  })
})

describe("posting, through RPCs", () => {
  let rpc = "/_weft/rpc/notes.addComment"

  testAsync("a comment the RPC's prepare refuses shows why, and sends nothing", async t => {
    let page = await openNote()
    page->WeftTesting.input("[data-id=comment-author]", "Me")
    page->WeftTesting.input("[data-id=comment-text]", "   ")
    page->WeftTesting.click("[data-id=post-comment]")
    await page->WeftTesting.waitFor(() => fieldError(page, "[data-id=comment-text]")->Option.isSome)
    t
    ->expect(fieldError(page, "[data-id=comment-text]"))
    ->Expect.toEqual(Some("Write something first."))
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1"])
    t->expect(await app()->commentCount(~noteId="1"))->Expect.toBe(1)
    // Fixed, it goes, and the error goes away.
    page->WeftTesting.input("[data-id=comment-text]", "Now with words")
    page->WeftTesting.click("[data-id=post-comment]")
    await page->WeftTesting.waitFor(
      () => text(page, "[data-id=comment-list]")->String.includes("Me: Now with words"),
    )
    t->expect(fieldError(page, "[data-id=comment-text]"))->Expect.toEqual(None)
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1", rpc, "/notes/1"])
  })

  testAsync("a comment the handler refuses shows why", async t => {
    let page = await openNote()
    await app()->removeNote(~noteId="1")
    page->WeftTesting.input("[data-id=comment-text]", "Hello?")
    page->WeftTesting.click("[data-id=post-comment]")
    await page->WeftTesting.waitFor(() => formError(page, "comment-form")->Option.isSome)
    t
    ->expect(formError(page, "comment-form"))
    ->Expect.toEqual(Some("This note doesn't exist any more."))
    // Nothing was refreshed: the text is still there to try again with.
    t
    ->expect(page->WeftTesting.query("[data-id=comment-text]")->Option.map(Doc.value))
    ->Expect.toEqual(Some("Hello?"))
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1", rpc])
  })

  testAsync("the server checks a comment again, whatever the client sent", async t => {
    let page = await openNote()
    // A client that doesn't check (a forged request, say): far too long a comment.
    app()->WeftTesting.rewriteBodies(
      rpc,
      body => body->String.replace(`"text":"short"`, `"text":"${String.repeat("x", 501)}"`),
    )
    page->WeftTesting.input("[data-id=comment-text]", "short")
    page->WeftTesting.click("[data-id=post-comment]")
    await page->WeftTesting.waitFor(() => fieldError(page, "[data-id=comment-text]")->Option.isSome)
    app()->WeftTesting.stopRewriting
    t
    ->expect(fieldError(page, "[data-id=comment-text]"))
    ->Expect.toEqual(Some("That's too long: 500 characters at most."))
    t->expect(await app()->commentCount(~noteId="1"))->Expect.toBe(1)
  })

  testAsync("a request the server can't read is Invalid, and the page says so", async t => {
    let page = await openNote()
    // An older client, whose request has other names for its fields.
    app()->WeftTesting.rewriteBodies(rpc, _ => `{"note":"1","comment":"hi"}`)
    page->WeftTesting.input("[data-id=comment-text]", "hi")
    page->WeftTesting.click("[data-id=post-comment]")
    await page->WeftTesting.waitFor(() => formError(page, "comment-form")->Option.isSome)
    app()->WeftTesting.stopRewriting
    t
    ->expect(formError(page, "comment-form"))
    ->Expect.toEqual(Some("The server couldn't read that: reload the page, and try again."))
    t->expect(await app()->commentCount(~noteId="1"))->Expect.toBe(1)
  })

  testAsync("liking is an RPC too", async t => {
    let page = await openNote()
    page->WeftTesting.click("[data-id=like]")
    await page->WeftTesting.waitFor(
      () => text(page, "[data-id=like]")->String.includes("you liked this"),
    )
    await page->WeftTesting.settle
    t->expect(await app()->likes(~noteId="1"))->Expect.toBe(4)
    t->expect(page->WeftTesting.pageRequests)->Expect.toEqual(["/notes/1", "/_weft/rpc/notes.like"])
  })
})

describe("the comments, refetched by themselves", () => {
  testAsync(
    "reloaded after another user's changes: the new comment inserted, the edited one updated in place",
    async t => {
      let page = await openNote()
      let first = page->WeftTesting.query("[data-id=comment-c1]")->Option.getOrThrow
      let before = page->WeftTesting.snapshot
      await app()->addComment(~noteId="1", ~author="Bob", ~text="New here")
      await app()->editComment(~noteId="1", ~commentId="c1", ~text="Coffee too.")
      page->WeftTesting.click("[data-id=reload-comments]")
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=comment-list]")->String.includes("Bob: New here"),
      )
      await page->WeftTesting.settle
      t->expect(page->WeftTesting.query("[data-id=comment-c1]") === Some(first))->Expect.toBe(true)
      t->expect(text(page, "[data-id=comment-c1]"))->Expect.toBe("Ada: Coffee too.")
      t->expect(page->WeftTesting.removedSince(before))->Expect.toEqual([])
    },
  )

  testAsync(
    "reloading while its gate is held keeps the old comments, pending, until it opens",
    async t => {
      let page = app()->open_("/notes/1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list-loading]"))
      // Let this first query through, but not the reload's.
      await app()->release(await app()->waiterFor("comments:1"))
      await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list]"))
      await page->WeftTesting.hydrated
      await app()->addComment(~noteId="1", ~author="Bob", ~text="Later")
      page->WeftTesting.click("[data-id=reload-comments]")
      await page->WeftTesting.waitFor(
        () => page->WeftTesting.query("[data-id=reload-comments]")->Option.isSome,
      )
      let rec reloadWaiting = async tries =>
        switch (await waiting(app()))->Array.find(id => id->String.startsWith("comments:1#")) {
        | Some(id) => id
        | None if tries > 0 =>
          await page->WeftTesting.idle
          await reloadWaiting(tries - 1)
        | None => JsError.throwWithMessage("the reload never queried the comments")
        }
      let reload = await reloadWaiting(100)
      await page->WeftTesting.settle
      t->expect(has(page, "[data-id=comment-list]"))->Expect.toBe(true)
      t->expect(has(page, "[data-id=comment-list-loading]"))->Expect.toBe(false)
      t->expect(text(page, "[data-id=comment-list]")->String.includes("Later"))->Expect.toBe(false)
      t
      ->expect(page->WeftTesting.textOf("[data-id=reload-comments]"))
      ->Expect.toEqual(Some("Reloading…"))
      await app()->release(reload)
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=comment-list]")->String.includes("Bob: Later"),
      )
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=reload-comments]") == "Reload comments",
      )
    },
  )

  testAsync("reloaded twice, with the first held: the first never lands", async t => {
    let page = app()->open_("/notes/1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list-loading]"))
    await app()->release(await app()->waiterFor("comments:1"))
    await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list]"))
    await page->WeftTesting.hydrated
    page->WeftTesting.click("[data-id=reload-comments]")
    let rec waiterCount = async (count, tries) => {
      let found = (await waiting(app()))->Array.filter(id => id->String.startsWith("comments:1#"))
      Array.length(found) >= count || tries == 0
        ? found
        : {
            await page->WeftTesting.idle
            await waiterCount(count, tries - 1)
          }
    }
    let firstReload = (await waiterCount(1, 100))->Array.getUnsafe(0)
    await app()->addComment(~noteId="1", ~author="Bob", ~text="Second")
    page->WeftTesting.click("[data-id=reload-comments]")
    // The second reload cancels the first: its query is abandoned.
    let rec firstAbandoned = async tries =>
      (await abandoned(app()))->Array.includes(firstReload) || tries == 0
        ? (await abandoned(app()))->Array.includes(firstReload)
        : {
            await page->WeftTesting.idle
            await firstAbandoned(tries - 1)
          }
    t->expect(await firstAbandoned(100))->Expect.toBe(true)
    await app()->release("comments:1")
    await page->WeftTesting.waitFor(
      () => text(page, "[data-id=comment-list]")->String.includes("Bob: Second"),
    )
    await page->WeftTesting.settle
    t->expect(text(page, "[data-id=reload-comments]"))->Expect.toBe("Reload comments")
  })
})

describe("the server's data changing", () => {
  testAsync(
    "shows the server's like count after a refresh, keeping the button's own state",
    async _t => {
      let page = await openNote()
      page->WeftTesting.click("[data-id=like]")
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=like]")->String.includes("you liked this"),
      )
      // The like has been posted.
      await page->WeftTesting.settle
      await app()->setLikes(~noteId="1", ~likes=10)
      await page->WeftTesting.refresh
      await page->WeftTesting.waitFor(
        () => text(page, "[data-id=like]") == "10 likes (you liked this)",
      )
    },
  )
})

let sheetOf = file => WeftCss.SheetId.ofFileId(`@e-cline/weft_notes_example/src/${file}.res`)

/** The stylesheets a page's HTML links in its head. */
let headSheets = html =>
  html
  ->String.slice(~start=0, ~end=html->String.indexOf("</head>"))
  ->String.split(`<link rel="stylesheet" href="`)
  ->Array.slice(~start=1)
  ->Array.map(rest => rest->String.slice(~start=0, ~end=rest->String.indexOf(`"`)))

let hasSheet = (hrefs, file) => hrefs->Array.some(href => href->String.includes(sheetOf(file)))

/** Whether any of `hrefs` is weft_ui's `file`'s sheet (`Field`, `Input`). */
let hasUiSheet = (hrefs, file) =>
  hrefs->Array.some(href =>
    href->String.includes(WeftCss.SheetId.ofFileId(`@e-cline/weft_ui/src/${file}.res`))
  )

describe("the styles (weft_css)", () => {
  testAsync(
    "are sent by what each page renders: the list's in its head, a note's when it's opened",
    async t => {
      let page = app()->open_("/")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=notes]"))
      let head = headSheets(await page->WeftTesting.shell)
      // The list's: the theme, the pages (server-only), and weft_ui's that it renders.
      t->expect(head->hasSheet("shared/Theme"))->Expect.toBe(true)
      t->expect(head->hasSheet("server/Pages"))->Expect.toBe(true)
      t->expect(head->hasUiSheet("List"))->Expect.toBe(true)
      t->expect(head->hasUiSheet("Tokens"))->Expect.toBe(true)
      // Not what the list doesn't render: a note's comment form's fields.
      t->expect(head->hasUiSheet("Field"))->Expect.toBe(false)
      t->expect(head->hasUiSheet("Input"))->Expect.toBe(false)
      t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
      // Opening a note brings its sheets, loaded by the client.
      await openGates()
      await page->WeftTesting.navigate("/notes/1")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-form]"))
      t->expect(page->WeftTesting.stylesheets->hasUiSheet("Field"))->Expect.toBe(true)
      t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
    },
  )

  testAsync("show nothing unstyled while a note streams in, part by part", async t => {
    let page = app()->open_("/notes/1")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=title]"))
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
    for i in 0 to 2 {
      await app()->release(["related:1", "body:1", "comments:1"]->Array.getUnsafe(i))
      await page->WeftTesting.settle
      t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
    }
    await page->WeftTesting.waitFor(() => has(page, "[data-id=comment-list]"))
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
  })
})
