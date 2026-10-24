// What only a browser can show, against the build, with the latency gated (the tests open the
// gates through the server's test-only routes): real HTML streaming and parsing, real chunk
// loading, portals, focus, cookies, the history, and the page with JavaScript off. Everything that
// can be checked without a browser is, in `tests/` (through the plugin's harness).

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

/**
 * Waits until the bootstrap has hydrated the element `selector` matches (it has its props): a
 * click before then does nothing.
 */
const hydrated = (page: Page, selector: string) =>
  page.waitForFunction((selector) => {
    const element = document.querySelector(selector);
    return element !== null && '$$resFiberProps' in element;
  }, selector);

/** Holds the requests for the chunk whose file name starts with `name` until the function it returns is called. */
const holdChunk = async (page: Page, name: string) => {
  let releaseChunk!: () => void;
  const held = new Promise<void>((resolve) => {
    releaseChunk = resolve;
  });
  await page.route(
    new RegExp(`/assets/${name}\\.res-[^/]*\\.js$`),
    async (route) => {
      await held;
      await route.continue();
    },
  );
  return releaseChunk;
};

/** What the console says that it shouldn't: errors and warnings. */
let complaints: string[] = [];

test.beforeEach(async ({page, request}) => {
  // Every gate closed, and the store as it started.
  await control(request, 'reset');
  complaints = [];
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning') {
      complaints.push(message.text());
    }
  });
  page.on('pageerror', (error) => complaints.push(String(error)));
});

test.afterEach(() => {
  expect(complaints).toEqual([]);
});

test('the home page streams: the shell, then the layout, then each block as its service answers', async ({
  page,
  request,
}) => {
  // Not waiting for `load`: the page is still streaming, so it hasn't loaded.
  await page.goto('/', {waitUntil: 'commit'});
  await expect(page.locator('#home-loading')).toBeVisible();
  await expect(page.locator('#cart-button')).toHaveText('Cart (0)');
  await release(request, 'layout:home');
  await expect(page.locator('#loading-featured')).toBeVisible();
  await expect(page.locator('#loading-hero')).toBeVisible();
  await release(request, 'rail:featured');
  await expect(page.locator('#carousel-featured')).toBeVisible();
  await expect(page.locator('#stock-loading-p1')).toHaveText('Checking stock…');
  await expect(page.locator('#loading-hero')).toBeVisible();
  await release(request, 'stock:p1');
  await expect(page.locator('#stock-p1')).toHaveText('In stock');
  await release(request, 'block:hero');
  await expect(page.locator('#hero-hero h1')).toHaveText('Made to last');
  await releaseAll(request);
  await expect(page.locator('#newsletter')).toBeVisible();
  // One copy of everything, hydrated.
  await hydrated(page, '#next-featured');
  await expect(page.locator('#blocks-home')).toHaveCount(1);
  await page.locator('#next-featured').click();
  await expect(page.locator('#position-featured')).toHaveText('5–6 of 6');
});

test("blocks arriving while an entrypoint's chunk is still loading are hydrated once it has, not rendered twice", async ({
  page,
  request,
}) => {
  const releaseTabs = await holdChunk(page, 'Tabs');
  await page.goto('/', {waitUntil: 'commit'});
  await hydrated(page, '#cart-button');
  await releaseAll(request);
  await expect(page.locator('#newsletter')).toBeVisible();
  await expect(page.locator('#blocks-home')).toHaveCount(1);
  releaseTabs();
  await hydrated(page, '#tabs-tabs-tab-1');
  await page.locator('#tabs-tabs-tab-1').click();
  await expect(page.locator('#tabs-tabs-panel-1')).toBeVisible();
  await expect(page.locator('#tabs-tabs-panel-0')).toBeHidden();
  await expect(page.locator('#blocks-home')).toHaveCount(1);
  await expect(page.locator('#tabs-tabs')).toHaveCount(1);
});

test('shopping, start to finish: a filter, a product, a variant, the cart, a promo code, checkout and the order', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await control(request, 'poll', '200');
  await page.goto('/c/shoes');
  await hydrated(page, '#color-green');
  await page.locator('#color-green').check();
  await expect(page).toHaveURL('/c/shoes?color=green');
  await expect(page.locator('#result-count')).toHaveText('Showing 2 of 2');
  await page.locator('#card-p8 .card-link').click();
  await expect(page.locator('#product-name')).toHaveText('Hiking Boot');
  await expect(page).toHaveURL('/p/hiking-boot');
  await hydrated(page, '#variant-p8-9');
  await page.locator('#variant-p8-9').click();
  await expect(page.locator('#stock')).toHaveText('Size 9: 5 in stock');
  await page.locator('#add-to-cart select').selectOption('2');
  await page.locator('#add').click();
  await expect(page.locator('#cart-button')).toHaveText('Cart (2)');
  await expect(page.locator('#toasts')).toContainText(
    'Added 2 × Hiking Boot to your cart',
  );
  // The drawer, in a portal at the end of the body.
  await page.locator('#cart-button').click();
  await expect(page.locator('body > #cart-drawer')).toContainText(
    'Hiking Boot (Size 9) × 2: $338.00',
  );
  await page.locator('#drawer-cart-link').click();
  await expect(page.locator('#cart-title')).toBeVisible();
  await expect(page.locator('#cart-drawer')).toHaveCount(0);
  await page.locator('.promo-code').fill('loom20');
  await page.locator('#apply-promo').click();
  await expect(page.locator('#summary-discount')).toHaveText('-$67.60');
  await expect(page.locator('#summary-total')).toHaveText('$270.40');
  await page.locator('#checkout-link').click();
  await page.locator('input[name=name]').fill('Ada');
  await page.locator('input[name=street]').fill('1 Loop Lane');
  await page.locator('input[name=city]').fill('Testville');
  await page.locator('input[name=postcode]').fill('12345');
  await page.locator('#checkout-next').click();
  await page.locator('#delivery-express').check();
  await page.locator('#checkout-next').click();
  await expect(page.locator('#review-total')).toHaveText('Total: $285.40');
  await page.locator('#checkout-next').click();
  await expect(page).toHaveURL('/orders/o1001');
  await expect(page.locator('#order-status')).toHaveText('Status: Placed');
  await expect(page.locator('#cart-button')).toHaveText('Cart (0)');
  // The order page refreshes itself: the server's newer status comes in.
  await control(request, 'advance', 'o1001');
  await expect(page.locator('#order-status')).toHaveText('Status: Packed');
  await control(request, 'advance', 'o1001');
  await control(request, 'advance', 'o1001');
  await expect(page.locator('#order-status')).toHaveText('Status: Delivered');
  await expect(page.locator('#estimate')).toHaveText('Delivered.');
});

test('the sign-in dialog takes focus, closes on Escape, and signing in personalises the home page', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await page.goto('/');
  await hydrated(page, '#sign-in');
  await page.locator('#sign-in').click();
  await expect(
    page.locator('body > #signin-overlay #signin-dialog'),
  ).toBeVisible();
  await expect(page.locator('#signin-dialog .signin-name')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(page.locator('#signin-dialog')).toHaveCount(0);
  await page.locator('#sign-in').click();
  await page.locator('#signin-dialog .signin-name').fill('Ada');
  await page.keyboard.press('Enter');
  await expect(page.locator('#account-menu')).toContainText('Hi, Ada');
  await expect(page.locator('#hero-welcome h1')).toHaveText(
    'Welcome back, Ada',
  );
  await expect(page.locator('#carousel-for-you')).toBeVisible();
  // The session is the cookie's: a new page load is still Ada's.
  await page.reload();
  await expect(page.locator('#hero-welcome h1')).toHaveText(
    'Welcome back, Ada',
  );
  expect((await page.context().cookies()).map((cookie) => cookie.name)).toEqual(
    ['sid'],
  );
});

test('the currency picked changes every price at once, and is the session’s for the next page load', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await page.goto('/c/outerwear');
  await hydrated(page, '#currency');
  await expect(page.locator('#card-p10 .price')).toHaveText('$149.00');
  // On sale: the price it was, too.
  await expect(page.locator('#card-p9 .price')).toHaveText('$373.75 $299.00');
  const saved = page.waitForResponse((response) =>
    response.url().endsWith('/_weft/rpc/prefs.setCurrency'),
  );
  await page.locator('#currency').selectOption('EUR');
  await expect(page.locator('#card-p10 .price')).toHaveText('€137.08');
  await expect(page.locator('#card-p9 .price')).toHaveText('€343.85 €275.08');
  await saved;
  await page.reload();
  await expect(page.locator('#card-p10 .price')).toHaveText('€137.08');
  await expect(page.locator('#currency')).toHaveValue('EUR');
});

test('the back and forward buttons go through filtered pages, and the filters follow', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await page.goto('/c/bags');
  await hydrated(page, '#color-black');
  await page.locator('#color-black').check();
  await expect(page).toHaveURL('/c/bags?color=black');
  await expect(page.locator('#result-count')).toHaveText('Showing 2 of 2');
  await page.locator('#sort').selectOption('price-desc');
  await expect(page).toHaveURL('/c/bags?color=black&sort=price-desc');
  await page.goBack();
  await expect(page).toHaveURL('/c/bags?color=black');
  await expect(page.locator('#sort')).toHaveValue('featured');
  await page.goBack();
  await expect(page).toHaveURL('/c/bags');
  await expect(page.locator('#result-count')).toHaveText('Showing 4 of 8');
  await expect(page.locator('#color-black')).not.toBeChecked();
  await page.goForward();
  await expect(page.locator('#color-black')).toBeChecked();
  await expect(page.locator('#result-count')).toHaveText('Showing 2 of 2');
});

test('a block whose service fails says so, and Retry fetches it by itself once it’s back', async ({
  page,
  request,
}) => {
  await control(request, 'fail', 'rail:featured');
  await releaseAll(request);
  await page.goto('/');
  // The build sends no error messages: only that the server failed.
  await expect(page.locator('#block-error-featured')).toContainText(
    "Couldn't load this: WeftServer: the server failed to render this",
  );
  await expect(page.locator('#hero-hero')).toBeVisible();
  await control(request, 'heal', 'rail:featured');
  await release(request, 'rail:featured');
  await hydrated(page, '#retry-featured');
  const refetched = page.waitForRequest((sent) =>
    sent.url().endsWith('/blocks/home/featured'),
  );
  await page.locator('#retry-featured').click();
  expect((await refetched).headers()['accept']).toBe('text/x-weft-payload');
  await expect(page.locator('#carousel-featured')).toBeVisible();
  await expect(page.locator('#block-error-featured')).toHaveCount(0);
});

test.describe('with JavaScript off', () => {
  test.use({javaScriptEnabled: false});

  test('the pages are readable: everything the server rendered', async ({
    page,
    request,
  }) => {
    await releaseAll(request);
    await page.goto('/');
    await expect(page.locator('#hero-hero h1')).toHaveText('Made to last');
    await expect(
      page.locator('#carousel-featured #card-p1 .card-name'),
    ).toHaveText('Trail Runner');
    await expect(page.locator('#carousel-featured #card-p1 .price')).toHaveText(
      '$129.00',
    );
    await page.goto('/p/trail-runner');
    await expect(page.locator('#product-name')).toHaveText('Trail Runner');
    await expect(page.locator('#stock')).toHaveText('Size 7: only 1 left');
    await expect(page.locator('#card-p2')).toBeVisible();
  });
});
