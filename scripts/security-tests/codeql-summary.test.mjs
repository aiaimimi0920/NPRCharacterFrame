import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(new URL("../summarize_codeql_results.py", import.meta.url));
const privateText = "PRIVATE_MESSAGE_SNIPPET_FLOW_TOKEN";

function result() {
  return {
    ruleId: "js/path-injection",
    message: { text: privateText },
    locations: [{ physicalLocation: {
      artifactLocation: { uri: "src/example.ts", uriBaseId: "%SRCROOT%" },
      region: { startLine: 12, snippet: { text: privateText } },
    } }],
    codeFlows: [{ message: { text: privateText } }],
    partialFingerprints: { secret: privateText },
  };
}

function payload(results = [result()]) {
  return {
    version: "2.1.0",
    runs: [{
      tool: { driver: { name: "CodeQL", rules: [{
        id: "js/path-injection",
        defaultConfiguration: { level: "warning" },
        properties: { "security-severity": "7.8" },
        fullDescription: { text: privateText },
      }] } },
      invocations: [{ executionSuccessful: true }],
      results,
    }],
  };
}

function inventory(documents, { maxResults, prepare } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "loom-codeql-summary-"));
  try {
    documents.forEach((document, index) => fs.writeFileSync(
      path.join(directory, `${index}.sarif`),
      typeof document === "string" ? document : JSON.stringify(document),
    ));
    prepare?.(directory);
    const args = [script, directory];
    if (maxResults !== undefined) args.push("--max-results", String(maxResults));
    const output = spawnSync(process.env.PYTHON || "python3", args, {
      encoding: "utf8", timeout: 10_000, maxBuffer: 1_000_000,
    });
    assert.ifError(output.error);
    assert.equal(output.stderr, "");
    assert.ok(!output.stdout.includes(privateText));
    assert.ok(!output.stdout.includes(directory));
    return { status: output.status, report: JSON.parse(output.stdout) };
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

test("inventory emits only allowed metadata, not source or private scanner details", () => {
  const { status, report } = inventory([payload()]);
  assert.equal(status, 0);
  assert.equal(report.analysis_complete, true);
  assert.equal(report.inventory_complete, true);
  assert.equal(report.count_kind, "sarif_results_not_github_open_alerts");
  assert.deepEqual(report.results, [{
    rule_id: "js/path-injection", path: "src/example.ts", line: 12,
    level: "warning", security_severity: "7.8",
  }]);
});

test("counts include all files and runs after the emitted-row cap", () => {
  const document = payload([result(), result()]);
  document.runs.push(payload().runs[0]);
  const { status, report } = inventory([document, payload()], { maxResults: 2 });
  assert.equal(status, 0);
  assert.equal(report.result_count, 4);
  assert.equal(report.file_count, 2);
  assert.equal(report.run_count, 3);
  assert.equal(report.emitted_count, 2);
  assert.equal(report.omitted_count, 2);
  assert.equal(report.truncated, true);
  assert.deepEqual(report.by_rule, [{ rule_id: "js/path-injection", count: 4 }]);
});

test("valid zero and parser warnings remain distinguishable from analysis failures", () => {
  const document = payload([]);
  document.runs[0].invocations[0].toolExecutionNotifications = [
    { level: "warning", message: { text: privateText } },
  ];
  const { status, report } = inventory([document]);
  assert.equal(status, 0);
  assert.equal(report.result_count, 0);
  assert.equal(report.diagnostics.warning_count, 1);
  assert.equal(report.analysis_complete, true);
});

for (const mode of ["failed", "error"]) {
  test(`scanner ${mode} preserves findings but marks analysis incomplete`, () => {
    const document = payload();
    const invocation = document.runs[0].invocations[0];
    if (mode === "failed") invocation.executionSuccessful = false;
    else invocation.toolExecutionNotifications = [{ level: "error", message: { text: privateText } }];
    const { status, report } = inventory([document]);
    assert.equal(status, 2);
    assert.equal(report.error, "analysis_incomplete");
    assert.equal(report.inventory_complete, true);
    assert.equal(report.analysis_complete, false);
    assert.equal(report.result_count, 1);
  });
}

for (const document of ["not JSON", {}, { version: "2.1.0", runs: [] }]) {
  test(`malformed SARIF cannot produce complete zero: ${JSON.stringify(document)}`, () => {
    const { status, report } = inventory([document]);
    assert.equal(status, 2);
    assert.equal(report.inventory_complete, false);
    assert.equal(report.analysis_complete, false);
    assert.equal(report.result_count, undefined);
  });
}

test("missing SARIF files fail closed", () => {
  const { status, report } = inventory([]);
  assert.equal(status, 2);
  assert.equal(report.error, "missing_sarif");
});

for (const uri of ["../secret", "/tmp/secret", "https://host/path", "a?token=secret", "a%2F..%2Fsecret", "a\nsecret"]) {
  test(`unsafe location is rejected: ${JSON.stringify(uri)}`, () => {
    const document = payload();
    document.runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri = uri;
    const { status, report } = inventory([document]);
    assert.equal(status, 2);
    assert.equal(report.error, "invalid_location");
    assert.equal(report.result_count, undefined);
  });
}

test("invalid results after the output cap still invalidate the inventory", () => {
  const document = payload([result(), result()]);
  document.runs[0].results[1].ruleId = privateText;
  const { status, report } = inventory([document], { maxResults: 1 });
  assert.equal(status, 2);
  assert.equal(report.inventory_complete, false);
});

test("indexed artifacts and rule references retain severity", () => {
  const document = payload();
  const run = document.runs[0];
  run.artifacts = [{ location: { uri: "src/indexed.ts", uriBaseId: "%SRCROOT%" } }];
  run.results[0].ruleIndex = 0;
  delete run.results[0].ruleId;
  run.results[0].locations[0].physicalLocation.artifactLocation = { index: 0 };
  const { status, report } = inventory([document]);
  assert.equal(status, 0);
  assert.equal(report.results[0].path, "src/indexed.ts");
  assert.equal(report.results[0].security_severity, "7.8");
});

test("SARIF extension component references use extension rules", () => {
  const document = payload();
  const run = document.runs[0];
  run.tool.extensions = [{ name: "extensions", rules: [{
    id: "rust/path-injection", properties: { "security-severity": "8.1" },
  }] }];
  run.results[0].rule = { index: 0, toolComponent: { index: 0, name: "extensions" } };
  delete run.results[0].ruleId;
  const { status, report } = inventory([document]);
  assert.equal(status, 0);
  assert.equal(report.results[0].rule_id, "rust/path-injection");
  assert.equal(report.results[0].security_severity, "8.1");
});

test("symlink SARIF inputs are rejected", { skip: process.platform === "win32" }, () => {
  const { status, report } = inventory([payload()], { prepare(directory) {
    fs.symlinkSync(path.join(directory, "0.sarif"), path.join(directory, "linked.sarif"));
  } });
  assert.equal(status, 2);
  assert.equal(report.error, "unsafe_input");
});

test("oversized SARIF files are rejected before parsing", () => {
  const { status, report } = inventory([payload()], { prepare(directory) {
    fs.truncateSync(path.join(directory, "0.sarif"), 20 * 1024 * 1024 + 1);
  } });
  assert.equal(status, 2);
  assert.equal(report.error, "input_limit_exceeded");
});

test("workflow preserves full scanning, source coverage and private SARIF boundary", () => {
  const workflow = fs.readFileSync(new URL("../../.github/workflows/codeql.yml", import.meta.url), "utf8");
  for (const required of [
    'CODEQL_ACTION_DIFF_INFORMED_QUERIES: "false"', "queries: security-extended",
    "language: [python, actions]",
    "category: /language:${{ matrix.language }}", "output: .tmp/codeql-results",
    "node --test scripts/security-tests/codeql-summary.test.mjs",
    "python3 scripts/summarize_codeql_results.py .tmp/codeql-results",
    "if: ${{ !cancelled() }}", "security-events: write",
  ]) assert.ok(workflow.includes(required), `missing workflow contract: ${required}`);
  assert.ok(workflow.includes("if-no-files-found: error"));
  assert.ok(!workflow.includes("continue-on-error"));
});
