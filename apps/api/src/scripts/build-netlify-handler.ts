// Bundle src/netlify-handler.ts into one ESM file for the Netlify Function.
//   npm run build:netlify            (writes netlify/build/netlify-handler.mjs)
//
// Why a bundle: Netlify packages `.mts` functions with plain file tracing, so
// dependencies load natively in its Lambda runtime, which cannot `require()` an
// ES module. Fastify's inject dependency (light-my-request) does exactly that
// with the ESM-only `cookie` package. esbuild converts it at build time.
// `pg` stays external: it is CommonJS and has optional native bindings.
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const API_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
export const DEFAULT_OUTFILE = path.join(API_ROOT, "netlify/build/netlify-handler.mjs");

export async function buildNetlifyHandler(outfile = DEFAULT_OUTFILE): Promise<string> {
  await build({
    entryPoints: [path.join(API_ROOT, "src/netlify-handler.ts")],
    outfile,
    bundle: true,
    platform: "node",
    format: "esm",
    target: "node20",
    external: ["pg"],
    // Bundled CommonJS code calls require() for Node built-ins and `pg`.
    banner: {
      js: "import { createRequire as __createRequire } from 'node:module';\n" +
        "const require = __createRequire(import.meta.url);",
    },
    logLevel: "warning",
  });
  return outfile;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const outfile = await buildNetlifyHandler();
  console.log(`wrote ${path.relative(process.cwd(), outfile)}`);
}
