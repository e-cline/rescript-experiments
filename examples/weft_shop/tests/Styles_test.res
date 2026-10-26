/***
The store's styles (`weft_css`): each page is sent the stylesheets of what it renders, the shell's
in its head, and nothing shows without its CSS, as the page streams in or as the shopper navigates.
*/

open Vitest
open ShopSupport

let app = useApp()

let sheetOf = file => WeftCss.SheetId.ofFileId(`@e-cline/weft_shop_example/src/${file}.res`)

/** The stylesheets a page's HTML links in its head. */
let headSheets = html => {
  let head = html->String.slice(~start=0, ~end=html->String.indexOf("</head>"))
  head
  ->String.split(`<link rel="stylesheet" href="`)
  ->Array.slice(~start=1)
  ->Array.map(rest => rest->String.slice(~start=0, ~end=rest->String.indexOf(`"`)))
}

/** Whether any of `hrefs` is `file`'s sheet. */
let hasSheet = (hrefs, file) => hrefs->Array.some(href => href->String.includes(sheetOf(file)))

/** weft_ui's `file`'s sheet (`Table`), and whether any of `hrefs` is it. */
let uiSheetOf = file => WeftCss.SheetId.ofFileId(`@e-cline/weft_ui/src/${file}.res`)
let hasUiSheet = (hrefs, file) => hrefs->Array.some(href => href->String.includes(uiSheetOf(file)))

describe("the store's styles", () => {
  testAsync(
    "are sent by what each page renders: the home page's in its head, the cart's when it's opened",
    async t => {
      await app()->releaseAll
      let page = app()->open_("/")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=blocks-home]"))
      await hydratedAsServed(page)
      let head = headSheets(await page->WeftTesting.shell)
      // The shell's: the theme, the frame around every page (`Ui`, server-only), the blocks.
      t->expect(head->hasSheet("shared/Theme"))->Expect.toBe(true)
      t->expect(head->hasSheet("server/Ui"))->Expect.toBe(true)
      // Not what the home page doesn't render: the cart's lines (weft_ui's table), the checkout's form.
      t->expect(head->hasUiSheet("Table"))->Expect.toBe(false)
      t->expect(head->hasSheet("client/CheckoutForm"))->Expect.toBe(false)
      t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
      // Navigating to the cart brings its sheets, loaded by the client.
      await addToCart(app(), "p1-9", 1)
      await page->WeftTesting.navigate("/cart")
      await page->WeftTesting.waitFor(() => has(page, "[data-id=cart-lines]"))
      t->expect(page->WeftTesting.stylesheets->hasUiSheet("Table"))->Expect.toBe(true)
      t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
    },
  )

  testAsync("show nothing unstyled while the page streams in, block by block", async t => {
    let page = app()->open_("/")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=home-loading]"))
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
    // Each part answers in turn (the layout, a rail, a card's stock, the hero, a tab's rail); the
    // page is styled at every step.
    let gates = ["layout:home", "rail:featured", "stock:p1", "block:hero", "rail:tab-outerwear"]
    for i in 0 to Array.length(gates) - 1 {
      await app()->release(gates->Array.getUnsafe(i))
      await page->WeftTesting.settle
      t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
    }
    await app()->releaseAll
    await page->WeftTesting.settle
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
  })

  testAsync("keep the old page on screen until the new one's sheets have loaded", async t => {
    await app()->releaseAll
    let page = app()->open_("/")
    await page->WeftTesting.waitFor(() => has(page, "[data-id=blocks-home]"))
    await hydratedAsServed(page)
    page->WeftTesting.holdStylesheets(~matching=uiSheetOf("Table"))
    let navigated = page->WeftTesting.navigate("/cart")
    await page->WeftTesting.settle
    // The cart's page is in, but for its lines' sheet (weft_ui's table's): the home page stays.
    t->expect(has(page, "[data-id=blocks-home]"))->Expect.toBe(true)
    t->expect(has(page, "[data-id=cart-title]"))->Expect.toBe(false)
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
    page->WeftTesting.releaseStylesheets
    await navigated
    await page->WeftTesting.waitFor(() => has(page, "[data-id=cart-title]"))
    t->expect(page->WeftTesting.unstyled)->Expect.toEqual([])
  })
})
