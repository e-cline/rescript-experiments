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
  await expect(page.locator('[data-id=home-loading]')).toBeVisible();
  await expect(page.locator('[data-id=cart-button]')).toHaveText('Cart (0)');
  await release(request, 'layout:home');
  await expect(page.locator('[data-id=loading-featured]')).toBeVisible();
  await expect(page.locator('[data-id=loading-hero]')).toBeVisible();
  await release(request, 'rail:featured');
  await expect(page.locator('[data-id=carousel-featured]')).toBeVisible();
  await expect(page.locator('[data-id=stock-loading-p1]')).toHaveText(
    'Checking stock…',
  );
  await expect(page.locator('[data-id=loading-hero]')).toBeVisible();
  await release(request, 'stock:p1');
  await expect(page.locator('[data-id=stock-p1]')).toHaveText('In stock');
  await release(request, 'block:hero');
  await expect(page.locator('[data-id=hero-hero] h1')).toHaveText(
    'Made to last',
  );
  await releaseAll(request);
  await expect(page.locator('[data-id=newsletter]')).toBeVisible();
  // One copy of everything, hydrated.
  await hydrated(page, '[data-id=next-featured]');
  await expect(page.locator('[data-id=blocks-home]')).toHaveCount(1);
  await page.locator('[data-id=next-featured]').click();
  await expect(page.locator('[data-id=position-featured]')).toHaveText(
    '5–6 of 6',
  );
});

test("blocks arriving while an entrypoint's chunk is still loading are hydrated once it has, not rendered twice", async ({
  page,
  request,
}) => {
  const releaseTabs = await holdChunk(page, 'Tabs');
  await page.goto('/', {waitUntil: 'commit'});
  await hydrated(page, '[data-id=cart-button]');
  await releaseAll(request);
  await expect(page.locator('[data-id=newsletter]')).toBeVisible();
  await expect(page.locator('[data-id=blocks-home]')).toHaveCount(1);
  releaseTabs();
  await hydrated(page, '[data-id=tabs-tabs-tab-1]');
  await page.locator('[data-id=tabs-tabs-tab-1]').click();
  await expect(page.locator('[data-id=tabs-tabs-panel-1]')).toBeVisible();
  await expect(page.locator('[data-id=tabs-tabs-panel-0]')).toBeHidden();
  await expect(page.locator('[data-id=blocks-home]')).toHaveCount(1);
  await expect(page.locator('[data-id=tabs-tabs]')).toHaveCount(1);
});

test('shopping, start to finish: a filter, a product, a variant, the cart, a promo code, checkout and the order', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await control(request, 'poll', '200');
  await page.goto('/c/shoes');
  await hydrated(page, '[data-id=color-green]');
  await page.locator('[data-id=color-green]').check();
  await expect(page).toHaveURL('/c/shoes?color=green');
  await expect(page.locator('[data-id=result-count]')).toHaveText(
    'Showing 2 of 2',
  );
  await page.locator('[data-id=card-p8] > a').click();
  await expect(page.locator('[data-id=product-name]')).toHaveText(
    'Hiking Boot',
  );
  await expect(page).toHaveURL('/p/hiking-boot');
  await hydrated(page, '[data-id=variant-p8-9]');
  await page.locator('[data-id=variant-p8-9]').click();
  await expect(page.locator('[data-id=stock]')).toHaveText(
    'Size 9: 5 in stock',
  );
  await page.locator('[data-id=add-to-cart] select').selectOption('2');
  await page.locator('[data-id=add]').click();
  await expect(page.locator('[data-id=cart-button]')).toHaveText('Cart (2)');
  await expect(page.locator('[data-id=toasts]')).toContainText(
    'Added 2 × Hiking Boot to your cart',
  );
  // The drawer: a modal dialog, the focus in it.
  await page.locator('[data-id=cart-button]').click();
  await expect(page.locator('[data-id=cart-drawer]')).toBeVisible();
  await expect(page.locator('[data-id=cart-drawer]')).toContainText(
    'Hiking Boot (Size 9) × 2: $338.00',
  );
  await page.locator('[data-id=drawer-cart-link]').click();
  await expect(page.locator('[data-id=cart-title]')).toBeVisible();
  await expect(page.locator('[data-id=cart-drawer]')).toBeHidden();
  await page.locator('[data-id=promo] input').fill('loom20');
  await page.locator('[data-id=apply-promo]').click();
  await expect(page.locator('[data-id=summary-discount]')).toHaveText(
    '-$67.60',
  );
  await expect(page.locator('[data-id=summary-total]')).toHaveText('$270.40');
  await page.locator('[data-id=checkout-link]').click();
  await page.locator('input[name=name]').fill('Ada');
  await page.locator('input[name=street]').fill('1 Loop Lane');
  await page.locator('input[name=city]').fill('Testville');
  await page.locator('input[name=postcode]').fill('12345');
  await page.locator('[data-id=checkout-next]').click();
  await page.locator('[data-id=delivery-express]').check();
  await page.locator('[data-id=checkout-next]').click();
  await expect(page.locator('[data-id=review-total]')).toHaveText(
    'Total: $285.40',
  );
  await page.locator('[data-id=checkout-next]').click();
  await expect(page).toHaveURL('/orders/o1001');
  await expect(page.locator('[data-id=order-status]')).toHaveText(
    'Status: Placed',
  );
  await expect(page.locator('[data-id=cart-button]')).toHaveText('Cart (0)');
  // The order page refreshes itself: the server's newer status comes in.
  await control(request, 'advance', 'o1001');
  await expect(page.locator('[data-id=order-status]')).toHaveText(
    'Status: Packed',
  );
  await control(request, 'advance', 'o1001');
  await control(request, 'advance', 'o1001');
  await expect(page.locator('[data-id=order-status]')).toHaveText(
    'Status: Delivered',
  );
  await expect(page.locator('[data-id=estimate]')).toHaveText('Delivered.');
});

test('the sign-in dialog takes focus, closes on Escape, and signing in personalises the home page', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await page.goto('/');
  await hydrated(page, '[data-id=sign-in]');
  await page.locator('[data-id=sign-in]').click();
  await expect(page.locator('[data-id=signin-dialog]')).toBeVisible();
  await expect(page.locator('[data-id=signin-dialog] input')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(page.locator('[data-id=signin-dialog]')).toBeHidden();
  // Closed, the focus is back on what opened it.
  await expect(page.locator('[data-id=sign-in]')).toBeFocused();
  await page.locator('[data-id=sign-in]').click();
  await page.locator('[data-id=signin-dialog] input').fill('Ada');
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-id=account-menu]')).toContainText('Hi, Ada');
  await expect(page.locator('[data-id=hero-welcome] h1')).toHaveText(
    'Welcome back, Ada',
  );
  await expect(page.locator('[data-id=carousel-for-you]')).toBeVisible();
  // The session is the cookie's: a new page load is still Ada's.
  await page.reload();
  await expect(page.locator('[data-id=hero-welcome] h1')).toHaveText(
    'Welcome back, Ada',
  );
  expect((await page.context().cookies()).map((cookie) => cookie.name)).toEqual(
    ['sid'],
  );
});

test('a link to a page that redirects lands at the URL the redirect leads to, in place', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  const where = () => {
    const url = new URL(page.url());
    return url.pathname + url.search;
  };
  await page.goto('/');
  await hydrated(page, '[data-id=sign-in]');
  await page.locator('[data-id=sign-in]').click();
  await page.locator('[data-id=signin-dialog] input').fill('Ada');
  await page.keyboard.press('Enter');
  await hydrated(page, '[data-id=account-trigger]');
  // Signed out behind the page's back: its account link now redirects to sign in.
  await page.context().clearCookies();
  // Gone if the page loads again: the link should navigate in place.
  await page.evaluate(() => {
    (window as {stayed?: boolean}).stayed = true;
  });
  // The account's link is in the account menu.
  await page.locator('[data-id=account-trigger]').click();
  await page.locator('[data-id=account-link]').click();
  await expect(page.locator('[data-id=signin-page]')).toBeVisible();
  expect(where()).toBe('/signin?next=/account');
  // The history's entry is the one it led to: back is the page before, forward that one again.
  await page.goBack();
  await expect(page.locator('[data-id=signin-page]')).toHaveCount(0);
  expect(where()).toBe('/');
  await page.goForward();
  await expect(page.locator('[data-id=signin-page]')).toBeVisible();
  expect(where()).toBe('/signin?next=/account');
  // Signing in there goes on to the account.
  await hydrated(page, '[data-id=signin-page] input');
  await page.locator('[data-id=signin-page] input').fill('Grace');
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-id=account-title]')).toHaveText(
    "Grace's account",
  );
  expect(where()).toBe('/account');
  // With nothing in the cart, checking out redirects back to it.
  await page.locator('[data-id=cart-button]').click();
  await page.locator('[data-id=drawer-cart-link]').click();
  await hydrated(page, '[data-id=checkout-link]');
  await page.locator('[data-id=checkout-link]').click();
  await expect(page.locator('[data-id=cart-empty]')).toBeVisible();
  await expect(page.locator('[data-id=checkout-title]')).toHaveCount(0);
  expect(where()).toBe('/cart');
  expect(await page.evaluate(() => (window as {stayed?: boolean}).stayed)).toBe(
    true,
  );
});

test('the currency picked changes every price at once, and is the session’s for the next page load', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await page.goto('/c/outerwear');
  await hydrated(page, '[data-id=currency]');
  await expect(page.locator('[data-id=card-p10] data')).toHaveText('$149.00');
  // On sale: the price it was, too.
  await expect(page.locator('[data-id=card-p9] data')).toHaveText(
    '$373.75 $299.00',
  );
  const saved = page.waitForResponse((response) =>
    response.url().endsWith('/_weft/rpc/prefs.setCurrency'),
  );
  await page.locator('[data-id=currency]').selectOption('EUR');
  await expect(page.locator('[data-id=card-p10] data')).toHaveText('€137.08');
  await expect(page.locator('[data-id=card-p9] data')).toHaveText(
    '€343.85 €275.08',
  );
  await saved;
  await page.reload();
  await expect(page.locator('[data-id=card-p10] data')).toHaveText('€137.08');
  await expect(page.locator('[data-id=currency]')).toHaveValue('EUR');
});

test('the back and forward buttons go through filtered pages, and the filters follow', async ({
  page,
  request,
}) => {
  await releaseAll(request);
  await page.goto('/c/bags');
  await hydrated(page, '[data-id=color-black]');
  await page.locator('[data-id=color-black]').check();
  await expect(page).toHaveURL('/c/bags?color=black');
  await expect(page.locator('[data-id=result-count]')).toHaveText(
    'Showing 2 of 2',
  );
  await page.locator('[data-id=sort]').selectOption('price-desc');
  await expect(page).toHaveURL('/c/bags?color=black&sort=price-desc');
  await page.goBack();
  await expect(page).toHaveURL('/c/bags?color=black');
  await expect(page.locator('[data-id=sort]')).toHaveValue('featured');
  await page.goBack();
  await expect(page).toHaveURL('/c/bags');
  await expect(page.locator('[data-id=result-count]')).toHaveText(
    'Showing 4 of 8',
  );
  await expect(page.locator('[data-id=color-black]')).not.toBeChecked();
  await page.goForward();
  await expect(page.locator('[data-id=color-black]')).toBeChecked();
  await expect(page.locator('[data-id=result-count]')).toHaveText(
    'Showing 2 of 2',
  );
});

test('a block whose service fails says so, and Retry fetches it by itself once it’s back', async ({
  page,
  request,
}) => {
  await control(request, 'fail', 'rail:featured');
  await releaseAll(request);
  await page.goto('/');
  // The build sends no error messages: only that the server failed.
  await expect(page.locator('[data-id=block-error-featured]')).toContainText(
    "Couldn't load this: WeftServer: the server failed to render this",
  );
  await expect(page.locator('[data-id=hero-hero]')).toBeVisible();
  await control(request, 'heal', 'rail:featured');
  await release(request, 'rail:featured');
  await hydrated(page, '[data-id=retry-featured]');
  const refetched = page.waitForRequest((sent) =>
    sent.url().endsWith('/blocks/home/featured'),
  );
  await page.locator('[data-id=retry-featured]').click();
  expect((await refetched).headers()['accept']).toBe('text/x-weft-payload');
  await expect(page.locator('[data-id=carousel-featured]')).toBeVisible();
  await expect(page.locator('[data-id=block-error-featured]')).toHaveCount(0);
});

test.describe('with JavaScript off', () => {
  test.use({javaScriptEnabled: false});

  test('the pages are readable: everything the server rendered', async ({
    page,
    request,
  }) => {
    await releaseAll(request);
    await page.goto('/');
    await expect(page.locator('[data-id=hero-hero] h1')).toHaveText(
      'Made to last',
    );
    await expect(
      page.locator('[data-id=carousel-featured] [data-id=card-p1] h3'),
    ).toHaveText('Trail Runner');
    await expect(
      page.locator('[data-id=carousel-featured] [data-id=card-p1] data'),
    ).toHaveText('$129.00');
    await page.goto('/p/trail-runner');
    await expect(page.locator('[data-id=product-name]')).toHaveText(
      'Trail Runner',
    );
    await expect(page.locator('[data-id=stock]')).toHaveText(
      'Size 7: only 1 left',
    );
    await expect(page.locator('[data-id=card-p2]')).toBeVisible();
  });
});
