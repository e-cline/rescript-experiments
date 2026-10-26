// Accessibility, as axe checks it (WCAG 2.1, A and AA): each page once it's all there (every gate
// open), the overlays while they're open (the sign-in dialog, the cart's drawer, the account menu,
// the search's suggestions), and the checkout at each step, refusing one. What axe can't (the
// keyboard, a screen reader's reading) is for the other tests, and for people.

import AxeBuilder from '@axe-core/playwright';
import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from '@playwright/test';

const control = (request: APIRequestContext, ...path: string[]) =>
  request.post(`/test/${path.map(encodeURIComponent).join('/')}`);

const hydrated = (page: Page, selector: string) =>
  page.waitForFunction((selector) => {
    const element = document.querySelector(selector);
    return element !== null && '$$resFiberProps' in element;
  }, selector);

/** What axe finds wrong on the page, each as its rule, impact and the elements it's on. */
const violations = async (page: Page) => {
  // As it's seen: once what's animating in (a dialog, a toast) has finished, not halfway faded
  // (what animates for ever, a spinner, aside).
  await page.waitForFunction(() =>
    document
      .getAnimations()
      .every(
        (animation) =>
          animation.playState !== 'running' ||
          animation.effect?.getTiming().iterations === Infinity,
      ),
  );
  const results = await new AxeBuilder({page})
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze();
  return results.violations.map(
    (violation) =>
      `${violation.id} (${violation.impact}): ${violation.nodes
        .map((node) => {
          // For contrast, what axe measured.
          const data = node.any[0]?.data as
            | {fgColor?: string; bgColor?: string; contrastRatio?: number}
            | undefined;
          const measured = data?.fgColor
            ? ` [${data.fgColor} on ${data.bgColor}: ${data.contrastRatio}]`
            : '';
          return node.target.join(' ') + measured;
        })
        .join(', ')}`,
  );
};

test.beforeEach(async ({request}) => {
  await control(request, 'reset');
  await control(request, 'release-all');
});

test('the home, a category, a product and the not-found page have nothing axe finds wrong', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.locator('[data-id=newsletter]')).toBeVisible();
  await expect(page.locator('[aria-busy="true"]')).toHaveCount(0);
  expect(await violations(page)).toEqual([]);
  await page.goto('/c/shoes');
  await expect(page.locator('[data-id=grid]')).toBeVisible();
  await expect(page.locator('[data-id=facets]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.goto('/p/trail-runner');
  await expect(page.locator('[data-id=questions]')).toBeVisible();
  await expect(page.locator('[data-id=review-list]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.goto('/c/hats');
  await expect(page.locator('[data-id=not-found]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
});

test('the overlays, open, have nothing axe finds wrong', async ({page}) => {
  await page.goto('/p/trail-runner');
  await expect(page.locator('[data-id=questions]')).toBeVisible();
  await hydrated(page, '[data-id=add]');
  // The drawer, with a line in it.
  await page.locator('[data-id=add]').click();
  await expect(page.locator('[data-id=cart-button]')).toHaveText('Cart (1)');
  await page.locator('[data-id=cart-button]').click();
  await expect(page.locator('[data-id=cart-drawer]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.keyboard.press('Escape');
  // The search's suggestions.
  await page.locator('[data-id=search-input]').fill('bo');
  await expect(page.locator('[role=listbox]')).toBeVisible();
  await page.keyboard.press('ArrowDown');
  expect(await violations(page)).toEqual([]);
  await page.keyboard.press('Escape');
  // The sign-in dialog, refusing an empty name.
  await page.locator('[data-id=sign-in]').click();
  await expect(page.locator('[data-id=signin-dialog]')).toBeVisible();
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-id=signin-dialog] input')).toHaveAttribute(
    'aria-invalid',
    'true',
  );
  expect(await violations(page)).toEqual([]);
  // Signed in, the account menu.
  await page.locator('[data-id=signin-dialog] input').fill('Ada');
  await page.keyboard.press('Enter');
  await hydrated(page, '[data-id=account-trigger]');
  await page.locator('[data-id=account-trigger]').click();
  await expect(page.locator('[data-id=account-link]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
});

test('the cart, the checkout at each step, an order and the account have nothing axe finds wrong', async ({
  page,
}) => {
  await page.goto('/p/trail-runner');
  await hydrated(page, '[data-id=add]');
  await page.locator('[data-id=add]').click();
  await expect(page.locator('[data-id=cart-button]')).toHaveText('Cart (1)');
  await page.goto('/cart');
  await expect(page.locator('[data-id=cart-lines]')).toBeVisible();
  await expect(page.locator('[data-id=summary]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.goto('/checkout');
  await hydrated(page, '[data-id=checkout-next]');
  // Continuing with nothing filled in: the address is refused.
  await page.locator('[data-id=checkout-next]').click();
  await expect(page.locator('[data-id=checkout-error]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.locator('input[name=name]').fill('Ada');
  await page.locator('input[name=street]').fill('1 Loop Lane');
  await page.locator('input[name=city]').fill('Testville');
  await page.locator('input[name=postcode]').fill('12345');
  await page.locator('[data-id=checkout-next]').click();
  await expect(page.locator('[data-id=delivery-step]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.locator('[data-id=checkout-next]').click();
  await expect(page.locator('[data-id=review-step]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.locator('[data-id=checkout-next]').click();
  await expect(page.locator('[data-id=order-status]')).toBeVisible();
  await expect(page.locator('[data-id=estimate]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.goto('/signin?next=/account');
  await expect(page.locator('[data-id=signin-page]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await hydrated(page, '[data-id=signin-page] input');
  await page.locator('[data-id=signin-page] input').fill('Ada');
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-id=account-title]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
});
