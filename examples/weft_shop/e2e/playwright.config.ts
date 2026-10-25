/// <reference types="node" />
import {fileURLToPath} from 'node:url';

import {defineConfig, devices} from '@playwright/test';

// The browser tests, against the build (`vp run e2e` builds it first), served twice by `serve.mjs`:
// once with its latency gated (`manual`, opened by the tests through the test-only routes), for
// tests that choose the order things arrive in; and once with seeded random latency and failures,
// as `vp run start` serves it, for tests that only say what must happen eventually.
const gated = Number(process.env.WEFT_SHOP_E2E_PORT ?? 4417);
const random = gated + 1;
const cwd = fileURLToPath(new URL('..', import.meta.url));

export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  // One server (and one database) each: the tests take turns.
  workers: 1,
  reporter: process.env.CI ? 'github' : 'list',
  projects: [
    {
      name: 'gated',
      testMatch: ['shop.e2e.ts', 'styles.e2e.ts'],
      use: {...devices['Desktop Chrome'], baseURL: `http://127.0.0.1:${gated}`},
    },
    // When a stylesheet counts as loaded, and when a script runs, differ by engine: the flash test
    // runs in each.
    {
      name: 'gated, Firefox',
      testMatch: 'styles.e2e.ts',
      use: {
        ...devices['Desktop Firefox'],
        baseURL: `http://127.0.0.1:${gated}`,
      },
    },
    {
      name: 'gated, WebKit',
      testMatch: 'styles.e2e.ts',
      use: {...devices['Desktop Safari'], baseURL: `http://127.0.0.1:${gated}`},
    },
    {
      name: 'random latency',
      testMatch: 'random.e2e.ts',
      use: {
        ...devices['Desktop Chrome'],
        baseURL: `http://127.0.0.1:${random}`,
      },
    },
  ],
  webServer: [
    {
      command: 'node serve.mjs',
      cwd,
      url: `http://127.0.0.1:${gated}/test/ready`,
      env: {
        PORT: String(gated),
        WEFT_SHOP_TEST_ROUTES: '1',
        WEFT_SHOP_LATENCY: 'manual',
      },
      reuseExistingServer: false,
    },
    {
      command: 'node serve.mjs',
      cwd,
      url: `http://127.0.0.1:${random}/c/shoes`,
      env: {
        PORT: String(random),
        WEFT_SHOP_LATENCY: 'random',
        WEFT_SHOP_SEED: '7',
        WEFT_SHOP_FAIL_RATE: '0.3',
      },
      reuseExistingServer: false,
    },
  ],
});
