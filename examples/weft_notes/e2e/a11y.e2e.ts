// Accessibility, as axe checks it (WCAG 2.1, A and AA): each page once it's all there, and a comment
// form showing an error. What axe can't (the keyboard, a screen reader's reading) is for the other
// tests, and for people.

import AxeBuilder from '@axe-core/playwright';
import {
  expect,
  test,
  type APIRequestContext,
  type Page,
} from '@playwright/test';

const releaseAll = async (request: APIRequestContext, ...notes: string[]) => {
  for (const note of notes) {
    for (const part of ['body', 'comments', 'related']) {
      await request.post(
        `/test/gates/release/${encodeURIComponent(`${part}:${note}`)}`,
      );
    }
  }
};

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
      `${violation.id} (${violation.impact}): ${violation.nodes.map((node) => node.target.join(' ')).join(', ')}`,
  );
};

test.beforeEach(async ({request}) => {
  await request.post('/test/gates/manual');
});

test('the list of notes has nothing axe finds wrong', async ({page}) => {
  await page.goto('/');
  await expect(page.locator('[data-id=notes]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
});

test("a note's page, all of it in, has nothing axe finds wrong, nor with a comment refused", async ({
  page,
  request,
}) => {
  await releaseAll(request, '1');
  await page.goto('/notes/1');
  await expect(page.locator('[data-id=comment-list]')).toBeVisible();
  await expect(page.locator('[data-id=related]')).toBeVisible();
  await expect(page.locator('[data-id=error-box]')).toBeVisible();
  expect(await violations(page)).toEqual([]);
  await page.waitForFunction(
    () =>
      '$$resFiberProps' in document.querySelector('[data-id=post-comment]')!,
  );
  await page.locator('[data-id=post-comment]').click();
  await expect(page.locator('[data-id=comment-text]')).toHaveAttribute(
    'aria-invalid',
    'true',
  );
  expect(await violations(page)).toEqual([]);
});
