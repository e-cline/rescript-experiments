import * as assert from 'node:assert';
import * as fs from 'node:fs';
import {before, describe, it} from 'node:test';

void describe('res_tree_shaking example', async () => {
  let fileContents: string;
  before(async () => {
    fileContents = fs.readFileSync('./dist/main.js', {encoding: 'utf-8'});
  });

  void it('strips the isDev-only branch', async () => {
    assert.equal(
      fileContents.indexOf('[env:isDev]') === -1,
      true,
      'Removes the `if (isDev)` branch reached through @e-cline/res_common.',
    );
  });

  void it('retains the isProd-only branch', async () => {
    assert.equal(
      fileContents.indexOf('[env:isProd]') > -1,
      true,
      'Keeps the `if (isProd)` branch reached through @e-cline/res_common.',
    );
  });

  void it('strips the Development case of a switch on Env.jsEnv', async () => {
    assert.equal(
      fileContents.indexOf('[env:jsEnv:Development]') === -1,
      true,
      'Removes the `Development` case of the `switch` on `jsEnv`.',
    );
  });

  void it('retains the Production case of a switch on Env.jsEnv', async () => {
    assert.equal(
      fileContents.indexOf('[env:jsEnv:Production]') > -1,
      true,
      'Keeps the `Production` case of the `switch` on `jsEnv`.',
    );
  });
});
