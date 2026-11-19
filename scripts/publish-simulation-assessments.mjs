// Publishes one simulation-based assessment activity per practice mission
// (owner decision 4: Practice and Assessment share the 2D simulation; the
// assessment is evaluated on the server by replaying the attempt evidence).
//
// For each of the 20 missions it ensures, idempotently:
//   * a published activity version: delivery_mode 'assessment',
//     learner_payload {mission_id, definition_version, mode:'assessment'}
//     (no simulation_template, so the app opens MissionSimulationScreen in
//     assessment mode) and evaluator_config {simulation_definition} holding a
//     snapshot of the published practice contract;
//   * an approved binary_sum / all_required rubric whose criteria are the
//     mission's steps, each a `simulation_condition` evidence rule with the
//     owner-approved threshold (2 incorrect attempts; 0 for safety-critical
//     steps), traced to the curriculum module and performance criteria;
//   * an activity_curriculum_links row (delivery_kind 'simulation').
// Outside COC1 M2 (whose contract declares its own POST charges) the
// snapshot's final verification checks get `counts` keyed to the step that
// owns the state they require, decide criteria require the correct decision,
// configure/interpret criteria with no practice completion require the state
// the final checks expect, and the ESD, PPE and power-isolation steps get
// their own zero-tolerance criterion (scripts/lib/simulation-assessment-
// scoring.mjs). The practice contract itself is never changed.
// It also links every existing form-based package to its module
// ('form_based'; the protected COC2 cable package 'protected_reference').
// A freshly reset database has no TESDA source yet: the official ELCCSS213
// source is then registered, approved and activated through the governed
// RPCs first (production already has it active, so nothing changes there).
// Published versions are immutable: a database that already holds a
// different package for the same contract version is reported, never edited.
//
// Usage (service role; local stack by default):
//   node scripts/publish-simulation-assessments.mjs [--dry-run [--emit <file.json>]] [--contracts <file.json>]
//   node scripts/publish-simulation-assessments.mjs --target hosted --confirm
// Environment: NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY (or
// NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY), SUPABASE_SERVICE_ROLE_KEY and
// BYTEQUEST_E2E_PASSWORD (temporary governance principal, retired at the end).
// --dry-run builds and validates every package without writing (including
// the scoring assertions) and prints what was derived per mission; with
// --contracts it reads {mission_id: {version, definition}} from a file instead
// of the database (offline validation); --emit writes the packages to a file.
import fs from "node:fs";
import path from "node:path";
import { createHash, randomUUID } from "node:crypto";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  DEFAULT_MAX_INCORRECT,
  NO_DERIVABLE_CONDITION,
  SAFETY_STEPS,
  assessmentScoring,
  canonical,
  derivedConditions,
  finalVerificationPhase,
  ownerOf,
} from "./lib/simulation-assessment-scoring.mjs";

export { DEFAULT_MAX_INCORRECT, SAFETY_STEPS };

const SOURCE_NOTE =
  "TR Computer Systems Servicing NC II (Amended December 2013); ByteQuest supplementary simulation assessment, not an official TESDA certification.";
// Same official source as scripts/publish-coc2-reference-assessment.mjs.
export const TESDA_SOURCE = {
  qualificationCode: "ELCCSS213",
  title: "Training Regulations: Computer Systems Servicing NC II",
  edition: "Amended December 2013",
  reference: "https://tesda.gov.ph/Downloadables/TRs/TR%20Computer%20Systems%20Servicing%20NC%20II%20.pdf",
  sha256: "42D85DAD87D0566B8B965AC0868E0F92E6CBB4C578028EFF648DB21BE421D147",
  // The repository copy of that PDF; its digest is computed before any
  // validation note claims it (demo-data review m3).
  localCopy: "docs/reference/tesda_sources/TR_current.pdf",
};

/** SHA-256 of the repository copy of the official PDF; throws when it differs. */
export function verifiedSourceDigest(root = fileURLToPath(new URL("..", import.meta.url))) {
  const digest = createHash("sha256").update(fs.readFileSync(path.join(root, TESDA_SOURCE.localCopy))).digest("hex").toUpperCase();
  if (digest !== TESDA_SOURCE.sha256) {
    throw new Error(`${TESDA_SOURCE.localCopy} has SHA-256 ${digest}, not the recorded ${TESDA_SOURCE.sha256}; the source cannot be registered as verified.`);
  }
  return digest;
}
const BINARY_RULE = {
  status: "APPROVED",
  method: "binary",
  satisfied_value: 1,
  not_satisfied_value: 0,
  classification: "TECHNICAL_BINARY_ENCODING",
  note: "1/0 encodes SATISFIED/NOT SATISFIED only; it is not a TESDA percentage or criterion weight.",
};
const eq = (path, value) => ({ path, value });
const present = (path) => ({ path, operator: "present" });

/**
 * COC1 M2 assembly bench: eleven step criteria (re-defense brief, owner
 * decision 7). Safety-critical steps (ESD, CPU orientation) allow no
 * incorrect attempt. BIOS configuration is not performed, so C11 traces PC
 * 1.4 only. Each "step:" key is the charge a failed power-on test adds to
 * that step (the "counts" of its POST checks, once per run).
 */
export const COC1_M2_CRITERIA = [
  {
    code: "COC1_M2_C1", title: "ESD protection and work area prepared", phases: ["coc1_m2_p1"],
    conditions: [eq("operation.wear_wrist_strap", true), eq("operation.ground_wrist_strap", true)],
    counted: ["operation:wear_wrist_strap", "operation:ground_wrist_strap"], max: 0, pcs: ["1.1"], safety: true,
  },
  {
    code: "COC1_M2_C2", title: "Parts inspected before assembly", phases: ["coc1_m2_p1"],
    conditions: ["system_case", "motherboard", "cpu", "cooler", "ram", "psu", "storage"].map((part) => eq(`inspected.${part}`, true)),
    counted: ["phase:coc1_m2_p1"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.2", "1.3"],
  },
  {
    code: "COC1_M2_C3", title: "CPU seated in the correct orientation with the lever closed", phases: ["coc1_m2_p2"],
    conditions: [eq("placed.cpu", "cpu_socket"), eq("setting.cpu_lever", "closed")],
    counted: ["item:cpu", "operation:open_cpu_lever", "operation:close_cpu_lever", "step:cpu"], max: 0, pcs: ["1.4"], safety: true,
  },
  {
    code: "COC1_M2_C4", title: "Thermal compound, cooler and CPU_FAN connected", phases: ["coc1_m2_p2"],
    conditions: [eq("setting.thermal_compound", true), eq("placed.cooler", "cooler_mount"), eq("link.cooler_fan>cpu_fan_header", true)],
    counted: ["operation:apply_thermal_compound", "item:cooler", "connection:cooler_fan", "step:cooling"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
  {
    code: "COC1_M2_C5", title: "Memory in DIMM_A2 and DIMM_B2 with latches locked", phases: ["coc1_m2_p2"],
    conditions: [
      { path: "placed.ram_1", operator: "one_of", value: ["dimm_a2", "dimm_b2"] },
      { path: "placed.ram_2", operator: "one_of", value: ["dimm_a2", "dimm_b2"] },
      eq("setting.dimm_latches", "closed"),
    ],
    counted: ["item:ram_1", "item:ram_2", "operation:open_dimm_latches", "operation:close_dimm_latches", "step:memory"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
  {
    code: "COC1_M2_C6", title: "Power supply installed and fastened", phases: ["coc1_m2_p3"],
    conditions: [eq("placed.psu", "psu_bay"), eq("setting.psu_fastened", true)],
    counted: ["item:psu", "operation:fasten_psu", "step:psu"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
  {
    code: "COC1_M2_C7", title: "Motherboard on standoffs, fastened, with the I/O shield fitted", phases: ["coc1_m2_p3"],
    conditions: [eq("placed.motherboard", "board_standoffs"), eq("setting.board_fastened", true), eq("placed.io_shield", "io_cutout")],
    counted: ["item:motherboard", "item:io_shield", "operation:fasten_motherboard", "step:board"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
  {
    code: "COC1_M2_C8", title: "Storage drive installed and fastened", phases: ["coc1_m2_p3"],
    conditions: [eq("placed.storage", "drive_bay"), eq("setting.drive_fastened", true)],
    counted: ["item:storage", "operation:fasten_drive", "step:drive"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
  {
    code: "COC1_M2_C9", title: "Power cables connected (24-pin ATX, 8-pin EPS, SATA power)", phases: ["coc1_m2_p4"],
    conditions: [eq("link.atx_24pin>board_atx24", true), eq("link.eps_8pin>board_eps8", true), eq("link.sata_power>drive_power", true)],
    counted: ["connection:atx_24pin", "connection:eps_8pin", "connection:sata_power", "step:power_cables"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
  {
    code: "COC1_M2_C10", title: "SATA data and front-panel cables connected", phases: ["coc1_m2_p4"],
    conditions: [eq("link.sata_data>drive_data", true), eq("link.front_panel>board_front_panel", true)],
    counted: ["connection:sata_data", "connection:front_panel", "step:data_cables"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
  {
    code: "COC1_M2_C11", title: "Power-on self-test passed and result interpreted", phases: ["coc1_m2_p5"],
    conditions: [eq("result.coc1_m2_post", true), present("interpretation.coc1_m2_p5")],
    counted: ["phase:coc1_m2_p5"], max: DEFAULT_MAX_INCORRECT, pcs: ["1.4"],
  },
];

const asMap = (value) => (value && typeof value === "object" && !Array.isArray(value) ? value : {});
const asList = (value) => (Array.isArray(value) ? value : []);

/** Invalid/correction keys that the replay attributes to one phase. */
export function countedTargetsForPhase(phase) {
  const presentation = asMap(phase.presentation);
  const equipment = asMap(presentation.equipment);
  const family = phase.primaryInteraction;
  const placement = family === "place" ? presentation : asMap(equipment.placement);
  const connection = family === "connect" ? presentation : asMap(equipment.connection);
  const targets = new Set([`phase:${phase.id}`]);
  for (const item of asList(placement.items)) targets.add(`item:${item.id}`);
  for (const source of asList(connection.sources)) targets.add(`connection:${source.id}`);
  for (const operation of asList(equipment.operations)) targets.add(`operation:${operation.id}`);
  for (const target of asList(equipment.targets ?? presentation.targets)) targets.add(`tool:${target.id}`);
  return [...targets];
}

function trace(link, pcs) {
  const codes = pcs.length ? pcs : link.pcCodes;
  return `${link.moduleCode} ${link.moduleTitle} · PC ${codes.join(", ")} · ${SOURCE_NOTE}`;
}

function rule({ phases, conditions, counted, max }) {
  return {
    operator: "simulation_condition",
    phase_ids: phases,
    conditions,
    counted_targets: counted,
    max_incorrect: max,
  };
}

/** One step criterion per work phase, plus a zero-tolerance criterion per safety step. */
function genericSpecs(missionCode, definition, scoring) {
  const specs = [];
  asList(definition.phases)
    .filter((phase) => phase.primaryInteraction !== "review")
    .forEach((phase, index) => {
      const code = `${missionCode.toUpperCase()}_S${index + 1}`;
      const keys = [...(scoring.keysByPhase.get(phase.id) ?? [])];
      specs.push({
        code,
        title: phase.title,
        description: phase.instruction,
        phases: [phase.id],
        conditions: [
          ...asList(asMap(asMap(phase.presentation).equipment).completion),
          ...derivedConditions(phase, scoring.ownedRequirements.get(phase.id)),
        ],
        counted: [...new Set([...countedTargetsForPhase(phase), ...keys])],
        max: DEFAULT_MAX_INCORRECT,
        pcs: [],
      });
      const safety = asList(SAFETY_STEPS[missionCode]).find((step) => step.phase === phase.id);
      if (safety) {
        specs.push({
          code: `${code}_SAFETY`,
          title: safety.title,
          description: `${safety.reason} Safety-critical: correct on the first attempt.`,
          phases: [phase.id],
          conditions: safety.conditions,
          counted: [...safety.targets, ...keys.filter((key) => key === `safety:${phase.id}`)],
          max: 0,
          pcs: [],
          safety: true,
        });
      }
    });
  return specs;
}

/** Rubric criteria for one mission: COC1 M2's eleven steps, otherwise one per work phase. */
export function simulationCriteria(missionCode, definition, link, scoring = assessmentScoring(missionCode, definition)) {
  const specs = missionCode === "coc1_m2" ? COC1_M2_CRITERIA : genericSpecs(missionCode, definition, scoring);
  return specs.map((spec, index) => ({
    criterion_code: spec.code,
    title: spec.title,
    description: spec.description ?? `${spec.title}${spec.safety ? " (safety-critical: correct on the first attempt)" : ""}.`,
    source_trace: trace(link, spec.pcs),
    evidence_rule: rule(spec),
    scoring_rule: BINARY_RULE,
    max_value: 1,
    order_index: index + 1,
    is_required: true,
  }));
}

// COC1 M2 keeps its published wording (its package is unchanged); the other
// missions name their final verification test.
const THRESHOLD_RULE = {
  coc1_m2: "Each step allows at most two incorrect attempts: refused actions, corrections, confirmed wrong orders and, once per failed power-on test, a failing check of the step (repairs of what that test flagged are not counted). Safety-critical steps allow none.",
  other: "Each step allows at most two incorrect attempts: refused actions, corrections, confirmed wrong orders and, once per failed final verification test, a failing check of the state the step owns. Safety-critical steps (ESD, PPE, power isolation) allow none.",
};

export function buildSimulationPackage({ missionCode, contract, link }) {
  const definition = contract.definition;
  const scoring = assessmentScoring(missionCode, definition);
  return {
    missionCode,
    title: `${definition.title} — simulation assessment`,
    instructions: `${definition.scenario} Work through the simulation without hints; submit when you have finished. Unfinished steps are evaluated as not satisfied.`,
    learnerPayload: { mission_id: missionCode, definition_version: contract.version, mode: "assessment" },
    evaluatorConfig: {
      engine: "simulation_replay_v1",
      simulation_definition: scoring.snapshot,
      contract_version: contract.version,
      scoring_method: "binary_sum",
      competency_method: "all_required",
      threshold_rule: THRESHOLD_RULE[missionCode] ?? THRESHOLD_RULE.other,
      client_score_authoritative: false,
    },
    criteria: simulationCriteria(missionCode, definition, link, scoring),
    moduleId: link.moduleId,
    // Not written to the database: the published contract the snapshot came
    // from and what was derived (validation and the dry-run report).
    sourceDefinition: definition,
    scoring: { finalPhaseId: scoring.finalPhaseId, injected: scoring.injected },
  };
}

const RULE_OPERATORS = new Set(["equals", "present", "contains", "set_equals", "one_of", "not_equals", "minimum"]);
const SERVER_PATHS = new Set(["inspected", "placed", "link", "config", "setting", "operation", "tool", "fact", "result",
  "observation", "interpretation", "selection", "classification", "decision", "sequence", "order"]);

const requirementKeys = (checks) => asList(checks).flatMap((check) => asList(check.requires).map(canonical)).sort();
const phaseWithout = (phase, drop) => {
  const copy = JSON.parse(JSON.stringify(phase));
  if (drop) delete asMap(asMap(copy.presentation).equipment).checks;
  return canonical(copy);
};

/**
 * Assessment scoring assertions (dry run and live publish): safety-critical
 * steps allow no incorrect attempt, only the final verification test is
 * amended (nothing else in the snapshot differs from the contract), every
 * final check charges a step that counts it, and every decide / configure /
 * interpret step either requires the correct state or is a listed exception.
 */
export function scoringErrors(item) {
  const errors = [];
  const source = item.sourceDefinition;
  const snapshot = item.evaluatorConfig.simulation_definition;
  if (!source) return [`${item.missionCode}: no source contract to compare the snapshot with`];
  const final = finalVerificationPhase(source);
  const sourcePhases = asList(source.phases);
  const snapshotPhases = asList(snapshot.phases);
  const sourceTop = { ...source, phases: [] };
  const snapshotTop = { ...snapshot, phases: [] };
  if (canonical(sourceTop) !== canonical(snapshotTop) || sourcePhases.length !== snapshotPhases.length) {
    errors.push(`${item.missionCode}: the snapshot differs from the contract outside its phases`);
  }
  sourcePhases.forEach((phase, index) => {
    const amended = snapshotPhases[index];
    const isFinal = final && phase.id === final.id && item.missionCode !== "coc1_m2";
    if (!amended || phaseWithout(phase, isFinal) !== phaseWithout(amended, isFinal)) {
      errors.push(`${item.missionCode}: snapshot phase ${phase.id} differs from the contract${phase.primaryInteraction === "testRun" && !isFinal ? " (a diagnostic test must not be amended)" : ""}`);
    }
  });
  const byCode = new Map(item.criteria.map((criterion) => [criterion.criterion_code, criterion]));
  if (final) {
    const finalSnapshot = snapshotPhases.find((phase) => phase.id === final.id);
    const checks = asList(asMap(asMap(finalSnapshot?.presentation).equipment).checks);
    if (canonical(requirementKeys(asMap(asMap(final.presentation).equipment).checks)) !== canonical(requirementKeys(checks))) {
      errors.push(`${item.missionCode}: the final checks' requirements changed`);
    }
    for (const check of checks) {
      if (typeof check.counts !== "string") { errors.push(`${item.missionCode}: final check ${check.id} charges no step`); continue; }
      if (!item.criteria.some((criterion) => criterion.evidence_rule.counted_targets.includes(check.counts))) {
        errors.push(`${item.missionCode}: final check ${check.id} charges ${check.counts}, which no criterion counts`);
      }
    }
  }
  // Safety-critical steps: correct on the first attempt (owner decision 7).
  for (const criterion of item.criteria) {
    const safety = criterion.criterion_code.endsWith("_SAFETY")
      || (item.missionCode === "coc1_m2" && COC1_M2_CRITERIA.find((spec) => spec.code === criterion.criterion_code)?.safety);
    if (safety && criterion.evidence_rule.max_incorrect !== 0) errors.push(`${criterion.criterion_code} is safety-critical but allows incorrect attempts`);
  }
  if (item.missionCode === "coc1_m2") {
    for (const code of ["COC1_M2_C1", "COC1_M2_C3"]) {
      if (byCode.get(code)?.evidence_rule.max_incorrect !== 0) errors.push(`${code} must allow no incorrect attempt`);
    }
  }
  for (const step of asList(SAFETY_STEPS[item.missionCode])) {
    const phase = sourcePhases.find((candidate) => candidate.id === step.phase);
    const criterion = item.criteria.find((candidate) => candidate.criterion_code.endsWith("_SAFETY")
      && canonical(candidate.evidence_rule.phase_ids) === canonical([step.phase]));
    if (!phase) { errors.push(`${item.missionCode}: safety step ${step.phase} is not in the contract`); continue; }
    if (!criterion || criterion.evidence_rule.max_incorrect !== 0) { errors.push(`${item.missionCode}: safety step ${step.phase} has no zero-tolerance criterion`); continue; }
    const phaseTargets = new Set([...countedTargetsForPhase(phase), `safety:${phase.id}`]);
    for (const target of step.targets) if (!phaseTargets.has(target)) errors.push(`${criterion.criterion_code} counts ${target}, which ${phase.id} does not own`);
    const finalIndex = final ? sourcePhases.findIndex((candidate) => candidate.id === final.id) : sourcePhases.length - 1;
    for (const condition of step.conditions) {
      if (ownerOf(condition.path, sourcePhases, finalIndex) !== phase.id) errors.push(`${criterion.criterion_code} checks ${condition.path}, which ${phase.id} does not own`);
    }
    for (const checkId of step.checks) {
      const charged = (item.scoring?.injected ?? []).filter((entry) => entry.check === checkId || entry.check === `${checkId}.${phase.id}`);
      if (!charged.some((entry) => entry.counts === `safety:${phase.id}`)) errors.push(`${criterion.criterion_code}: final check ${checkId} does not charge safety:${phase.id}`);
    }
  }
  // Decide, configure and interpret steps require the state the final checks expect.
  if (item.missionCode !== "coc1_m2") {
    sourcePhases.filter((phase) => phase.primaryInteraction !== "review").forEach((phase, index) => {
      const family = phase.primaryInteraction;
      const empty = !asList(asMap(asMap(phase.presentation).equipment).completion).length;
      if (family !== "decide" && !((family === "configure" || family === "interpret") && empty)) return;
      const criterion = byCode.get(`${item.missionCode.toUpperCase()}_S${index + 1}`);
      const required = asList(criterion?.evidence_rule.conditions);
      const decided = family !== "decide" || required.some((condition) => condition.path === `decision.${phase.id}`);
      const stated = family === "decide" ? decided : required.length > 0;
      if (!stated && !NO_DERIVABLE_CONDITION[phase.id]) errors.push(`${item.missionCode}: step ${phase.id} (${family}) requires no correct state and is not a listed exception`);
    });
  }
  return errors;
}

/** Mirrors private.valid_evidence_rule plus contract consistency and scoring checks. */
export function validateSimulationPackages(packages) {
  const errors = [];
  const missions = new Set();
  for (const item of packages) {
    if (missions.has(item.missionCode)) errors.push(`Duplicate mission ${item.missionCode}`);
    missions.add(item.missionCode);
    const payload = JSON.stringify(item.learnerPayload);
    if (payload.includes("simulation_template") || payload.includes("evidence_rule") || payload.includes("simulation_definition")) {
      errors.push(`${item.missionCode} learner payload exposes evaluator data`);
    }
    const phaseIds = new Set(asList(item.evaluatorConfig.simulation_definition.phases).map((phase) => phase.id));
    const codes = new Set();
    if (!item.criteria.length) errors.push(`${item.missionCode} has no criteria`);
    for (const criterion of item.criteria) {
      if (codes.has(criterion.criterion_code)) errors.push(`Duplicate criterion ${criterion.criterion_code}`);
      codes.add(criterion.criterion_code);
      const evidence = criterion.evidence_rule;
      if (!evidence.phase_ids.length || evidence.phase_ids.some((id) => !phaseIds.has(id))) {
        errors.push(`${criterion.criterion_code} names a phase outside its contract`);
      }
      if (!Number.isInteger(evidence.max_incorrect) || evidence.max_incorrect < 0 || evidence.max_incorrect > 999) {
        errors.push(`${criterion.criterion_code} has an invalid threshold`);
      }
      for (const condition of evidence.conditions) {
        if (!SERVER_PATHS.has(String(condition.path).split(".")[0]) || !RULE_OPERATORS.has(condition.operator ?? "equals")) {
          errors.push(`${criterion.criterion_code} uses a condition the server cannot evaluate: ${JSON.stringify(condition)}`);
        }
      }
      if (criterion.title.length < 2 || criterion.title.length > 300 || criterion.source_trace.length > 1000) {
        errors.push(`${criterion.criterion_code} title or trace length is invalid`);
      }
    }
    errors.push(...scoringErrors(item));
  }
  if (errors.length) throw new Error(errors.join("\n"));
  return { missions: packages.length, criteria: packages.reduce((sum, item) => sum + item.criteria.length, 0) };
}

/** What the scoring derived per mission (dry-run report). */
export function scoringReport(packages) {
  return packages.map((item) => ({
    mission: item.missionCode,
    final_test: item.scoring.finalPhaseId,
    counts: Object.fromEntries(item.scoring.injected.map((entry) => [entry.check, entry.counts])),
    safety_criteria: item.criteria.filter((criterion) => criterion.evidence_rule.max_incorrect === 0)
      .map((criterion) => ({ code: criterion.criterion_code, phases: criterion.evidence_rule.phase_ids, counted: criterion.evidence_rule.counted_targets })),
    decisions: Object.fromEntries(item.criteria.flatMap((criterion) => criterion.evidence_rule.conditions
      .filter((condition) => String(condition.path).startsWith("decision.") && condition.operator === "one_of")
      .map((condition) => [`${criterion.criterion_code} ${condition.path}`, condition.value]))),
  }));
}

/** The package fields written to the database (for --emit and drift checks). */
export function publishedShape(item) {
  return { mission: item.missionCode, title: item.title, learner_payload: item.learnerPayload, evaluator_config: item.evaluatorConfig, criteria: item.criteria };
}

export function parseArgs(argv) {
  const options = { target: "local", confirm: false, dryRun: false, contracts: null, emit: null };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--target") options.target = argv[++index];
    else if (arg === "--confirm") options.confirm = true;
    else if (arg === "--dry-run") options.dryRun = true;
    else if (arg === "--contracts") options.contracts = argv[++index];
    else if (arg === "--emit") options.emit = argv[++index];
    else throw new Error(`Unknown argument ${arg}`);
  }
  if (!["local", "hosted"].includes(options.target)) throw new Error("--target must be local or hosted.");
  if (options.target === "hosted" && !options.confirm) throw new Error("Publishing to the hosted project requires --confirm.");
  // A live publish snapshots the published contracts from the database, never
  // from a local file.
  if (options.contracts && !options.dryRun) throw new Error("--contracts is only accepted with --dry-run.");
  if (options.emit !== null && (!options.dryRun || !options.emit)) throw new Error("--emit <file> is only accepted with --dry-run.");
  return options;
}

async function loadInputs(service, contractsFile) {
  const fromFile = contractsFile ? JSON.parse(fs.readFileSync(contractsFile, "utf8")) : null;
  const contracts = fromFile
    ? Object.entries(fromFile).map(([mission_id, contract]) => ({ mission_id, ...contract }))
    : await (async () => {
      const { data, error } = await service.from("practice_mission_contracts").select("mission_id,version,definition");
      if (error) throw error;
      return data;
    })();
  const links = fromFile?.__links ?? await (async () => {
    const { data, error } = await service
      .from("mission_curriculum_links")
      .select("mission_code,pc_codes,module_id,curriculum_modules(code,title)");
    if (error) throw error;
    return data;
  })();
  const linkByMission = new Map(links.map((row) => [row.mission_code, {
    moduleId: row.module_id,
    moduleCode: row.curriculum_modules?.code ?? row.module_code,
    moduleTitle: row.curriculum_modules?.title ?? row.module_title,
    pcCodes: row.pc_codes ?? [],
  }]));
  return contracts
    .filter((contract) => /^coc[1-4]_m[1-5]$/.test(contract.mission_id))
    .sort((a, b) => a.mission_id.localeCompare(b.mission_id))
    .map((contract) => {
      const link = linkByMission.get(contract.mission_id);
      if (!link) throw new Error(`${contract.mission_id} has no curriculum module link.`);
      return buildSimulationPackage({ missionCode: contract.mission_id, contract, link });
    });
}

async function createGovernancePrincipal(service, url, publishableKey, createClient) {
  const password = process.env.BYTEQUEST_E2E_PASSWORD;
  if (!password) throw new Error("BYTEQUEST_E2E_PASSWORD is required for the temporary governance principal.");
  const email = `bytequest-simulation-release-${Date.now()}-${randomUUID().slice(0, 8)}@bytequest.invalid`;
  const { data, error } = await service.auth.admin.createUser({
    email, password, email_confirm: true,
    user_metadata: { full_name: "ByteQuest Simulation Release Governance", bytequest_technical_principal: true },
  });
  if (error || !data.user) throw new Error(error?.message ?? "Governance principal was not created.");
  const principal = { id: data.user.id, client: createClient(url, publishableKey, { auth: { autoRefreshToken: false, persistSession: false } }) };
  // Sign in before the promotion, and retire the account on any failure, so a
  // failed run never leaves an active admin behind (dashboard-server M4).
  try {
    const { error: signInError } = await principal.client.auth.signInWithPassword({ email, password });
    if (signInError) throw signInError;
    const { error: profileError } = await service.from("profiles")
      .update({ full_name: "ByteQuest Simulation Release Governance", role: "admin", status: "active" })
      .eq("user_id", principal.id);
    if (profileError) throw profileError;
    return principal;
  } catch (failure) {
    await retireGovernancePrincipal(service, principal);
    throw failure;
  }
}

// Runs in `finally`: report a failed retirement without masking the publish
// error, so an operator can deactivate the principal by hand.
async function retireGovernancePrincipal(service, principal) {
  if (!principal) return;
  try { await principal.client.auth.signOut(); } catch { /* not signed in: retire the account below */ }
  const { error: profileError } = await service.from("profiles").update({
    status: "deactivated",
    deactivated_at: new Date().toISOString(),
    deactivation_reason: "Technical release principal retired after publishing simulation assessments.",
  }).eq("user_id", principal.id);
  const { error: banError } = await service.auth.admin.updateUserById(principal.id, { ban_duration: "876000h" });
  for (const error of [profileError, banError]) {
    if (error) console.error(`Governance principal ${principal.id} was not fully retired: ${error.message}`);
  }
}

async function ensureActiveSource(service, principal) {
  const { data: active, error } = await service.from("tesda_sources")
    .select("id,edition,status").eq("qualification_code", TESDA_SOURCE.qualificationCode).eq("status", "active").maybeSingle();
  if (error) throw error;
  if (active) return active;
  const { data: existing, error: lookupError } = await service.from("tesda_sources").select("id,edition,status")
    .eq("qualification_code", TESDA_SOURCE.qualificationCode).eq("title", TESDA_SOURCE.title)
    .eq("edition", TESDA_SOURCE.edition).maybeSingle();
  if (lookupError) throw lookupError;
  let source = existing;
  // The digest is computed from the repository copy of the official PDF
  // before a note claims it (throws when the copy differs).
  const digest = source && source.status !== "pending_tesda_validation" ? null : verifiedSourceDigest();
  if (!source) {
    const { data, error: registerError } = await principal.client.rpc("register_tesda_source", {
      p_qualification_code: TESDA_SOURCE.qualificationCode,
      p_title: TESDA_SOURCE.title,
      p_edition: TESDA_SOURCE.edition,
      p_effective_date: null,
      p_publication_date: null,
      p_source_reference: TESDA_SOURCE.reference,
      p_document_storage_path: null,
      p_validation_notes: `Official TESDA primary source; SHA-256 ${digest} computed from the repository copy ${TESDA_SOURCE.localCopy} of the published PDF.`,
    });
    if (registerError) throw registerError;
    source = data;
  }
  if (source.status === "pending_tesda_validation") {
    const { data, error: approveError } = await principal.client.rpc("approve_tesda_source", {
      p_source_id: source.id,
      p_validation_notes: `TESDA_OFFICIAL_APPROVED: official amended December 2013 CSS NC II Training Regulations; SHA-256 ${digest} computed from ${TESDA_SOURCE.localCopy}.`,
    });
    if (approveError) throw approveError;
    source = data;
  }
  if (source.status === "approved") {
    const { data, error: activateError } = await principal.client.rpc("activate_tesda_source", {
      p_source_id: source.id,
      p_reason: "Activate the verified official source that carries the simulation-based assessments.",
    });
    if (activateError) throw activateError;
    source = data;
  }
  if (source.status !== "active") throw new Error(`TESDA source is ${source.status}, not active.`);
  return source;
}

async function ensurePublishedModule(service, principal, source, cocModule) {
  const { data: versions, error } = await service.from("module_versions").select("*")
    .eq("module_id", cocModule.id).eq("tesda_source_id", source.id).order("version_number", { ascending: false });
  if (error) throw error;
  const published = versions.find((item) => item.status === "published");
  if (published) return published;
  const { data: inserted, error: insertError } = await service.from("module_versions").insert({
    module_id: cocModule.id,
    tesda_source_id: source.id,
    version_number: (versions[0]?.version_number ?? 0) + 1,
    title: `${cocModule.coc_code.toUpperCase()} simulation assessments`,
    description: "Versioned ByteQuest module carrying simulation-based assessments evaluated by server replay.",
    source_trace: { source_classification: "TESDA_OFFICIAL_APPROVED", note: SOURCE_NOTE },
    content_metadata: { supplementary_platform: true, issues_official_tesda_certification: false, assessment_engine: "simulation_replay_v1" },
    created_by: principal.id,
  }).select("*").single();
  if (insertError) throw insertError;
  const { data, error: publishError } = await principal.client.rpc("publish_module_version", {
    p_module_version_id: inserted.id,
    p_reason: "Publish the module that carries simulation-based assessments.",
  });
  if (publishError) throw publishError;
  return data;
}

async function ensureActivity(service, principal, pkg, mission, moduleVersion) {
  const { data: matches, error } = await service.from("activity_versions").select("*")
    .eq("mission_id", mission.id).contains("learner_payload", pkg.learnerPayload);
  if (error) throw error;
  let activity = matches.find((item) => item.status !== "retired") ?? null;
  const created = !activity;
  if (!activity) {
    const { data: versions, error: versionError } = await service.from("activity_versions")
      .select("version_number").eq("mission_id", mission.id).order("version_number", { ascending: false }).limit(1);
    if (versionError) throw versionError;
    const { data, error: insertError } = await service.from("activity_versions").insert({
      mission_id: mission.id,
      module_version_id: moduleVersion.id,
      version_number: (versions[0]?.version_number ?? 0) + 1,
      title: pkg.title.slice(0, 300),
      instructions: pkg.instructions,
      delivery_mode: "assessment",
      learner_payload: pkg.learnerPayload,
      evaluator_config: pkg.evaluatorConfig,
      created_by: principal.id,
    }).select("*").single();
    if (insertError) throw insertError;
    activity = data;
  }
  const publishedNow = activity.status === "draft";
  if (activity.status === "draft") {
    const { data, error: publishError } = await principal.client.rpc("publish_activity_version", {
      p_activity_version_id: activity.id,
      p_reason: `Publish the ${pkg.missionCode} simulation assessment.`,
    });
    if (publishError) throw publishError;
    activity = data;
  }
  if (activity.status !== "published") throw new Error(`${pkg.missionCode} activity is ${activity.status}.`);
  return { activity, created, publishedNow };
}

async function ensureRubric(service, principal, pkg, activity, source) {
  const { data: versions, error } = await service.from("rubric_versions").select("*")
    .eq("activity_version_id", activity.id).order("version_number", { ascending: false });
  if (error) throw error;
  let rubric = versions.find((item) => item.status === "approved") ?? versions[0];
  if (rubric?.status === "approved") return { rubric, approvedNow: false };
  if (!rubric) {
    const { data, error: insertError } = await service.from("rubric_versions").insert({
      activity_version_id: activity.id,
      tesda_source_id: source.id,
      version_number: 1,
      title: `${pkg.missionCode.toUpperCase()} simulation step rubric`,
      status: "draft",
      created_by: principal.id,
    }).select("*").single();
    if (insertError) throw insertError;
    rubric = data;
  }
  const { error: criteriaError } = await service.from("rubric_criteria").upsert(
    pkg.criteria.map((criterion) => ({ ...criterion, rubric_version_id: rubric.id })),
    { onConflict: "rubric_version_id,criterion_code" },
  );
  if (criteriaError) throw criteriaError;
  const { data: approved, error: approveError } = await principal.client.rpc("approve_rubric_version", {
    p_rubric_version_id: rubric.id,
    p_scoring_method: "binary_sum",
    p_passing_rule: {
      status: "APPROVED",
      method: "all_required",
      classification: "PROJECT_APPROVED_OPERATIONAL_RULE",
      official_numeric_threshold: null,
      step_threshold: "At most two incorrect attempts per step; safety-critical steps none (owner decision 7).",
    },
    p_reason: "Approve the simulation step rubric generated from the published practice contract.",
  });
  if (approveError) throw approveError;
  return { rubric: approved, approvedNow: true };
}

const CRITERION_FIELDS = ["criterion_code", "title", "description", "source_trace", "evidence_rule", "scoring_rule", "max_value", "order_index", "is_required"];
const criterionShape = (criterion) => Object.fromEntries(CRITERION_FIELDS.map((field) => [field, field === "max_value" || field === "order_index" ? Number(criterion[field]) : criterion[field]]));

/**
 * Packages already in the database for the same contract version that differ
 * from what this publisher generates. Published activity and approved rubric
 * versions are immutable, so a live publish stops before writing anything.
 */
export async function publishedDrift(service, packages, missionByCode) {
  const drift = [];
  for (const pkg of packages) {
    const mission = missionByCode.get(pkg.missionCode);
    if (!mission) continue;
    const { data: matches, error } = await service.from("activity_versions").select("id,status,evaluator_config")
      .eq("mission_id", mission.id).contains("learner_payload", pkg.learnerPayload);
    if (error) throw error;
    const activity = matches.find((item) => item.status !== "retired");
    if (!activity) continue;
    const reasons = [];
    if (canonical(activity.evaluator_config) !== canonical(pkg.evaluatorConfig)) reasons.push("evaluator snapshot");
    const { data: rubrics, error: rubricError } = await service.from("rubric_versions").select("id,status")
      .eq("activity_version_id", activity.id).eq("status", "approved");
    if (rubricError) throw rubricError;
    for (const rubric of rubrics) {
      const { data: criteria, error: criteriaError } = await service.from("rubric_criteria").select(CRITERION_FIELDS.join(","))
        .eq("rubric_version_id", rubric.id);
      if (criteriaError) throw criteriaError;
      const stored = criteria.map(criterionShape).sort((a, b) => a.criterion_code.localeCompare(b.criterion_code));
      const generated = pkg.criteria.map(criterionShape).sort((a, b) => a.criterion_code.localeCompare(b.criterion_code));
      if (canonical(stored) !== canonical(generated)) reasons.push("approved rubric criteria");
    }
    if (reasons.length) drift.push({ mission: pkg.missionCode, activity_version_id: activity.id, status: activity.status, differs: reasons });
  }
  return drift;
}

async function linkFormBasedPackages(service, missionsById, links) {
  const { data, error } = await service.from("activity_versions")
    .select("id,mission_id,learner_payload,status").eq("delivery_mode", "assessment");
  if (error) throw error;
  const rows = [];
  for (const activity of data) {
    const payload = asMap(activity.learner_payload);
    if (payload.mode === "assessment" && !payload.simulation_template) continue;
    const mission = missionsById.get(activity.mission_id);
    const link = mission && links.get(mission.mission_code);
    if (!link) continue;
    rows.push({
      activity_version_id: activity.id,
      module_id: link.moduleId,
      delivery_kind: payload.simulation_template === "coc2_cable_termination" ? "protected_reference" : "form_based",
    });
  }
  if (!rows.length) return 0;
  const { error: linkError } = await service.from("activity_curriculum_links")
    .upsert(rows, { onConflict: "activity_version_id", ignoreDuplicates: true });
  if (linkError) throw linkError;
  return rows.length;
}

function dryRunResult(options, packages, validation, extra = {}) {
  if (options.emit) fs.writeFileSync(options.emit, `${JSON.stringify(packages.map(publishedShape), null, 2)}\n`);
  return { status: "VALIDATED", ...extra, ...validation, scoring: scoringReport(packages), ...(options.emit ? { emitted: options.emit } : {}) };
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.dryRun && options.contracts) {
    const packages = await loadInputs(null, options.contracts);
    verifiedSourceDigest();
    return dryRunResult(options, packages, validateSimulationPackages(packages));
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !publishableKey || !serviceRoleKey) throw new Error("Trusted Supabase publishing environment is unavailable.");
  const local = ["127.0.0.1", "localhost"].includes(new URL(url).hostname);
  if (options.target === "local" && !local) throw new Error("The local target requires a 127.0.0.1/localhost Supabase URL.");
  if (options.target === "hosted" && local) throw new Error("--target hosted needs the hosted project URL.");

  const { createClient } = await import("@supabase/supabase-js");
  const service = createClient(url, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const packages = await loadInputs(service, options.contracts);
  const validation = validateSimulationPackages(packages);
  verifiedSourceDigest();

  const [{ data: cocModules, error: moduleError }, { data: missions, error: missionError }] = await Promise.all([
    service.from("coc_modules").select("id,coc_code"),
    service.from("missions").select("id,mission_code"),
  ]);
  if (moduleError) throw moduleError;
  if (missionError) throw missionError;
  const moduleByCoc = new Map(cocModules.map((row) => [row.coc_code, row]));
  const missionByCode = new Map(missions.map((row) => [row.mission_code, row]));
  const missionById = new Map(missions.map((row) => [row.id, row]));
  const linkByMission = new Map(packages.map((pkg) => [pkg.missionCode, { moduleId: pkg.moduleId }]));

  const drift = await publishedDrift(service, packages, missionByCode);
  if (options.dryRun) return dryRunResult(options, packages, validation, { target: options.target, drift });
  if (drift.length) {
    throw new Error(`Nothing was published. ${drift.length} mission(s) already have a different package for the same contract version (${drift.map((item) => `${item.mission}: ${item.differs.join(" and ")}`).join("; ")}). Published activity and approved rubric versions are immutable; publish onto a database without these packages (a fresh local reset, or a project where the packages were never published).`);
  }

  const principal = await createGovernancePrincipal(service, url, publishableKey, createClient);
  const published = [];
  try {
    const source = await ensureActiveSource(service, principal);
    const moduleCache = new Map();
    for (const pkg of packages) {
      const coc = pkg.missionCode.slice(0, 4);
      const mission = missionByCode.get(pkg.missionCode);
      const cocModule = moduleByCoc.get(coc);
      if (!mission || !cocModule) throw new Error(`Catalog entry missing for ${pkg.missionCode}.`);
      if (!moduleCache.has(coc)) moduleCache.set(coc, await ensurePublishedModule(service, principal, source, cocModule));
      const { activity, created, publishedNow } = await ensureActivity(service, principal, pkg, mission, moduleCache.get(coc));
      const { rubric, approvedNow } = await ensureRubric(service, principal, pkg, activity, source);
      const { error: linkError } = await service.from("activity_curriculum_links").upsert(
        { activity_version_id: activity.id, module_id: pkg.moduleId, delivery_kind: "simulation" },
        { onConflict: "activity_version_id", ignoreDuplicates: true },
      );
      if (linkError) throw linkError;
      // audit_events is append-only: record only what this run published
      // (a re-run after a partial failure adds nothing for finished missions).
      const changed = created || publishedNow || approvedNow;
      if (changed) {
        const { error: auditError } = await service.from("audit_events").insert({
          actor_id: principal.id,
          actor_role: "admin",
          action: "simulation_assessment.published",
          target_type: "activity_version",
          target_id: activity.id,
          reason: `Publish the ${pkg.missionCode} simulation assessment generated from contract ${pkg.learnerPayload.definition_version}.`,
          metadata: {
            mission_code: pkg.missionCode, definition_version: pkg.learnerPayload.definition_version, rubric_version_id: rubric.id,
            criteria_count: pkg.criteria.length, activity_created: created, activity_published: publishedNow, rubric_approved: approvedNow,
          },
          outcome: "success",
        });
        if (auditError) throw auditError;
      }
      published.push({ mission: pkg.missionCode, activityVersionId: activity.id, rubricVersionId: rubric.id, criteria: pkg.criteria.length, changed });
    }
    const formBased = await linkFormBasedPackages(service, missionById, new Map(
      [...linkByMission].map(([code, link]) => [code, link]),
    ));
    return { status: "PUBLISHED", target: options.target, ...validation, missions: published, formBasedLinked: formBased };
  } finally {
    await retireGovernancePrincipal(service, principal);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().then((result) => console.log(JSON.stringify(result, null, 2))).catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
