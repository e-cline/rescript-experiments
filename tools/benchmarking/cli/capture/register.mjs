// Loaded with `node --import` into every benchmark process `res-bench` starts.
// It installs `hooks.mjs`, which hands the benchmark bundle `mitata.mjs` in
// place of mitata itself.
import {register} from 'node:module';

register('./hooks.mjs', import.meta.url);
