/**
 * Smoke test: runs agent.mjs as a child process against a stub Anthropic API.
 * No real API key needed. Run: npm test
 *
 * The stub server lives in THIS process, so the children must be spawned
 * async — a synchronous spawn would block the event loop and the stub could
 * never answer.
 */
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const agent = join(dirname(fileURLToPath(import.meta.url)), "..", "agent.mjs");
const workdir = mkdtempSync(join(tmpdir(), "infra-review-"));
const planPath = join(workdir, "plan.json");

writeFileSync(
  planPath,
  JSON.stringify({
    format_version: "1.2",
    resource_changes: [
      {
        address: "aws_s3_bucket.logs",
        type: "aws_s3_bucket",
        name: "logs",
        change: { actions: ["create"], before: null, after: { bucket: "logs", root_password: "hunter2" } },
      },
    ],
  }),
);

const responses = [
  { verdict: "warn", summary: "one new bucket", findings: [{ severity: "low", title: "untagged bucket", detail: "no tags", remediation: "add tags" }] },
  { verdict: "fail", summary: "world-open ingress", findings: [{ severity: "high", title: "0.0.0.0/0 ingress", detail: "open to the world", remediation: "scope the CIDR" }] },
];
let calls = 0;

const server = createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    try {
      assert.ok(!body.includes("hunter2"), "sensitive plan values must be scrubbed before the API call");
      const payload = responses[Math.min(calls, responses.length - 1)];
      calls += 1;
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ content: [{ type: "text", text: JSON.stringify(payload) }] }));
    } catch (err) {
      res.writeHead(500, { "content-type": "text/plain" });
      res.end(String(err));
    }
  });
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

const baseEnv = {
  ...process.env,
  ANTHROPIC_API_KEY: "test-key",
  ANTHROPIC_BASE_URL: `http://127.0.0.1:${port}`,
  TF_VAR_spacelift_run_type: "PROPOSED",
  INFRA_REVIEW_SPEC: "all buckets must be tagged",
};

const run = (extraEnv = {}) =>
  new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [agent, planPath], {
      env: { ...baseEnv, ...extraEnv },
      cwd: workdir,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (c) => (stdout += c));
    child.stderr.on("data", (c) => (stderr += c));
    child.on("error", reject);
    child.on("close", (code) => resolve({ status: code, stdout, stderr }));
  });

// 1. PR run is reviewed; verdict printed; custom input written for plan policies.
let r = await run();
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /verdict: WARN/);
const custom = JSON.parse(readFileSync(join(workdir, "infrareview.custom.spacelift.json"), "utf8"));
assert.equal(custom.verdict, "warn");
assert.equal(custom.agent, "infra-review");

// 2. TRACKED runs are skipped by default (PR-only gate).
r = await run({ TF_VAR_spacelift_run_type: "TRACKED" });
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /skipping/);

// 3. fail_on=findings turns high-severity findings into a failed hook.
r = await run({ INFRA_REVIEW_FAIL_ON: "findings" });
assert.equal(r.status, 1, r.stderr);
assert.match(r.stdout, /blocking findings/);

// 4. No API key -> advisory skip, exit 0.
r = await run({ ANTHROPIC_API_KEY: "" });
assert.equal(r.status, 0, r.stderr);
assert.match(r.stdout, /ANTHROPIC_API_KEY is not set/);

// The scrub assertion lives in the stub; make sure it actually saw traffic.
assert.equal(calls, 2, "expected exactly two API calls (cases 1 and 3)");

server.close();
console.log("smoke: ok (api call, scrubbing, run-type gate, fail mode, no-key skip)");
