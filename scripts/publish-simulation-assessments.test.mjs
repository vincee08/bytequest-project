// Shape of the generated simulation assessment packages (final fix wave:
// dashboard-server I2 safety thresholds, SQL-A I3 final-test counts and
// decision conditions). Runs without a database: the published practice
// contracts are read from the migrations that write them.
// Run: node --test scripts/publish-simulation-assessments.test.mjs
// (also part of `corepack pnpm test` in ByteQuest-Web-Dashboard).
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  COC1_M2_CRITERIA,
  SAFETY_STEPS,
  TESDA_SOURCE,
  buildSimulationPackage,
  parseArgs,
  validateSimulationPackages,
  verifiedSourceDigest,
} from "./publish-simulation-assessments.mjs";
import { canonical } from "./lib/simulation-assessment-scoring.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONTRACT_MIGRATIONS = [
  "20261009091000_css_practice_contracts.sql",
  "20261011043723_css_drag_workspace_contracts.sql",
  "20261109120000_coc1_m1_identification_contract.sql",
  "20261119110200_coc1_m2_assembly_contract.sql",
];

/** The contracts as the migrations leave them (later writes replace earlier ones). */
function publishedContracts() {
  const contracts = {};
  const row = /\('(coc[1-4]_m[1-5])',\s*'([^']+)',\s*'((?:[^']|'')*)'::jsonb\)/g;
  for (const file of CONTRACT_MIGRATIONS) {
    const sql = fs.readFileSync(path.join(ROOT, "supabase", "migrations", file), "utf8");
    for (const match of sql.matchAll(row)) {
      contracts[match[1]] = { version: match[2], definition: JSON.parse(match[3].replaceAll("''", "'")) };
    }
  }
  return contracts;
}

const contracts = publishedContracts();
const link = { moduleId: "00000000-0000-4000-8000-000000000001", moduleCode: "LO0.0", moduleTitle: "Test module", pcCodes: ["1.1"] };
const build = (mission) => buildSimulationPackage({ missionCode: mission, contract: structuredClone(contracts[mission]), link });
const packages = Object.keys(contracts).sort().map(build);
const byMission = new Map(packages.map((item) => [item.missionCode, item]));
const criterion = (mission, code) => byMission.get(mission).criteria.find((item) => item.criterion_code === code);
const phaseOf = (definition, id) => definition.phases.find((phase) => phase.id === id);
const checksOf = (definition, id) => phaseOf(definition, id).presentation.equipment.checks;
const decisionOf = (mission, code) => criterion(mission, code).evidence_rule.conditions.find((condition) => condition.path.startsWith("decision."));

test("the migrations publish all 20 practice contracts and every package validates", () => {
  assert.equal(Object.keys(contracts).length, 20);
  assert.equal(contracts.coc1_m2.version, "css-assembly-20261119-v3");
  assert.equal(contracts.coc1_m1.version, "css-sag-20261109-v3");
  const result = validateSimulationPackages(packages);
  assert.equal(result.missions, 20);
});

test("safety-critical steps allow no incorrect attempt in every mission (owner decision 7)", () => {
  const expected = { coc1_m1: "COC1_M1_S2_SAFETY", coc2_m2: "COC2_M2_S1_SAFETY", coc4_m4: "COC4_M4_S1_SAFETY", coc4_m5: "COC4_M5_S2_SAFETY" };
  assert.deepEqual(Object.keys(SAFETY_STEPS).sort(), Object.keys(expected).sort());
  for (const [mission, code] of Object.entries(expected)) {
    const safety = criterion(mission, code);
    assert.ok(safety, `${code} exists`);
    assert.equal(safety.evidence_rule.max_incorrect, 0);
    assert.deepEqual(safety.evidence_rule.phase_ids, [SAFETY_STEPS[mission][0].phase]);
  }
  assert.deepEqual(criterion("coc1_m1", "COC1_M1_S2_SAFETY").evidence_rule.counted_targets, ["tool:chassis_ground", "safety:coc1_m1_p2"]);
  assert.deepEqual(criterion("coc4_m4", "COC4_M4_S1_SAFETY").evidence_rule.counted_targets, ["tool:retaining_screw", "phase:coc4_m4_p1", "safety:coc4_m4_p1"]);
  assert.deepEqual(criterion("coc4_m5", "COC4_M5_S2_SAFETY").evidence_rule.counted_targets, ["phase:coc4_m5_p2", "safety:coc4_m5_p2"]);
  assert.deepEqual(criterion("coc2_m2", "COC2_M2_S1_SAFETY").evidence_rule.conditions, [{ path: "config.ppe_prepared", value: true }]);
  for (const code of ["COC1_M2_C1", "COC1_M2_C3"]) assert.equal(criterion("coc1_m2", code).evidence_rule.max_incorrect, 0);
  // Every other criterion keeps the standard threshold of two.
  const zero = packages.flatMap((item) => item.criteria.filter((c) => c.evidence_rule.max_incorrect === 0).map((c) => c.criterion_code)).sort();
  assert.deepEqual(zero, [...Object.values(expected), "COC1_M2_C1", "COC1_M2_C3"].sort());
  assert.ok(packages.every((item) => item.criteria.every((c) => [0, 2].includes(c.evidence_rule.max_incorrect))));
});

test("only the final verification test is amended; diagnostic tests and the contract are untouched", () => {
  for (const item of packages) {
    const source = contracts[item.missionCode].definition;
    assert.equal(canonical(item.sourceDefinition), canonical(source), `${item.missionCode}: the input contract is not mutated`);
    const snapshot = item.evaluatorConfig.simulation_definition;
    for (const phase of source.phases) {
      if (phase.id === item.scoring.finalPhaseId) continue;
      assert.equal(canonical(phaseOf(snapshot, phase.id)), canonical(phase), `${phase.id} is unchanged`);
    }
  }
  for (const [mission, phase] of [["coc2_m5", "coc2_m5_p2"], ["coc3_m3", "coc3_m3_p2"], ["coc4_m3", "coc4_m3_p4"], ["coc2_m3", "coc2_m3_p3"], ["coc2_m4", "coc2_m4_p3"]]) {
    const checks = checksOf(byMission.get(mission).evaluatorConfig.simulation_definition, phase);
    assert.ok(checks.every((check) => check.counts === undefined), `${phase} (a test that shows the fault) charges nothing`);
  }
  assert.equal(byMission.get("coc4_m3").scoring.finalPhaseId, null, "COC4 M3 has no final verification test");
  assert.deepEqual(byMission.get("coc4_m3").scoring.injected, []);
});

test("COC1 M2 (the demo assessment) keeps exactly its published package", () => {
  const item = byMission.get("coc1_m2");
  assert.equal(canonical(item.evaluatorConfig.simulation_definition), canonical(contracts.coc1_m2.definition));
  assert.deepEqual(item.criteria.map((c) => c.criterion_code), COC1_M2_CRITERIA.map((spec) => spec.code));
  assert.match(item.evaluatorConfig.threshold_rule, /once per failed power-on test, a failing check of the step/);
});

test("COC4 M2: retests charge the repair decision, which must be the supported repair", () => {
  const item = byMission.get("coc4_m2");
  const checks = checksOf(item.evaluatorConfig.simulation_definition, "coc4_m2_p5");
  const counts = Object.fromEntries(checks.map((check) => [check.id, check.counts]));
  assert.deepEqual(counts, { health: "step:coc4_m2_p4", "close_out.coc4_m2_p5": "step:coc4_m2_p5", "close_out.coc4_m2_p1": "step:coc4_m2_p1" });
  // Split checks keep the original conjunction of requirements.
  const original = checksOf(contracts.coc4_m2.definition, "coc4_m2_p5").flatMap((check) => check.requires.map(canonical)).sort();
  assert.deepEqual(checks.flatMap((check) => check.requires.map(canonical)).sort(), original);
  const s4 = criterion("coc4_m2", "COC4_M2_S4").evidence_rule;
  assert.deepEqual(decisionOf("coc4_m2", "COC4_M2_S4"), { path: "decision.coc4_m2_p4", operator: "one_of", value: ["replace_storage"] });
  assert.ok(s4.counted_targets.includes("step:coc4_m2_p4") && s4.counted_targets.includes("phase:coc4_m2_p4"));
  assert.equal(s4.max_incorrect, 2);
  assert.ok(criterion("coc4_m2", "COC4_M2_S1").evidence_rule.counted_targets.includes("step:coc4_m2_p1"));
});

test("every decide step requires the decision the final checks support", () => {
  const expected = {
    COC1_M5_S4: ["replace_storage_cable"], COC2_M3_S4: ["replace_link_segment"], COC3_M1_S3: ["file_service"],
    COC3_M2_S3: ["restart_after_configuration"], COC3_M5_S4: ["restore_support_membership"], COC4_M1_S3: ["prioritize_network_path"],
    COC4_M1_S4: ["preliminary_network_path"], COC4_M2_S4: ["replace_storage"], COC4_M5_S2: ["service_verified_faults"],
  };
  for (const [code, value] of Object.entries(expected)) {
    const mission = code.slice(0, 7).toLowerCase();
    assert.deepEqual(decisionOf(mission, code)?.value, value, code);
  }
  // The listed exceptions have nothing to derive.
  assert.equal(decisionOf("coc3_m1", "COC3_M1_S2"), undefined);
  assert.equal(decisionOf("coc4_m5", "COC4_M5_S3"), undefined);
});

test("configure steps without a practice completion require the state the final checks expect", () => {
  const conditions = (mission, code) => criterion(mission, code).evidence_rule.conditions;
  assert.deepEqual(conditions("coc2_m4", "COC2_M4_S2").filter((c) => c.path === "config.interface_address" || c.path === "config.wireless_security"),
    [{ path: "config.interface_address", value: "192.168.10.2" }, { path: "config.wireless_security", value: "wpa2_aes" }]);
  assert.deepEqual(conditions("coc3_m4", "COC3_M4_S3"), [{ path: "setting.service_running", value: true }]);
  assert.ok(conditions("coc3_m3", "COC3_M3_S4").some((c) => c.path === "setting.user_folder_ready" && c.value === true));
  assert.ok(conditions("coc4_m4", "COC4_M4_S3").some((c) => c.path === "config.device_identifier" && c.operator === "present"));
});

test("the scoring assertions reject a weakened package", () => {
  const weakened = (mutate) => {
    const copy = packages.map((item) => ({ ...item, criteria: structuredClone(item.criteria), evaluatorConfig: structuredClone(item.evaluatorConfig) }));
    mutate(new Map(copy.map((item) => [item.missionCode, item])));
    return () => validateSimulationPackages(copy);
  };
  assert.throws(weakened((map) => { map.get("coc1_m1").criteria.find((c) => c.criterion_code === "COC1_M1_S2_SAFETY").evidence_rule.max_incorrect = 2; }), /safety-critical/);
  assert.throws(weakened((map) => { map.get("coc1_m2").criteria.find((c) => c.criterion_code === "COC1_M2_C3").evidence_rule.max_incorrect = 2; }), /COC1_M2_C3/);
  assert.throws(weakened((map) => {
    checksOf(map.get("coc2_m5").evaluatorConfig.simulation_definition, "coc2_m5_p2")[0].counts = "step:coc2_m5_p1";
  }), /diagnostic test must not be amended/);
  assert.throws(weakened((map) => {
    const s4 = map.get("coc4_m2").criteria.find((c) => c.criterion_code === "COC4_M2_S4");
    s4.evidence_rule.conditions = s4.evidence_rule.conditions.filter((c) => !c.path.startsWith("decision."));
  }), /coc4_m2_p4 \(decide\) requires no correct state/);
  assert.throws(weakened((map) => {
    delete checksOf(map.get("coc4_m2").evaluatorConfig.simulation_definition, "coc4_m2_p5")[0].counts;
  }), /charges no step/);
});

test("publisher arguments keep their guards", () => {
  assert.throws(() => parseArgs(["--target", "hosted"]), /requires --confirm/);
  assert.throws(() => parseArgs(["--contracts", "x.json"]), /only accepted with --dry-run/);
  assert.throws(() => parseArgs(["--emit", "x.json"]), /only accepted with --dry-run/);
  assert.deepEqual(parseArgs(["--dry-run", "--emit", "x.json"]).emit, "x.json");
});

test("the TESDA source digest the notes claim is computed from the repository copy", () => {
  assert.equal(verifiedSourceDigest(ROOT), TESDA_SOURCE.sha256);
});
