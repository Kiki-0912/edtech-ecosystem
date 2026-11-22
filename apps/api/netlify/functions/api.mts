// Netlify Function (v2) serving the whole Fastify API on every path.
// The handler is an esbuild bundle produced by `npm run build:netlify`
// (the Netlify build command runs it); its source is src/netlify-handler.ts.
export { default } from "../build/netlify-handler.mjs";

export const config = {
  path: ["/", "/*"],
};
