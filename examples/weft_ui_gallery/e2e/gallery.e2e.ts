// What only a browser can show of weft_ui: axe on every page (WCAG 2.1, A and AA) and on the
// overlays while they're open; modal dialogs, popovers and menus with the keyboard and the focus;
// tabs; the combobox; and where popups are placed. In Chromium, Firefox and WebKit.

import AxeBuilder from '@axe-core/playwright';
import {expect, test, type Page} from '@playwright/test';

/** What axe finds wrong on the page, once what's animating in has finished. */
const violations = async (page: Page) => {
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
      `${violation.id} (${violation.impact}): ${violation.nodes.map((node) => node.target.join(' ')).join(', ')}`,
  );
};

const hydrated = (page: Page, selector: string) =>
  page.waitForFunction((selector) => {
    const element = document.querySelector(selector);
    return element !== null && '$$resFiberProps' in element;
  }, selector);

/** The focused element's `data-id`, label or text. */
const focused = (page: Page) =>
  page.evaluate(() => {
    const element = document.activeElement as HTMLElement | null;
    return (
      element?.dataset.id ??
      element?.getAttribute('aria-label') ??
      element?.textContent?.trim()
    );
  });

/** Where `popup` is, against `trigger`: its gap below it, and its start's offset from the trigger's. */
const placement = (page: Page, trigger: string, popup: string) =>
  page.evaluate(
    ([trigger, popup]) => {
      const a = document.querySelector(trigger)!.getBoundingClientRect();
      const b = document.querySelector(popup)!.getBoundingClientRect();
      return {
        below: Math.round(b.top - a.bottom),
        start: Math.round(b.left - a.left),
      };
    },
    [trigger, popup],
  );

let complaints: string[] = [];

test.beforeEach(async ({page}) => {
  complaints = [];
  page.on('console', (message) => {
    if (message.type() === 'error' || message.type() === 'warning')
      complaints.push(message.text());
  });
  page.on('pageerror', (error) => complaints.push(String(error)));
});

test.afterEach(() => expect(complaints).toEqual([]));

for (const path of [
  '/',
  '/layout',
  '/text',
  '/surfaces',
  '/data',
  '/forms',
  '/overlays',
  '/disclosure',
  '/search',
  '/actions',
]) {
  test(`${path} has nothing axe finds wrong`, async ({page}) => {
    await page.goto(path);
    await expect(page.locator('[data-id=page-title]')).toBeVisible();
    expect(await violations(page)).toEqual([]);
  });
}

test('a dialog is modal, starts in its content, and closes on Escape with the focus back', async ({
  page,
}) => {
  await page.goto('/overlays');
  await hydrated(page, '[data-id=size-guide]');
  await page.locator('[data-id=size-guide]').focus();
  await page.keyboard.press('Enter');
  const dialog = page.locator('dialog[open]');
  await expect(dialog).toBeVisible();
  expect(await dialog.evaluate((element) => element.matches(':modal'))).toBe(
    true,
  );
  expect(await violations(page)).toEqual([]);
  expect(await focused(page)).toBe('Close');
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  expect(await focused(page)).toBe('size-guide');
});

test("an alert dialog starts on Cancel, and a click outside doesn't close it", async ({
  page,
}) => {
  await page.goto('/overlays');
  await hydrated(page, '[data-id=delete-open]');
  await page.locator('[data-id=delete-open]').click();
  await expect(page.locator('[data-id=delete-dialog]')).toBeVisible();
  expect(await focused(page)).toBe('delete-cancel');
  await page.mouse.click(10, 400);
  await expect(page.locator('[data-id=delete-dialog]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.locator('[data-id=delete-confirm]').click();
  await expect(page.locator('[data-id=delete-dialog]')).toBeHidden();
  await expect(page.locator('[data-id=toasts] li')).toContainText(
    'Note deleted',
  );
});

test('a drawer is pinned to the end, its full height, and its backdrop closes it', async ({
  page,
}) => {
  await page.goto('/overlays');
  await hydrated(page, '[data-id=drawer-end]');
  await page.locator('[data-id=drawer-end]').click();
  const drawer = page.locator('dialog[open]');
  await expect(drawer).toBeVisible();
  await page.waitForTimeout(300);
  const box = (await drawer.boundingBox())!;
  const viewport = page.viewportSize()!;
  expect(Math.round(box.x + box.width)).toBe(viewport.width);
  expect(Math.round(box.height)).toBe(viewport.height);
  await page.mouse.click(10, 400);
  await expect(drawer).toHaveCount(0);
  expect(await focused(page)).toBe('drawer-end');
});

test('a popover opens below its trigger, the focus in it, and Escape puts it back', async ({
  page,
}) => {
  await page.goto('/overlays');
  await hydrated(page, '[data-id=popover-open]');
  await page.locator('[data-id=popover-open]').click();
  const popup =
    '#' +
    (await page
      .locator('[data-id=popover-open]')
      .getAttribute('popovertarget'));
  await expect(page.locator(popup)).toBeVisible();
  expect(await placement(page, '[data-id=popover-open]', popup)).toEqual({
    below: 4,
    start: 4,
  });
  expect(await violations(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await expect(page.locator(popup)).toBeHidden();
  expect(await focused(page)).toBe('popover-open');
});

test('a menu: ArrowDown opens it on the first item, the arrows skip a disabled one, a letter jumps, Enter chooses', async ({
  page,
}) => {
  await page.goto('/overlays');
  await hydrated(page, '[data-id=menu-open]');
  await page.locator('[data-id=menu-open]').focus();
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-id=menu]')).toBeVisible();
  expect(await focused(page)).toBe('menu-account');
  expect(await violations(page)).toEqual([]);
  await page.keyboard.press('ArrowDown');
  expect(await focused(page)).toBe('Orders');
  await page.keyboard.press('ArrowDown');
  expect(await focused(page)).toBe('Light');
  await page.keyboard.press('s');
  expect(await focused(page)).toBe('menu-sign-out');
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-id=menu-last]')).toHaveText(
    'Chose: Sign out',
  );
  await expect(page.locator('[data-id=menu]')).toBeHidden();
  expect(await focused(page)).toBe('menu-open');
});

test('a tooltip shows on focus, describing its trigger, and Escape hides it', async ({
  page,
}) => {
  await page.goto('/overlays');
  await hydrated(page, '[data-id=tooltip-trigger]');
  await page.locator('[data-id=tooltip-trigger]').focus();
  const tooltip = page.locator('[role=tooltip]', {hasText: 'Saves a copy'});
  await expect(tooltip).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.keyboard.press('Escape');
  await expect(tooltip).toBeHidden();
});

test('tabs: the arrows move and select, Tab goes into the panel; manual tabs wait for Enter', async ({
  page,
}) => {
  await page.goto('/disclosure');
  await hydrated(page, '[data-id=product-tabs-tab-0]');
  await page.locator('[data-id=product-tabs-tab-0]').focus();
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('[data-id=product-tabs-panel-1]')).toBeVisible();
  await page.keyboard.press('Tab');
  expect(
    await page.evaluate(() => document.activeElement?.getAttribute('role')),
  ).toBe('tabpanel');
  await page.getByRole('tab', {name: 'Profile'}).click();
  await page.keyboard.press('ArrowDown');
  await expect(page.getByRole('tab', {name: 'Notifications'})).toBeFocused();
  await expect(page.getByRole('tab', {name: 'Notifications'})).toHaveAttribute(
    'aria-selected',
    'false',
  );
  await page.keyboard.press('ArrowDown');
  await expect(page.getByRole('tab', {name: 'Security'})).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('tab', {name: 'Security'})).toHaveAttribute(
    'aria-selected',
    'true',
  );
});

test("an accordion's items are exclusive", async ({page}) => {
  await page.goto('/disclosure');
  await page.locator('[data-id=faq] summary').nth(1).click();
  expect(
    await page
      .locator('[data-id=faq] details')
      .evaluateAll((items) =>
        items.map((item) => (item as HTMLDetailsElement).open),
      ),
  ).toEqual([false, true, false]);
});

test('a combobox: its popup under the input, the arrows highlighting with the focus kept, Enter choosing', async ({
  page,
}) => {
  await page.goto('/search');
  await hydrated(page, '[data-id=fruit]');
  await page.locator('[data-id=fruit]').click();
  await page.keyboard.type('an');
  await expect(page.locator('[data-id=fruit-list]')).toBeVisible();
  await expect(page.locator('[data-id=fruit]')).toHaveAttribute(
    'aria-expanded',
    'true',
  );
  expect(
    await placement(page, '[data-id=fruit]', '[data-id=fruit-list]'),
  ).toEqual({below: 4, start: 4});
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-id=fruit]')).toBeFocused();
  const active = await page
    .locator('[data-id=fruit]')
    .getAttribute('aria-activedescendant');
  await expect(page.locator(`[id="${active}"]`)).toContainText('Mango');
  expect(await violations(page)).toEqual([]);
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-id=fruit-chosen]')).toHaveText(
    'Chose: mango',
  );
  await expect(page.locator('[data-id=fruit]')).toHaveValue('Mango');
  await expect(page.locator('[data-id=fruit]')).toHaveAttribute(
    'aria-expanded',
    'false',
  );
});
