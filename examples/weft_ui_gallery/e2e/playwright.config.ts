import {fileURLToPath} from 'node:url';

import {defineConfig, devices} from '@playwright/test';

// The browser tests: the built gallery, served by `serve.mjs`, in Chromium, Firefox and WebKit
// (weft_ui leans on the platform: `<dialog>`, the Popover API, anchor positioning). `vp run e2e`
// builds it first.
const port = Number(process.env.WEFT_UI_GALLERY_E2E_PORT ?? 4419);

export default defineConfig({
  testDir: '.',
  testMatch: '*.e2e.ts',
  fullyParallel: false,
  workers: 1,
  reporter: process.env.CI ? 'github' : 'list',
  use: {baseURL: `http://127.0.0.1:${port}`},
  projects: [
    {name: 'chromium', use: {...devices['Desktop Chrome']}},
    {name: 'firefox', use: {...devices['Desktop Firefox']}},
    {name: 'webkit', use: {...devices['Desktop Safari']}},
  ],
  webServer: {
    command: 'node serve.mjs',
    cwd: fileURLToPath(new URL('..', import.meta.url)),
    url: `http://127.0.0.1:${port}/`,
    env: {PORT: String(port)},
    reuseExistingServer: false,
  },
});
