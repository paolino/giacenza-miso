// @ts-check
// Playwright config for the giacenza browser smoke.
// reuseExistingServer is FALSE on purpose (audit finding F-1): the
// smoke must drive the server it starts from the freshly built
// public/, never whatever already listens on the port.
export default {
    testDir: ".",
    timeout: 240_000,
    expect: { timeout: 30_000 },
    outputDir: process.env.EVIDENCE_DIR ?? "browser-evidence",
    use: {
        baseURL: "http://localhost:8123",
        headless: true,
    },
    webServer: {
        command: "node scripts/serve.mjs 8123 public",
        cwd: "..",
        url: "http://localhost:8123/index.html",
        reuseExistingServer: false,
        timeout: 30_000,
    },
};
