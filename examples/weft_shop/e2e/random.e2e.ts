// The build as `vp run start` serves it: every service waits a random time (seeded, so a run can be
// repeated), and the recommendations and questions fail now and then. These tests say only what
// must happen eventually, whatever order things arrive in: every page streams in completely, with
// one copy of everything and nothing in the console, and a shopper can buy something, retrying
// whatever fails.

import {expect, test, type Page} from '@playwright/test';

/** What the console says that it shouldn't: errors and warnings. */
let complaints: string[] = [];

test.beforeEach(({page}) => {
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

/** Waits until nothing on the page is still loading (no fallback, skeleton or pending stock). */
const streamedIn = (page: Page) =>
  expect(page.locator('.loading, .skeleton, .stock.loading')).toHaveCount(0, {
    timeout: 15_000,
  });

/** Clicks Retry on every block that failed, until none has. */
const retryFailures = async (page: Page) => {
  for (let tries = 0; tries < 20; tries++) {
    const failed = page.locator('.block-error button');
    if ((await failed.count()) === 0) return;
    await failed.first().click();
    await page.waitForTimeout(300);
    await streamedIn(page);
  }
  throw new Error('a block kept failing');
};

for (const url of [
  '/',
  '/c/shoes',
  '/c/home?sort=price-asc',
  '/search?q=wool',
  '/p/down-parka',
  '/cart',
]) {
  test(`${url} streams in completely, once, and hydrates`, async ({page}) => {
    await page.goto(url, {waitUntil: 'commit'});
    await streamedIn(page);
    await retryFailures(page);
    await expect(page.locator('#main')).toHaveCount(1);
    await expect(page.locator('#header')).toHaveCount(1);
    // Hydrated: the header's search box answers.
    await page.waitForFunction(
      () => '$$resFiberProps' in document.querySelector('#search-input')!,
    );
  });
}

test('navigating quickly through pages still streaming lands on the last, complete', async ({
  page,
}) => {
  await page.goto('/');
  await page.waitForFunction(
    () => '$$resFiberProps' in document.querySelector('#nav-shoes')!,
  );
  // Each click before the page before has finished streaming.
  await page.locator('#nav-shoes').click();
  await page.locator('#nav-outerwear').click();
  await page.locator('#nav-bags').click();
  await expect(page).toHaveURL('/c/bags');
  await expect(page.locator('#hero-bags-hero h1')).toHaveText('Bags');
  await streamedIn(page);
  await expect(page.locator('#grid .card-name').first()).toHaveText(
    'Weekender',
  );
  await expect(page.locator('#blocks-c-bags')).toHaveCount(1);
});

test('a shopper can find something, buy it, and see the order, whatever fails along the way', async ({
  page,
}) => {
  await page.goto('/');
  await page.waitForFunction(
    () => '$$resFiberProps' in document.querySelector('#search-input')!,
  );
  await page.locator('#search-input').fill('blanket');
  await page.locator('#suggestion-wool-blanket').click();
  await expect(page.locator('#product-name')).toHaveText('Wool Blanket');
  await streamedIn(page);
  await retryFailures(page);
  await page.waitForFunction(
    () => '$$resFiberProps' in document.querySelector('#variant-p26-lg')!,
  );
  await page.locator('#variant-p26-lg').click();
  await expect(page.locator('#stock')).toContainText('Large');
  await expect(page.locator('#offer-price')).toHaveText('$159.00');
  await page.locator('#add').click();
  await expect(page.locator('#cart-button')).toHaveText('Cart (1)');
  await page.locator('#cart-button').click();
  await page.locator('#drawer-cart-link').click();
  await expect(page.locator('#summary-total')).toHaveText('$159.00', {
    timeout: 15_000,
  });
  await page.locator('#checkout-link').click();
  await page.locator('input[name=name]').fill('Grace');
  await page.locator('input[name=street]').fill('2 Loop Lane');
  await page.locator('input[name=city]').fill('Testville');
  await page.locator('input[name=postcode]').fill('54321');
  await page.locator('#checkout-next').click();
  await page.locator('#checkout-next').click();
  await page.locator('#checkout-next').click();
  await expect(page.locator('#order-title')).toContainText('Order o');
  await expect(page.locator('#cart-button')).toHaveText('Cart (0)');
  // The order moves on by itself (by the clock, here), and the page follows.
  await expect(page.locator('#order-status')).toHaveText('Status: Packed', {
    timeout: 15_000,
  });
});
