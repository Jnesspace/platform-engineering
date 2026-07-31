/**
 * Leak regression tests: each case plants a canary behind a known leak vector
 * and asserts it never reaches the stub Anthropic API (or the logs / custom
 * input, depending on the vector). Run with smoke.mjs via: npm test
 *
 * Children are spawned async — the stub server lives in this process, so a
 * synchronous spawn would deadlock it.
 */
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const agent = join(dirname(fileURLToPath(import.meta.url)), "..", "agent.mjs");
const workdir = mkdtempSync(join(tmpdir(), "infra-review-leak-"));
const planPath = join(workdir, "plan.json");

const PASS = { verdict: "pass", summary: "fine", findings: [] };
const bodies = [];
const responseQueue = [];

const server = createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    bodies.push(body);
    const next = responseQueue.shift() ?? { status: 200, payload: PASS };
    res.writeHead(next.status, { "content-type": "application/json" });
    res.end(next.status === 200 ? JSON.stringify({ content: [{ type: "text", text: JSON.stringify(next.payload) }] }) : next.body);
  });
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

const baseEnv = {
  ...process.env,
  ANTHROPIC_API_KEY: "test-key",
  ANTHROPIC_BASE_URL: `http://127.0.0.1:${port}`,
  TF_VAR_spacelift_run_type: "PROPOSED",
};

const run = (plan, extraEnv = {}) => {
  writeFileSync(planPath, JSON.stringify(plan));
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [agent, planPath], { env: { ...baseEnv, ...extraEnv }, cwd: workdir });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (c) => (stdout += c));
    child.stderr.on("data", (c) => (stderr += c));
    child.on("error", reject);
    child.on("close", (code) => resolve({ status: code, stdout, stderr }));
  });
};

const rc = (address, type, change) => ({ address, type, name: address.split(".").pop(), change });

// Case 1 — sensitivity masks: after_sensitive redacts `result` (denylisted
// anyway) AND a generically-named field (masks only); planned_values
// sensitive_values and sensitive_attributes paths are honored too.
{
  const r = await run({
    resource_changes: [
      rc("random_password.this", "random_password", {
        actions: ["create"],
        before: null,
        after: { length: 16, result: "CANARY_MASK_RESULT", connection_name: "CANARY_MASK_GENERIC" },
        after_sensitive: { length: false, result: true, connection_name: true },
      }),
    ],
    planned_values: {
      root_module: {
        resources: [
          { address: "random_password.this", values: { endpoint: "CANARY_MASK_PV" }, sensitive_values: { endpoint: true } },
          {
            address: "module.x.null_resource.y",
            values: { admin: { shared_key: "CANARY_MASK_ATTR" } },
            sensitive_attributes: [[{ type: "get_attr", value: "admin" }, { type: "get_attr", value: "shared_key" }]],
          },
        ],
      },
    },
  });
  assert.equal(r.status, 0, r.stderr);
  for (const canary of ["CANARY_MASK_RESULT", "CANARY_MASK_GENERIC", "CANARY_MASK_PV", "CANARY_MASK_ATTR"]) {
    assert.ok(!bodies.at(-1).includes(canary), `mask canary leaked to the API: ${canary}`);
  }
}

// Case 2 — suffix denylist: azurerm keys redacted even without any mask.
{
  const r = await run({
    resource_changes: [
      rc("azurerm_storage_account.this", "azurerm_storage_account", {
        actions: ["create"],
        before: null,
        after: { name: "st", primary_access_key: "CANARY_AZ_KEY", primary_connection_string: "CANARY_AZ_CS" },
      }),
    ],
  });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(!bodies.at(-1).includes("CANARY_AZ_KEY"), "primary_access_key leaked");
  assert.ok(!bodies.at(-1).includes("CANARY_AZ_CS"), "primary_connection_string leaked");
}

// Case 3 — opaque blob fields: kubernetes_secret_v1 data/binary_data maps,
// including a JSON-string canary nested inside a string value.
{
  const r = await run({
    resource_changes: [
      rc("kubernetes_secret_v1.app", "kubernetes_secret_v1", {
        actions: ["create"],
        before: null,
        after: {
          metadata: [{ name: "app" }],
          data: { config: '{"pw":"CANARY_JSON_STR"}', cert: "CANARY_BASE64==" },
          binary_data: { blob: "CANARY_BINARY" },
        },
      }),
    ],
  });
  assert.equal(r.status, 0, r.stderr);
  for (const canary of ["CANARY_JSON_STR", "CANARY_BASE64", "CANARY_BINARY"]) {
    assert.ok(!bodies.at(-1).includes(canary), `blob canary leaked to the API: ${canary}`);
  }
}

// Case 4 — spec file containment: an absolute path outside the project root
// is rejected and its contents never reach the API; the review still runs.
{
  const outside = mkdtempSync(join(tmpdir(), "infra-review-spec-"));
  writeFileSync(join(outside, "environ-copy.txt"), "SPEC_CANARY_OUTSIDE_ROOT");
  const r = await run({ resource_changes: [] }, { INFRA_REVIEW_SPEC_FILE: join(outside, "environ-copy.txt") });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /spec file .* rejected/);
  assert.ok(!bodies.at(-1).includes("SPEC_CANARY_OUTSIDE_ROOT"), "outside-root spec file reached the API");
}

// Case 5 — API error bodies: a 400 whose body echoes the key and a canary
// must surface nowhere — not stdout, not stderr, not the custom-input file.
{
  responseQueue.push({ status: 400, body: '{"error":{"message":"invalid x-api-key test-key API_ERROR_CANARY"}}' });
  const r = await run({ resource_changes: [] });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Anthropic API 400/);
  for (const leak of ["test-key", "API_ERROR_CANARY"]) {
    assert.ok(!r.stdout.includes(leak), `${leak} in stdout`);
    assert.ok(!r.stderr.includes(leak), `${leak} in stderr`);
  }
  const custom = readFileSync(join(workdir, "infrareview.custom.spacelift.json"), "utf8");
  for (const leak of ["test-key", "API_ERROR_CANARY"]) {
    assert.ok(!custom.includes(leak), `${leak} persisted in custom input`);
  }
}

// Case 6 — base URL policy: http:// to a non-loopback host must refuse to
// send the key, make no request, and still exit 0 in advisory mode.
{
  const before = bodies.length;
  const r = await run({ resource_changes: [] }, { ANTHROPIC_BASE_URL: "http://169.254.169.254:8080" });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /refusing to send the API key/);
  assert.equal(bodies.length, before, "a request was made to a non-https, non-loopback base URL");
}

assert.equal(bodies.length, 5, "expected 5 API calls across cases 1-5");
server.close();
console.log("leak: ok (sensitivity masks, key denylist, blob fields, spec containment, error-body policy, base-url policy)");
