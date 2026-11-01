import assert from "node:assert/strict";
import { test } from "node:test";
import { registerProjectTrustNotice } from "../src/project_trust_extension.mjs";

for (const { name, trusted, argv, notices } of [
  { name: "a trusted folder", trusted: true, argv: [], notices: 0 },
  { name: "an untrusted folder", trusted: false, argv: [], notices: 1 },
  { name: "--no-approve", trusted: false, argv: ["--approve", "-na"], notices: 0 },
  { name: "a Pi without a trust gate", trusted: undefined, argv: [], notices: 0 },
]) {
  test(`sends ${notices} trust notice per session for ${name}`, async () => {
    const sent = [];
    const ctx = {
      cwd: "/repo",
      ...(trusted === undefined ? {} : { isProjectTrusted: () => trusted }),
      ui: { notify: (message, level) => sent.push([message, level]) },
    };
    // Pi reruns extension factories on session replacement.
    for (const _session of [1, 2]) {
      let hook;
      registerProjectTrustNotice({ on: (event, handler) => { if (event === "before_agent_start") hook = handler; } }, ["node", "pi", ...argv]);
      for (const _turn of [1, 2]) await hook({}, ctx);
    }
    assert.equal(sent.length, notices * 2);
    for (const [message, level] of sent) {
      assert.match(message, /for \/repo because the folder is not trusted/);
      assert.equal(level, "warning");
    }
  });
}
