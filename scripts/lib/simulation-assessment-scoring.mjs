// Assessment scoring derived from a published practice contract (re-defense
// final fix wave: dashboard-server I2, SQL-A I3). Pure functions, no I/O.
//
// The practice contract itself is never changed. The assessment package keeps
// its own snapshot of it (evaluator_config.simulation_definition), and only
// that snapshot is amended:
//   * every check of the mission's FINAL verification test (the testRun
//     phase whose completion requires its own passing result) gets a
//     `counts` key naming the step that owns the state it requires, so a
//     failed final test charges that step once per run (private.
//     simulation_replay). A check whose requirements belong to several steps
//     is split into one check per owning step; the conjunction is unchanged.
//     Diagnostic tests that exist to show the fault (no completion on their
//     result, e.g. coc2_m5_p2, coc3_m3_p2, coc4_m3_p4) get no counts;
//   * decision effects belong to the decide step, config.* to the configure
//     step, settings to the step whose operation sets them, and so on.
// The rubric then gives every decide criterion the condition that its
// decision is one of the choices whose effects satisfy the final checks, and
// configure/interpret criteria with an empty practice completion the final
// checks' requirements on the state they own.

export const DEFAULT_MAX_INCORRECT = 2;

const asMap = (value) => (value && typeof value === "object" && !Array.isArray(value) ? value : {});
const asList = (value) => (Array.isArray(value) ? value : []);
const clone = (value) => JSON.parse(JSON.stringify(value));

/** Canonical JSON (sorted keys), for equality of JSON documents. */
export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
const same = (a, b) => canonical(a) === canonical(b);

/**
 * Safety-critical steps outside COC1 M2 (owner decision 7: correct on the
 * first attempt). Each becomes its own criterion with max_incorrect 0 whose
 * counted targets are only the safety actions and the failed final-test
 * checks of the safety state ("safety:<phase>"). The step criterion keeps
 * the standard threshold for the rest of the step. Identified from the
 * contracts: ESD protection, PPE and power isolation (spec WS2, SQL-A triage
 * of A1 M6). COC1 M2's ESD (C1) and CPU orientation (C3) are in
 * COC1_M2_CRITERIA of the publisher.
 */
export const SAFETY_STEPS = {
  coc1_m1: [{
    phase: "coc1_m1_p2",
    title: "ESD protection and a de-energized safe work set",
    reason: "The anti-static strap goes on the bare chassis ground point, and the safe-work set records ESD controls and excludes energized servicing (check safe_work).",
    conditions: [
      { path: "tool.chassis_ground", value: "anti_static_strap" },
      { path: "selection.coc1_m1_p2", operator: "set_equals", value: ["esd_protection", "open_memory_latch"] },
    ],
    targets: ["tool:chassis_ground"],
    checks: ["safe_work"],
  }],
  coc2_m2: [{
    phase: "coc2_m2_p1",
    title: "PPE and ESD protection prepared before cable work",
    reason: "The work-order check records PPE and ESD protection (field ppe_prepared) before termination. No final check examines it, so the final state must show it prepared.",
    conditions: [{ path: "config.ppe_prepared", value: true }],
    targets: [],
    checks: [],
  }],
  coc4_m4: [{
    phase: "coc4_m4_p1",
    title: "Power isolated and ESD-safe tool used before removal",
    reason: "The repair order starts with \"Disconnect power and prepare ESD protection\" before the adapter is removed, with the ESD-safe screwdriver on the retaining screw (check hardware: safe repair chronology).",
    conditions: [
      { path: "tool.retaining_screw", value: "esd_driver" },
      { path: "sequence.coc4_m4_p1", value: true },
    ],
    targets: ["tool:retaining_screw", "phase:coc4_m4_p1"],
    checks: ["hardware"],
  }],
  coc4_m5: [{
    phase: "coc4_m5_p2",
    title: "Damaged USB port isolated before software maintenance",
    reason: "The decision must isolate the damaged USB port before software changes (final check \"Safety priority\").",
    conditions: [{ path: "decision.coc4_m5_p2", operator: "one_of", value: ["service_verified_faults"] }],
    targets: ["phase:coc4_m5_p2"],
    checks: ["priority"],
  }],
};

/**
 * Steps whose correct value cannot be derived from the snapshot. A decide,
 * configure or interpret step that gets no derived condition must be listed
 * here, so a contract change cannot silently drop a check.
 */
export const NO_DERIVABLE_CONDITION = {
  coc2_m4_p4: "Interpretation is free text; the replay records only that it was made.",
  coc3_m1_p2: "Neither choice has an equipment effect and no final check reads the decision.",
  coc3_m4_p5: "Interpretation is free text; the replay records only that it was made.",
  coc4_m2_p3: "Interpretation is free text; the replay records only that it was made.",
  coc4_m3_p3: "Interpretation is free text; the replay records only that it was made.",
  coc4_m3_p5: "Interpretation is free text; the replay records only that it was made.",
  coc4_m5_p3: "A single choice (open_service_console); no final check reads its effect.",
};

/** Mirrors public.practice_conditions_met for state built in this module. */
export function conditionsMet(conditions, state) {
  for (const condition of asList(conditions)) {
    const actual = state[condition.path];
    const wanted = condition.value;
    const operator = condition.operator ?? "equals";
    let valid;
    if (operator === "present") valid = actual !== undefined && actual !== null && actual !== false && actual !== "" && !(Array.isArray(actual) && actual.length === 0);
    else if (operator === "contains") valid = Array.isArray(actual) && actual.some((item) => same(item, wanted));
    else if (operator === "set_equals") valid = Array.isArray(actual) && Array.isArray(wanted) && wanted.every((w) => actual.some((a) => same(a, w))) && actual.every((a) => wanted.some((w) => same(a, w)));
    else if (operator === "one_of") valid = Array.isArray(wanted) && actual !== undefined && wanted.some((w) => same(w, actual));
    else if (operator === "not_equals") valid = actual !== undefined && actual !== null && !same(actual, wanted);
    else if (operator === "minimum") valid = /^[0-9]+(\.[0-9]+)?$/.test(String(actual ?? "")) && Number(actual) >= Number(wanted);
    else valid = actual !== undefined && same(actual, wanted);
    if (!valid) return false;
  }
  return true;
}

const placementPanel = (phase) => (phase.primaryInteraction === "place" ? asMap(phase.presentation) : asMap(asMap(asMap(phase.presentation).equipment).placement));
const connectionPanel = (phase) => (phase.primaryInteraction === "connect" ? asMap(phase.presentation) : asMap(asMap(asMap(phase.presentation).equipment).connection));
const configurationFields = (phase) => {
  const presentation = asMap(phase.presentation);
  return asList(asMap(asMap(presentation.equipment).configuration).fields ?? presentation.fields);
};
const toolTargets = (phase) => {
  const presentation = asMap(phase.presentation);
  return asList(asMap(presentation.equipment).targets ?? presentation.targets);
};
const testTarget = (phase) => asMap(phase.presentation).target ?? phase.id;

/** The testRun phase whose completion requires its own passing result. */
export function finalVerificationPhase(definition) {
  const phases = asList(definition.phases);
  const verifying = phases.filter((phase) => phase.primaryInteraction === "testRun"
    && asList(asMap(asMap(phase.presentation).equipment).completion)
      .some((condition) => condition.path === `result.${testTarget(phase)}` && condition.value === true));
  return verifying.at(-1) ?? null;
}

/** Every state path a phase's own actions set (see private.simulation_replay). */
function ownedPaths(phase) {
  const presentation = asMap(phase.presentation);
  const equipment = asMap(presentation.equipment);
  const paths = new Set();
  for (const item of asList(placementPanel(phase).items)) {
    paths.add(`placed.${item.id}`);
    for (const key of Object.keys(asMap(item.removal_effects))) paths.add(`setting.${key}`);
  }
  for (const source of asList(connectionPanel(phase).sources)) paths.add(`link.${source.id}>`);
  for (const field of configurationFields(phase)) {
    paths.add(`config.${field.id}`);
    // configuration_applied sets setting.service_running from service_control.
    if (field.id === "service_control") paths.add("setting.service_running");
  }
  for (const operation of asList(equipment.operations)) {
    paths.add(`operation.${operation.id}`);
    for (const key of Object.keys(asMap(operation.effects))) paths.add(`setting.${key}`);
  }
  if (Array.isArray(presentation.choices)) {
    paths.add(`decision.${phase.id}`);
    for (const choice of presentation.choices) {
      for (const key of Object.keys(asMap(choice.equipment_effects))) paths.add(`setting.${key}`);
    }
  }
  for (const target of toolTargets(phase)) paths.add(`tool.${target.id}`);
  for (const action of asList(presentation.diagnostic_actions)) paths.add(`fact.${action.reveals_fact_id}`);
  if (presentation.test_reveals_fact_id) paths.add(`fact.${presentation.test_reveals_fact_id}`);
  for (const object of asList(presentation.objects)) paths.add(`inspected.${object.id}`);
  for (const condition of asList(equipment.completion)) {
    if (String(condition.path).startsWith("inspected.")) paths.add(condition.path);
  }
  for (const group of asList(equipment.selection_groups)) paths.add(`classification.${group.id}`);
  if (phase.primaryInteraction === "select") paths.add(`selection.${phase.id}`);
  if (phase.primaryInteraction === "sequence") { paths.add(`sequence.${phase.id}`); paths.add(`order.${phase.id}`); }
  paths.add(`observation.${phase.id}`);
  paths.add(`interpretation.${phase.id}`);
  if (phase.primaryInteraction === "testRun") paths.add(`result.${testTarget(phase)}`);
  return paths;
}

/**
 * The step that owns a requirement's state: the last owning phase up to the
 * final test, preferring a configure step for config.* (a test phase that
 * repeats the fields only offers the correction).
 */
export function ownerOf(path, phases, limitIndex) {
  const candidates = phases.slice(0, limitIndex + 1).filter((phase) => {
    const owned = ownedPaths(phase);
    if (owned.has(path)) return true;
    return path.startsWith("link.") && owned.has(`${path.slice(0, path.indexOf(">") + 1)}`);
  });
  if (!candidates.length) return null;
  if (path.startsWith("config.")) {
    const configure = candidates.filter((phase) => phase.primaryInteraction === "configure");
    if (configure.length) return configure.at(-1).id;
  }
  return candidates.at(-1).id;
}

const safetyFor = (missionCode, phaseId) => asList(SAFETY_STEPS[missionCode]).find((step) => step.phase === phaseId) ?? null;

/**
 * The amended snapshot, the counts key of each final check and the state
 * each step owns in the final checks.
 */
export function assessmentScoring(missionCode, definition) {
  const snapshot = clone(definition);
  const phases = asList(snapshot.phases);
  const final = finalVerificationPhase(snapshot);
  const result = { snapshot, finalPhaseId: final?.id ?? null, injected: [], ownedRequirements: new Map(), keysByPhase: new Map() };
  if (!final) return result;
  const finalIndex = phases.findIndex((phase) => phase.id === final.id);
  const equipment = asMap(asMap(final.presentation).equipment);
  const checks = [];
  for (const check of asList(equipment.checks)) {
    if (typeof check.counts === "string") { checks.push(check); continue; } // declared by the contract (COC1 M2)
    const groups = new Map();
    for (const requirement of asList(check.requires)) {
      const owner = ownerOf(requirement.path, phases, finalIndex);
      if (!owner) throw new Error(`${missionCode}: no step owns ${requirement.path} (final check ${check.id})`);
      groups.set(owner, [...(groups.get(owner) ?? []), requirement]);
    }
    const entries = [...groups];
    for (const [owner, requires] of entries) {
      const safety = safetyFor(missionCode, owner)?.checks.includes(check.id);
      const key = `${safety ? "safety" : "step"}:${owner}`;
      const part = entries.length === 1
        ? { ...check, counts: key }
        : { ...check, id: `${check.id}.${owner}`, split_from: check.id, requires, counts: key };
      checks.push(part);
      result.injected.push({ check: part.id, counts: key, requires: requires.map((requirement) => requirement.path) });
      result.ownedRequirements.set(owner, [...(result.ownedRequirements.get(owner) ?? []), ...requires]);
      result.keysByPhase.set(owner, new Set([...(result.keysByPhase.get(owner) ?? []), key]));
    }
  }
  equipment.checks = checks;
  return result;
}

/** decision.<phase> one_of the choices whose effects satisfy the final checks. */
export function correctChoices(phase, ownedRequirements) {
  const choices = asList(asMap(phase.presentation).choices);
  const effectKeys = new Set(choices.flatMap((choice) => Object.keys(asMap(choice.equipment_effects)).map((key) => `setting.${key}`)));
  const decisionRequirements = asList(ownedRequirements)
    .filter((requirement) => requirement.path === `decision.${phase.id}` || effectKeys.has(requirement.path));
  if (!decisionRequirements.length || choices.length < 2) return null;
  const correct = choices.filter((choice) => conditionsMet(decisionRequirements, {
    [`decision.${phase.id}`]: choice.id,
    ...Object.fromEntries(Object.entries(asMap(choice.equipment_effects)).map(([key, value]) => [`setting.${key}`, value])),
  })).map((choice) => choice.id);
  if (!correct.length) throw new Error(`${phase.id}: no choice satisfies the final checks`);
  return correct.length === choices.length ? null : correct;
}

/** Conditions a step criterion adds to its practice completion. */
export function derivedConditions(phase, ownedRequirements) {
  const family = phase.primaryInteraction;
  if (family === "decide") {
    const correct = correctChoices(phase, ownedRequirements);
    return correct ? [{ path: `decision.${phase.id}`, operator: "one_of", value: correct }] : [];
  }
  const completion = asList(asMap(asMap(phase.presentation).equipment).completion);
  if ((family === "configure" || family === "interpret") && !completion.length) return clone(asList(ownedRequirements));
  return [];
}
