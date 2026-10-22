// Types for the plugin's virtual modules. Reference them with
// `/// <reference types="@e-cline/vite_plugin_weft/virtual" />`.

declare module 'virtual:weft/client-references' {
  /** Each entrypoint file's id, and a function importing it. */
  const modules: Record<string, () => Promise<unknown>>;
  export default modules;
  /** The module of the entrypoint file `id`, as `WeftServer.Decoder.make`'s `loadModule` takes. */
  export function loadModule(id: string): Promise<unknown>;
}

declare module 'virtual:weft/client' {
  export {loadModule} from 'virtual:weft/client-references';
  /**
   * Calls `listener` whenever a file only the server uses has changed in development. Returns a
   * function that stops it.
   */
  export function onRefresh(
    listener: (data: {file: string}) => void,
  ): () => void;
}

declare module 'virtual:weft/assets' {
  /** What a page needs to load the client. */
  const assets: {
    /** The module scripts to load, in order: in development, Vite's client and then the bootstrap. */
    scripts: string[];
    /** The chunks the bootstrap imports, for `modulepreload` links. */
    preloads: string[];
    /** The stylesheets the bootstrap imports. */
    styles: string[];
    /** For each entrypoint file, by id: its chunk, then the chunks it imports. */
    entrypoints: Record<string, string[]>;
  };
  export default assets;
}
