// The store's styles in a browser, against the build, with the latency gated and every stylesheet
// slowed down: nothing is ever on screen without its CSS. A probe on every animation frame looks at
// each element with a `weft_css` class (a name ending in a sheet id) and checks the sheet it's in
// has been applied (its link's `sheet` is set), while the page streams in, block by block, and as
// the shopper navigates, adds to the cart and changes a quantity.

import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from '@playwright/test';

const control = (request: APIRequestContext, ...path: string[]) =>
  request.post(`/test/${path.map(encodeURIComponent).join('/')}`);
const release = (request: APIRequestContext, gate: string) =>
  control(request, 'release', gate);
const releaseAll = (request: APIRequestContext) =>
  control(request, 'release-all');

const hydrated = (page: Page, selector: string) =>
  page.waitForFunction((selector) => {
    const element = document.querySelector(selector);
    return element !== null && '$$resFiberProps' in element;
  }, selector);

/** Records, every frame, each element shown with a class whose sheet hasn't been applied. */
function probe() {
  const seen: string[] = [];
  (window as unknown as {__unstyled: string[]}).__unstyled = seen;
  const applied = (id: string) =>
    [
      ...document.querySelectorAll<HTMLLinkElement>('link[rel="stylesheet"]'),
    ].some(
      (link) =>
        (link.getAttribute('href') ?? '').includes(id) && link.sheet !== null,
    );
  const check = () => {
    for (const element of document.querySelectorAll('[class]')) {
      for (const name of (element.getAttribute('class') ?? '').split(/\s+/)) {
        const id = /_(w[0-9a-z]{6})$/.exec(name)?.[1];
        if (id !== undefined && !applied(id)) {
          const found = `${element.localName}.${name} (${Math.round(performance.now())} ms)`;
          if (seen.length < 50) seen.push(found);
        }
      }
    }
    requestAnimationFrame(check);
  };
  requestAnimationFrame(check);
}

const unstyled = (page: Page) =>
  page.evaluate(() => (window as unknown as {__unstyled: string[]}).__unstyled);

/** Every stylesheet the page asks for, `delay` ms late. */
const slowStylesheets = (page: Page, delay = 500) =>
  page.route(/\.css(\?.*)?$/, async (route) => {
    await new Promise((resolve) => setTimeout(resolve, delay));
    await route.continue();
  });

test.beforeEach(async ({request}) => {
  await control(request, 'reset');
});

test('the probe sees a page shown before its CSS (a stylesheet a script adds, not waited for)', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await page.addInitScript(probe);
  await slowStylesheets(page);
  await page.goto('/');
  await expect(page.locator('#blocks-home')).toBeVisible();
  // A class whose sheet is added without waiting for it: what Weft never does.
  await page.evaluate(() => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/assets/wzzzzzz-control.css';
    document.head.append(link);
    document.querySelector('#main')!.classList.add('Control-x_wzzzzzz');
  });
  await page.waitForTimeout(200);
  expect((await unstyled(page)).length).toBeGreaterThan(0);
});

test('nothing shows without its CSS: streaming, navigating, the cart and its totals', async ({
  page,
  request,
}) => {
  await page.addInitScript(probe);
  await slowStylesheets(page);
  // The home page, streaming: the shell (its sheets in the head), then each block, whose sheets
  // come with it.
  await page.goto('/', {waitUntil: 'commit'});
  await expect(page.locator('#home-loading')).toBeVisible();
  await release(request, 'layout:home');
  await expect(page.locator('#loading-featured')).toBeVisible();
  await release(request, 'rail:featured');
  await expect(page.locator('#carousel-featured')).toBeVisible();
  await release(request, 'block:hero');
  await expect(page.locator('#hero-hero h1')).toBeVisible();
  await releaseAll(request);
  await expect(page.locator('#newsletter')).toBeVisible();
  await hydrated(page, '#nav-shoes');
  // A category (a navigation: its filters and grid bring theirs), then a product.
  await page.locator('#nav-shoes').click();
  await expect(page.locator('#grid')).toBeVisible();
  await hydrated(page, '#grid .card-link');
  await page.locator('#grid .card-link').first().click();
  await expect(page.locator('#product-name')).toBeVisible();
  await hydrated(page, '#add');
  await page.locator('#add').click();
  await expect(page.locator('#cart-button')).toHaveText('Cart (1)');
  // The drawer (a portal), then the cart's page, and a quantity changed (its totals refetched).
  await page.locator('#cart-button').click();
  await expect(page.locator('#cart-drawer')).toBeVisible();
  await page.locator('#drawer-cart-link').click();
  await expect(page.locator('#cart-lines')).toBeVisible();
  const subtotal = await page.locator('#summary-subtotal').textContent();
  const more = page.locator('#cart-lines button[id^="more-"]').first();
  // Enough of it in stock for one more.
  const sku = (await more.getAttribute('id'))!.slice('more-'.length);
  await control(request, 'stock', sku, '10');
  await hydrated(page, `#more-${sku}`);
  await more.click();
  await expect(page.locator('#summary-subtotal')).not.toHaveText(subtotal!);
  await page.waitForTimeout(300);
  expect(await unstyled(page)).toEqual([]);
  // And it was styled: the sheets of what it rendered, each once.
  const hrefs = await page.evaluate(() =>
    [...document.querySelectorAll('link[rel="stylesheet"]')].map((link) =>
      link.getAttribute('href'),
    ),
  );
  expect(hrefs.length).toBeGreaterThan(5);
  expect(new Set(hrefs).size).toBe(hrefs.length);
});
