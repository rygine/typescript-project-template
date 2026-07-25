import { defineConfig } from "tsdown";

export default defineConfig({
  entry: ["src/index.ts"],
  format: "esm",
  fixedExtension: false,
  // This is an application, not a library — nothing imports dist/, so there
  // are no declarations worth emitting. Turn this on if that changes, and add
  // "types"/"exports"/"files" to package.json alongside it.
  dts: false,
  sourcemap: true,
});
