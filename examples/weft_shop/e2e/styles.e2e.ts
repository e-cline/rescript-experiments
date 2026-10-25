// The store's styles in a browser, against the build, with the latency gated and every stylesheet
// slowed down: nothing is ever on screen without its CSS. A probe (every frame, and every task) looks
// at each element with a `weft_css` class (a name ending in a sheet id) and checks the sheet it's in
// has been applied (its link has its `sheet`), while the page streams in, block by block, and as
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

/**
 * Records each element shown with a class whose sheet hasn't been applied: a link's sheet is applied
 * once it's set (the browser has parsed it; its `load` event comes a task later) or the link has
 * fired `load` or `error` (each link is watched from when it's added: one that fails has no sheet).
 * It looks every animation frame and, from the first (once the head's stylesheets, which block
 * rendering, have loaded), after every task too: headless WebKit on Linux runs animation frames
 * rarely, and what's in the document after a task is what the next frame would show. It counts its
 * looks: one that never looked would see nothing.
 */
function probe() {
  const seen: string[] = [];
  const state = window as unknown as {
    __unstyled: string[];
    __looks: number;
    __frames: number;
  };
  state.__unstyled = seen;
  state.__looks = 0;
  state.__frames = 0;
  const settled = new WeakSet<Element>();
  const watch = (link: Element) => {
    const done = () => settled.add(link);
    link.addEventListener('load', done, {once: true});
    link.addEventListener('error', done, {once: true});
  };
  new MutationObserver((records) => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (!(node instanceof Element)) continue;
        if (node.matches('link[rel="stylesheet"]')) watch(node);
        node.querySelectorAll('link[rel="stylesheet"]').forEach(watch);
      }
    }
  }).observe(document, {childList: true, subtree: true});
  const applied = (id: string) =>
    [...document.querySelectorAll('link[rel="stylesheet"]')].some(
      (link) =>
        (link.getAttribute('href') ?? '').includes(id) &&
        ((link as HTMLLinkElement).sheet !== null || settled.has(link)),
    );
  const look = () => {
    state.__looks++;
    for (const element of document.querySelectorAll('[class]')) {
      for (const name of (element.getAttribute('class') ?? '').split(/\s+/)) {
        const id = /_(w[0-9a-z]{6})$/.exec(name)?.[1];
        if (id !== undefined && !applied(id)) {
          const found = `${element.localName}.${name} (${Math.round(performance.now())} ms)`;
          if (seen.length < 50) seen.push(found);
        }
      }
    }
  };
  const everyTask = () => {
    look();
    setTimeout(everyTask, 0);
  };
  const everyFrame = () => {
    if (state.__frames++ === 0) setTimeout(everyTask, 0);
    look();
    requestAnimationFrame(everyFrame);
  };
  requestAnimationFrame(everyFrame);
}

const unstyled = (page: Page) =>
  page.evaluate(() => (window as unknown as {__unstyled: string[]}).__unstyled);

/** How many times the probe has looked, and how many frames there were, as a message. */
const looked = async (page: Page) => {
  const {looks, frames, visibility} = await page.evaluate(() => {
    const state = window as unknown as {__looks: number; __frames: number};
    return {
      looks: state.__looks,
      frames: state.__frames,
      visibility: document.visibilityState,
    };
  });
  return {looks, message: `${looks} looks, ${frames} frames, ${visibility}`};
};

/** Fails unless the probe has looked enough times to have seen anything. */
const expectLooked = async (page: Page) => {
  const {looks, message} = await looked(page);
  expect(looks, message).toBeGreaterThan(5);
};

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
  await expect(page.locator('[data-id=blocks-home]')).toBeVisible();
  // A class whose sheet is added without waiting for it: what Weft never does.
  await page.evaluate(() => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/assets/wzzzzzz-control.css';
    document.head.append(link);
    document
      .querySelector('[data-id=main]')!
      .classList.add('Control-x_wzzzzzz');
  });
  await page.waitForTimeout(200);
  await expectLooked(page);
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
  await expect(page.locator('[data-id=home-loading]')).toBeVisible();
  await release(request, 'layout:home');
  await expect(page.locator('[data-id=loading-featured]')).toBeVisible();
  await release(request, 'rail:featured');
  await expect(page.locator('[data-id=carousel-featured]')).toBeVisible();
  await release(request, 'block:hero');
  await expect(page.locator('[data-id=hero-hero] h1')).toBeVisible();
  await releaseAll(request);
  await expect(page.locator('[data-id=newsletter]')).toBeVisible();
  await hydrated(page, '[data-id=nav-shoes]');
  // A category (a navigation: its filters and grid bring theirs), then a product.
  await page.locator('[data-id=nav-shoes]').click();
  await expect(page.locator('[data-id=grid]')).toBeVisible();
  await hydrated(page, '[data-id=grid] article > a');
  await page.locator('[data-id=grid] article > a').first().click();
  await expect(page.locator('[data-id=product-name]')).toBeVisible();
  await hydrated(page, '[data-id=add]');
  await page.locator('[data-id=add]').click();
  await expect(page.locator('[data-id=cart-button]')).toHaveText('Cart (1)');
  // The drawer (a portal), then the cart's page, and a quantity changed (its totals refetched).
  await page.locator('[data-id=cart-button]').click();
  await expect(page.locator('[data-id=cart-drawer]')).toBeVisible();
  await page.locator('[data-id=drawer-cart-link]').click();
  await expect(page.locator('[data-id=cart-lines]')).toBeVisible();
  const subtotal = await page
    .locator('[data-id=summary-subtotal]')
    .textContent();
  const more = page
    .locator('[data-id=cart-lines] button[data-id^="more-"]')
    .first();
  // Enough of it in stock for one more.
  const sku = (await more.getAttribute('data-id'))!.slice('more-'.length);
  await control(request, 'stock', sku, '10');
  await hydrated(page, `[data-id=more-${sku}]`);
  await more.click();
  await expect(page.locator('[data-id=summary-subtotal]')).not.toHaveText(
    subtotal!,
  );
  await page.waitForTimeout(300);
  await expectLooked(page);
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
