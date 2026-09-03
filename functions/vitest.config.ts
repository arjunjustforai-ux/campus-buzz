import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: false,
    environment: "node",
    testTimeout: 30000,
    hookTimeout: 60000,
    include: ["tests/**/*.test.ts"],
    // Integration + rules suites share one emulator database and the rules suite
    // calls clearFirestore(); never run test files concurrently.
    fileParallelism: false,
  },
});
