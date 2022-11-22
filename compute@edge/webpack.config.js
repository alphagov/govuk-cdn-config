import { fileURLToPath } from "url"
import { dirname, resolve } from "path"
import webpack from "webpack"

export default {
  entry: "./src/index.js",
  optimization: {
    minimize: true
  },
  target: "webworker",
  output: {
    filename: "index.js",
    path: resolve(dirname(fileURLToPath(import.meta.url)), "bin"),
    libraryTarget: "this",
  },
  module: {
    // Asset modules are modules that allow the use asset files (fonts, icons, etc) 
    // without additional configuration or dependencies.
    rules: [
      // asset/source exports the source code of the asset. 
      // Usage: e.g., import notFoundPage from "./page_404.html"
      {
        test: /\.(txt|html)/,
        type: "asset/source",
      },
    ],
  },
  plugins: [
    // Polyfills go here.
    // Used for, e.g., any cross-platform WHATWG, 
    // or core nodejs modules needed for your application.
  ],
};
