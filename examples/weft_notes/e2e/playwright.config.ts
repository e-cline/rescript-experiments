import {fileURLToPath} from 'node:url';

import {defineConfig, devices} from '@playwright/test';

// The browser tests (tier 3 of the plan's tests): the built app, served over HTTP by `serve.mjs`,
// with the test-only routes that open the database's gates. `vp run e2e` builds it first.
const port = Number(process.env.WEFT_NOTES_E2E_PORT ?? 4317);

export default defineConfig({
  testDir: '.',
  testMatch: '*.e2e.ts',
  fullyParallel: false,
  // One server, one database: the tests take turns.
  workers: 1,
  reporter: process.env.CI ? 'github' : 'list',
  use: {baseURL: `http://127.0.0.1:${port}`},
  projects: [{name: 'chromium', use: {...devices['Desktop Chrome']}}],
  webServer: {
    command: 'node serve.mjs',
    cwd: fileURLToPath(new URL('..', import.meta.url)),
    url: `http://127.0.0.1:${port}/`,
    env: {PORT: String(port), WEFT_NOTES_TEST_ROUTES: '1'},
    reuseExistingServer: false,
  },
});
