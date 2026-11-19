// Re-defense demo data (spec WS11, owner decision 6).
//
// Creates, idempotently, the clearly labelled demo class
// "DEMO – Re-defense (synthetic learners)" (class code DEMO-REDEF) with twelve
// synthetic learners (Alex Demo .. Lou Demo, demo.learner01..12@bytequest.invalid)
// who perform real activities through the same API routes and RPCs the
// learner app and the dashboard use:
//   * accounts: learner sign-up (GoTrue, as the app does); the instructor
//     imports an Excel roster through the dashboard route (8 accounts enroll
//     now, 4 emails stay pending and enroll automatically when they sign up);
//     an already-seeded learner whose name differs renames itself through its
//     own profile update, as the app's Edit profile screen does;
//   * two LO1.1 lessons through the curriculum workflow (one published, one
//     approved so an admin can publish it live);
//   * practice through the app's evidence table and /api/learner/practice
//     (action generators of scripts/test-practice-api-all-missions.mjs, with
//     realistic mistakes and failed verifications), lessons through
//     /api/learner/curriculum and the COC1 practice quiz;
//   * the COC1 M2 simulation assessment, assigned exactly as the dashboard's
//     "Assign published content" form does (approved rubric read under the
//     instructor's own RLS, then the instructor's assign_activity), taken
//     through start_attempt / append_attempt_action / submit_attempt, and the
//     Evaluation Center (record evaluation, finalize, release) through
//     /api/evaluations;
//   * a curriculum quiz with a scenario essay (quiz RPCs, /api/quizzes/
//     evaluation and /api/evaluations) and a homework with two criteria
//     (/api/activities/homework and /api/evaluations);
//   * four learners opt into the class leaderboard (profile update).
// Nothing is inserted directly into result, attempt, evidence, point or
// completion tables; points, levels, achievements, unlocks and analytics are
// computed by the server from these records. The service role is used only
// where the apps use it too (account confirmation/password reset) and for
// read-only checks and the run summary.
//
// Usage (repository root; see docs/DEMO_DATA.md):
//   node scripts/seed-demo-class.mjs                  local stack + local dashboard (default)
//   node scripts/seed-demo-class.mjs --summary-only   print the run summary only
//   node scripts/seed-demo-class.mjs --remove         archive the class and deactivate the learners
//   node scripts/seed-demo-class.mjs --target hosted --confirm --instructor-email <email> --admin-email <email> [--publish-topics]
// Credentials of the demo learners are written only to the gitignored
// .tmp/demo-accounts.json; the run summary to .tmp/demo-seed-summary.json.
import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomBytes } from 'node:crypto';
import { execSync, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOCAL_API = 'http://127.0.0.1:57321';
const LOCAL_WEB = 'http://127.0.0.1:3000';
const ACCOUNT_FILE = path.join(ROOT, '.tmp', 'demo-accounts.json');
const SUMMARY_FILE = path.join(ROOT, '.tmp', 'demo-seed-summary.json');
const DEFAULT_FIXTURES = path.join(ROOT, '.tmp', 'demo-practice-evidence.json');
const DEFAULT_QA_ACCOUNTS = path.join(ROOT, '.tmp', 'local-qa-accounts.json');

// ---------------------------------------------------------------------------
// Labels and authored content (every authored item is prefixed "DEMO · ").
// ---------------------------------------------------------------------------
export const CLASS_CODE = 'DEMO-REDEF';
export const CLASS_TITLE = 'DEMO – Re-defense (synthetic learners)';
export const PREFIX = 'DEMO · ';
const COURSE_SECTION = 'CSS NC II · Demo section';

// Synthetic first names (not project members) with the surname "Demo", so the
// leaderboard's "First name L." display is distinct per learner and still
// obviously demo data ("Alex D.", "Bea D.", ...).
export const DEMO_FIRST_NAMES = ['Alex', 'Bea', 'Cris', 'Dani', 'Eli', 'Fran', 'Gale', 'Hal', 'Iya', 'Jules', 'Kai', 'Lou'];
export const DEMO_SURNAME = 'Demo';

export const LEARNERS = DEMO_FIRST_NAMES.map((firstName, index) => {
  const nn = String(index + 1).padStart(2, '0');
  return {
    key: `L${nn}`,
    email: `demo.learner${nn}@bytequest.invalid`,
    name: `${firstName} ${DEMO_SURNAME}`,
    firstName,
    lastName: DEMO_SURNAME,
    studentId: `DEMO-RD-${nn}`,
    // Learners 09-12 have no account when the roster is imported: they are
    // pending roster entries that enroll automatically when they sign up.
    pendingAtImport: index + 1 >= 9,
  };
});
const learnerByKey = new Map(LEARNERS.map((learner) => [learner.key, learner]));

export const TOPICS = {
  esd: {
    title: `${PREFIX}ESD precautions at the workbench`,
    outcomes: ['1.1', '1.3'],
    summary: 'Why electrostatic discharge damages components and how to prepare an ESD-safe workbench before assembling a computer.',
    body: [
      '## Why ESD matters',
      'Electrostatic discharge (ESD) is the sudden flow of static electricity between two objects at different electrical potentials. People usually feel a discharge only above about 3,000 volts, but a much smaller discharge can damage or weaken the circuits of a processor, a memory module or a motherboard. The damage is not always immediate: a weakened component can fail weeks later.',
      '',
      '## Prepare the work area',
      '1. Shut down the computer, switch off the power supply and unplug the power cord before you open the case.',
      '2. Work on a clean, dry table, not on a carpeted floor, with an anti-static mat connected to ground.',
      '3. Wear an anti-static wrist strap and clip it to bare, unpainted metal of the chassis or to the ground point of the mat.',
      '4. Remove jewellery and avoid clothing that builds static, such as wool or synthetic sweaters.',
      '5. Keep food, drinks and magnets away from the work area.',
      '',
      '## Handle components safely',
      '- Keep new components in their anti-static bags until you install them.',
      '- Hold cards and modules by their edges; never touch gold contacts, pins or chips.',
      '- Put removed components on the anti-static mat or in an anti-static bag, never on a carpet or a plain plastic surface.',
      '- If no wrist strap is available, touch bare metal of the grounded chassis before handling a component and repeat it often.',
      '',
      '## Check your tools',
      'Use insulated hand tools and a non-magnetic Phillips screwdriver. Inspect the cord and clip of the wrist strap before use and replace a damaged strap.',
    ].join('\n'),
  },
  handling: {
    title: `${PREFIX}Handling and seating components`,
    outcomes: ['1.2', '1.4'],
    summary: 'How to check, align and seat the processor, memory, boards, drives and cables without forcing them.',
    body: [
      '## Check before you install',
      '- Compare each part with the system requirements: the CPU socket, the memory type (for example DDR4 or DDR5) and the motherboard form factor must match.',
      '- Inspect parts for bent pins, cracked boards or damaged connectors before installation.',
      '',
      '## Processor (CPU)',
      '1. Lift the retention lever of the socket (and the load plate, if there is one).',
      '2. Align the triangle or notch marker of the CPU with the marker on the socket.',
      '3. Lower the CPU straight into the socket without pressing or sliding it.',
      '4. Close the load plate and lower the lever until it locks.',
      '5. Apply a thin layer of thermal compound if the cooler has none, mount the cooler and connect its fan cable to the CPU_FAN header.',
      '',
      '## Memory (RAM)',
      '1. Open the latches of the memory slots.',
      '2. Align the notch of the module with the key in the slot; a module fits only one way.',
      '3. For two modules, use the slots the motherboard manual recommends for dual-channel operation.',
      '4. Press both ends down evenly until the latches click closed.',
      '',
      '## Boards, drives and cables',
      '- Fit the I/O shield before the motherboard, then fasten the board to the standoffs without overtightening the screws.',
      '- Secure drives in their bays with screws or the tool-less brackets of the case.',
      '- Connect the 24-pin ATX and the 4/8-pin EPS power cables, then the SATA power and data cables and the front-panel connectors. Connectors are keyed: if one does not fit, check its orientation instead of forcing it.',
      '- Route cables away from fans and tie them so that the airflow stays clear.',
    ].join('\n'),
  },
};

export const QUIZ = {
  title: `${PREFIX}Assembly safety check`,
  description: 'Short check of safe assembly practice before the COC1 M2 assembly assessment.',
  instructions: 'Answer every question. Your instructor evaluates the scenario essay with the rubric shown, then finalizes and releases the result.',
  focus: 'Applying ESD and OH&S precautions and the correct seating procedure for internal components when assembling computer hardware (LO1.1, PC 1.1 and 1.4).',
  quizType: 'formative',
  difficulty: 'foundation',
  timeLimitMinutes: 15,
  outcomes: ['1.1', '1.4'],
  items: [
    {
      key: 'q1', type: 'multiple_choice',
      prompt: 'Before you open the system unit to install a component, what should you do first?',
      options: ['Shut down the computer and unplug the power cord', 'Remove the CPU cooler first', 'Open the power supply unit to check its fuse', 'Spray the motherboard with compressed air while it is running'],
      answer: 'Shut down the computer and unplug the power cord',
      explanation: 'Removing the power source protects you from electric shock and the components from damage before any work starts.',
    },
    {
      key: 'q2', type: 'multiple_choice',
      prompt: 'Where should an anti-static wrist strap be clipped?',
      options: ['To bare, unpainted metal of the chassis or the ground point of the anti-static mat', 'To a painted panel of the case', 'To the fins of the CPU heat sink', 'To the plastic front bezel'],
      answer: 'To bare, unpainted metal of the chassis or the ground point of the anti-static mat',
      explanation: 'Only a bare metal ground point equalises the charge between you and the computer.',
    },
    {
      key: 'q3', type: 'true_false',
      prompt: 'A CPU can be installed in any orientation as long as it is pressed firmly into the socket.',
      answer: 'false',
      explanation: 'Align the triangle marker of the CPU with the socket and lower it without force; pressing a misaligned CPU bends the pins.',
    },
    {
      key: 'q4', type: 'true_false',
      prompt: 'Memory modules should be held by their edges and pressed down evenly until both latches click closed.',
      answer: 'true',
      explanation: 'Holding modules by the edges avoids ESD damage to the contacts; even pressure seats the module fully.',
    },
    {
      key: 'q5', type: 'multiple_choice',
      prompt: 'A memory module does not go into its slot. What is the correct action?',
      options: ['Check that the notch of the module lines up with the key in the slot', 'Press harder until it clicks', 'File down the notch of the module', 'Install it in the slot at an angle'],
      answer: 'Check that the notch of the module lines up with the key in the slot',
      explanation: 'Memory slots are keyed; a module that does not fit is reversed or of the wrong type.',
    },
    {
      key: 'essay', type: 'scenario_essay',
      scenario: 'A classmate is about to upgrade the memory of a desktop computer. The computer is still plugged in, the work table stands on a carpeted floor, the classmate is wearing a wool sweater, and the new memory modules have been taken out of their anti-static bags and placed on the carpet.',
      prompt: 'Identify the hazards in this situation and explain, step by step, how you would prepare the work area and install the memory modules safely.',
      rubric: [
        { id: 'C1', criterion: 'Identifies the hazards', description: 'Names the electrical hazard of working on a plugged-in unit and the ESD risks (carpet, wool clothing, unprotected modules).', max_points: 4 },
        { id: 'C2', criterion: 'Prepares the work area', description: 'Describes shutting down and unplugging, an anti-static mat and a grounded wrist strap, and a suitable work surface.', max_points: 4 },
        { id: 'C3', criterion: 'Installs the memory correctly', description: 'Explains holding modules by the edges, aligning the notch, using the recommended slots and seating until the latches lock.', max_points: 2 },
      ],
      guide: 'Expect: power off and unplug; anti-static mat and wrist strap on bare chassis metal; avoid carpet and wool; keep modules in anti-static bags; hold by the edges; align the notch; dual-channel slots; press until both latches lock.',
      minWords: 40,
      maxWords: 250,
    },
  ],
};

export const HOMEWORK = {
  title: `${PREFIX}Document a safe assembly checklist`,
  instructions: 'After the COC1 M2 assembly practice, write the safe assembly checklist you followed. Include the safety precautions you took and the order in which you installed and connected each component, ending with the power-on test.',
  objectives: [
    'List the power-isolation and ESD precautions taken before assembly.',
    'Document the installation sequence of the internal components and the final power-on test.',
  ],
  criteria: [
    { id: 'C1', criterion: 'Safety precautions identified', description: 'Power isolation, ESD protection and safe handling before and during assembly.', max_points: 10 },
    { id: 'C2', criterion: 'Assembly sequence documented', description: 'Correct order for the CPU, cooler, memory, power supply, motherboard, storage and cables, ending with a power-on test.', max_points: 10 },
  ],
  requirements: 'Submit a numbered checklist of at least eight steps in the answer box. File attachments are optional.',
  deadlineMinutes: 4,
};

const ESSAYS = {
  strong: 'The computer is still plugged in, so there is a risk of electric shock and of damaging the board. The carpet, the wool sweater and the modules lying on the carpet can all build up static electricity, and an electrostatic discharge can destroy the memory chips. First I would shut down the computer and unplug the power cord. I would move the work to a table with an anti-static mat, wear an anti-static wrist strap clipped to the bare metal of the chassis and take off the sweater. I would keep the modules in their anti-static bags until installation and hold them only by the edges. Then I would open the slot latches, line up the notch with the key, use the dual-channel slots shown in the manual and press both ends down until the latches click.',
  good: 'The PC is still plugged in, which can give an electric shock, and the carpet and the wool sweater build static that can damage the RAM. I would shut down and unplug the computer, put on an anti-static wrist strap connected to the case and work on an anti-static mat on a table instead of the carpet. Then I would open the latches, line up the notch on the RAM with the slot and press it down until it clicks.',
  decent: 'The problem is static electricity from the carpet and the sweater, and the computer is still plugged in. Unplug it first and wear a wrist strap. Do not put the RAM on the carpet; keep it in the anti-static bag until you need it. Hold the RAM by the edges and push it into the slot until the clips lock.',
  fair: 'Static electricity can damage the memory, so the student should not work on the carpet or wear the sweater. Turn off the computer and use a wrist strap while working. Insert the memory into the slot carefully and close the latches so that the module does not come out of the slot.',
  complete: 'There is a risk of electric shock because the computer is plugged in, and of electrostatic discharge because of the carpet, the wool sweater and the bare memory modules. I would turn the computer off, unplug it, ground myself with a wrist strap clipped to the chassis and work on an anti-static mat. I would return the modules to their bags until needed, hold them by the edges, align the notch and press until both latches lock.',
  weak: 'You should be careful because the computer can be damaged if you are not careful. Turn it off before you start and then put the RAM in the right slot. Push the RAM down hard so that it goes inside, then close the computer and test if it works properly after the upgrade.',
  solid: 'Static from the carpet and the wool sweater can damage the RAM chips, and the plugged-in computer is a shock hazard. Unplug the power cord, move to a table, wear a grounded wrist strap and keep the modules in their anti-static bags. Install each module by matching the notch with the key and pressing evenly until the latches close.',
  brief: 'The computer must be unplugged first and the student should wear an anti-static wrist strap because static electricity can damage the memory modules. The modules should not be left on the carpet. Put the memory in the slots and press down until the latches click into place.',
  careful: 'Electrostatic discharge from the carpet and the sweater can damage the modules, and the computer is still connected to power. I would shut it down, unplug it, wear a wrist strap on the bare metal of the case and work on an anti-static mat. I would hold the modules by their edges, line up the notch and push both ends down until the latches lock.',
};

const CHECKLISTS = {
  full: ['Shut down the computer, switch off the PSU and unplug the power cord.', 'Work on an anti-static mat and clip the wrist strap to bare chassis metal.', 'Inspect the case, motherboard, CPU, cooler, RAM, PSU and drive for damage.', 'Open the CPU lever, align the triangle marker, seat the CPU and close the lever.', 'Apply thermal compound, mount the cooler and connect the fan to CPU_FAN.', 'Open the DIMM latches and seat both modules in DIMM_A2 and DIMM_B2 until the latches lock.', 'Install and fasten the PSU, then fit the I/O shield.', 'Place the motherboard on the standoffs and fasten its screws.', 'Install and fasten the storage drive.', 'Connect the 24-pin ATX, 8-pin EPS, SATA power, SATA data and front-panel cables, then tie the cables.', 'Power on and confirm the POST detects the CPU, memory, fan and boot drive.'],
  good: ['Unplug the computer and switch off the power supply.', 'Wear a grounded anti-static wrist strap and use the anti-static mat.', 'Check all parts before installing them.', 'Seat the CPU with the triangle aligned and close the lever.', 'Apply thermal paste and install the cooler; connect the CPU fan.', 'Install the RAM in the dual-channel slots until the latches click.', 'Install the PSU, the I/O shield and the motherboard on the standoffs.', 'Install the drive and connect the power and data cables.', 'Turn on the computer and check the POST screen.'],
  basic: ['Unplug the PC and wear a wrist strap.', 'Put the CPU in the socket using the triangle and lock the lever.', 'Put thermal paste and attach the cooler and its fan cable.', 'Install the memory sticks and lock the latches.', 'Mount the power supply in the case.', 'Screw the motherboard onto the standoffs.', 'Install the hard drive and connect the SATA cables.', 'Connect the 24-pin and CPU power cables and test the computer.'],
  short: ['Turn off the computer.', 'Use an anti-static strap.', 'Install the processor.', 'Install the cooler.', 'Install the RAM.', 'Install the power supply.', 'Install the motherboard and the drive.', 'Connect the cables and power on.'],
  steady: ['Power off and unplug the computer, then press the power button to drain residual power.', 'Ground myself with the wrist strap on the chassis and work on the mat.', 'Inspect every component and keep them in anti-static bags until used.', 'Install the CPU (marker aligned) and close the retention lever.', 'Apply compound, mount the cooler and plug in the CPU_FAN cable.', 'Seat two RAM modules in the recommended slots and lock the latches.', 'Install the PSU, I/O shield, motherboard and drive with their screws.', 'Connect ATX, EPS, SATA and front-panel cables.', 'Run the power-on self-test and record the result.'],
  partial: ['Unplug the system unit.', 'Wear the wrist strap.', 'Install the CPU and cooler.', 'Install the RAM.', 'Install the PSU.', 'Install the motherboard.', 'Install the storage drive.', 'Plug in the cables and power on the computer.'],
};

const checklist = (key) => CHECKLISTS[key].map((step, index) => `${index + 1}. ${step}`).join('\n');

// ---------------------------------------------------------------------------
// Activity mix per learner (varied so learner statuses differ).
// ---------------------------------------------------------------------------
// Practice: a step is a lesson ({topic}), a mission ({mission, mistakes,
// failAfter: phases after which the learner presses Verify too early,
// stopAfterFailures, partialActions}) or the COC practice quiz ({cocQuiz}).
export const PRACTICE = {
  L01: [{ topic: 'esd' }, { mission: 'coc1_m1' }, { mission: 'coc1_m2', mistakes: ['cpu_orientation'], failAfter: ['coc1_m2_p3'] }, { mission: 'coc1_m3' }, { mission: 'coc1_m4' }, { mission: 'coc1_m5' }, { cocQuiz: 'coc1' }],
  L02: [{ topic: 'esd' }, { mission: 'coc1_m1' }, { mission: 'coc1_m2' }, { mission: 'coc1_m3' }, { mission: 'coc1_m4' }],
  L03: [{ topic: 'esd' }, { mission: 'coc1_m1', mistakes: ['wrong_tool'] }, { mission: 'coc1_m2' }, { mission: 'coc1_m3' }],
  L04: [{ topic: 'esd' }, { mission: 'coc1_m1' }, { mission: 'coc1_m2' }],
  L05: [{ topic: 'esd' }, { mission: 'coc1_m1' }, { mission: 'coc1_m2', failAfter: ['coc1_m2_p2'] }],
  L06: [{ mission: 'coc1_m1' }, { mission: 'coc1_m2' }],
  L07: [{ topic: 'esd' }, { mission: 'coc1_m1' }, { mission: 'coc1_m2', failAfter: ['coc1_m2_p1', 'coc1_m2_p2', 'coc1_m2_p3'], stopAfterFailures: true }],
  L08: [{ topic: 'esd' }, { mission: 'coc1_m1' }, { mission: 'coc1_m2' }],
  L09: [{ mission: 'coc1_m1' }, { mission: 'coc1_m2', mistakes: ['ram_reseat'] }],
  L10: [{ topic: 'esd' }, { mission: 'coc1_m1' }],
  L11: [{ mission: 'coc1_m1', failAfter: ['coc1_m1_p1'], stopAfterFailures: true }],
  L12: [{ mission: 'coc1_m1', partialActions: 2 }],
};

// COC1 M2 simulation assessment: the run each learner submits and the
// Evaluation Center stage the instructor leaves it in.
export const ASSESSMENT = {
  title: `${PREFIX}COC1 M2 assembly assessment`,
  instructions: 'Assemble the computer on the simulation bench without hints and submit when you have finished. Unfinished steps are evaluated as not satisfied.',
  takers: {
    L01: { run: 'perfect', stage: 'released' },
    L02: { run: 'perfect', stage: 'release' },
    L03: { run: 'cpu_two_errors', stage: 'finalize', note: 'Two CPU placements were refused before the correct orientation; the CPU step is safety-critical and must be correct on the first attempt.' },
    L04: { run: 'ram_three_corrections', stage: 'evaluate' },
    L05: { run: 'perfect', stage: 'evaluate' },
    L08: { run: 'ram_three_corrections', stage: 'released', note: 'The memory was reseated three times before the latches locked; the step allows at most two incorrect attempts.' },
    L09: { run: 'unfinished', stage: 'evaluate' },
  },
};

// Quiz: answers per item ('correct' or the index of a wrong option / the
// wrong true-false value), the essay text, the stage and the essay scores.
export const QUIZ_TAKERS = {
  L01: { answers: { q1: 'correct', q2: 'correct', q3: 'correct', q4: 'correct', q5: 'correct' }, essay: 'strong', stage: 'released', scores: { C1: 4, C2: 4, C3: 2 }, feedback: 'Complete and accurate: every hazard is named and the preparation and installation steps are in the right order.' },
  L02: { answers: { q1: 'correct', q2: 'correct', q3: 'correct', q4: 'correct', q5: 1 }, essay: 'good', stage: 'released', scores: { C1: 4, C2: 3, C3: 1 }, feedback: 'Hazards and preparation are correct. Mention keeping the modules in anti-static bags and using the recommended dual-channel slots.' },
  L03: { answers: { q1: 'correct', q2: 'correct', q3: 'correct', q4: 'correct', q5: 'correct' }, essay: 'decent', stage: 'release', scores: { C1: 3, C2: 3, C3: 1 }, feedback: 'Good safety steps. Describe aligning the notch with the slot key and the recommended slots.' },
  L04: { answers: { q1: 'correct', q2: 2, q3: 'true', q4: 'correct', q5: 'correct' }, essay: 'fair', stage: 'finalize', scores: { C1: 3, C2: 2, C3: 1 }, feedback: 'Turning the computer off is not enough: unplug it. Add the anti-static mat and notch alignment.' },
  L05: { answers: { q1: 'correct', q2: 'correct', q3: 'correct', q4: 'correct', q5: 'correct' }, essay: 'complete', stage: 'evaluate' },
  L06: { answers: { q1: 1, q2: 3, q3: 'correct', q4: 'correct', q5: 1 }, essay: 'weak', stage: 'released', scores: { C1: 1, C2: 1, C3: 1 }, feedback: 'Name the hazards (power still connected, static from the carpet and sweater). Never force a module: align the notch and press evenly.' },
  L07: { answers: { q1: 'correct', q2: 'correct', q3: 'true', q4: 'correct', q5: 2 }, essay: 'solid', stage: 'evaluate' },
  L08: { answers: { q1: 'correct', q2: 'correct', q3: 'correct', q4: 'false', q5: 'correct' }, essay: 'brief', stage: 'finalize', scores: { C1: 2, C2: 2, C3: 1 }, feedback: 'Correct start. Explain the shock hazard, the work surface and how to align the module before pressing it.' },
  L09: { answers: { q1: 2, q2: 'correct', q3: 'true', q4: 'correct', q5: 'correct' }, essay: 'careful', stage: 'evaluate' },
  // Starts, saves three answers and leaves: the server submits it
  // automatically when the 15-minute time limit runs out.
  L10: { answers: { q1: 'correct', q2: 'correct', q3: 'true' }, essay: null, abandon: true },
};

// Homework: on time, late (after the deadline) or missing; the stage and
// the criterion scores the instructor records.
export const HOMEWORK_TAKERS = {
  L01: { when: 'on_time', answer: 'full', stage: 'released', scores: { C1: 10, C2: 10 }, feedback: 'Complete, correctly ordered checklist with every safety precaution and the power-on check.' },
  L02: { when: 'on_time', answer: 'good', stage: 'released', scores: { C1: 9, C2: 7 }, feedback: 'Safety steps are complete. List the cable connections (ATX, EPS, SATA, front panel) separately.' },
  L03: { when: 'on_time', answer: 'steady', stage: 'release', scores: { C1: 8, C2: 7 }, feedback: 'Good order and safety steps. Name the memory slots (DIMM_A2/DIMM_B2) and the devices the POST must detect.' },
  L04: { when: 'on_time', answer: 'basic', stage: 'finalize', scores: { C1: 6, C2: 6 }, feedback: 'Add the anti-static mat, part inspection and the I/O shield to the sequence.' },
  L05: { when: 'on_time', answer: 'good', stage: 'evaluate' },
  L06: { when: 'on_time', answer: 'short', stage: 'evaluate' },
  L07: { when: 'late', answer: 'good', stage: 'released', scores: { C1: 7, C2: 7 }, feedback: 'Submitted after the deadline. Safety steps are correct; list each cable connection and record the POST result.' },
  L08: { when: 'late', answer: 'partial', stage: 'finalize', scores: { C1: 6, C2: 5 }, feedback: 'Submitted after the deadline. Add the anti-static mat, part inspection and the order of the cable connections.' },
  L09: { when: 'late', answer: 'basic', stage: 'evaluate' },
};

export const LEADERBOARD_OPT_IN = ['L01', 'L02', 'L03', 'L05'];

// ---------------------------------------------------------------------------
// Action generators (reused from scripts/test-practice-api-all-missions.mjs:
// the Flutter-exported work orders of tool/export_practice_test_evidence.dart,
// with the same untrusted keys removed).
// ---------------------------------------------------------------------------
const UNTRUSTED_VALUE_KEYS = ['equipment_snapshot', 'measured_result', 'measured_fact', 'measured_tool_result'];

export function fixtureActions(fixtures, mission) {
  const actions = fixtures?.[mission];
  if (!Array.isArray(actions) || !actions.length) throw new Error(`The practice fixtures have no work order for ${mission}.`);
  return actions.map((action) => {
    const value = { ...action.value };
    for (const key of UNTRUSTED_VALUE_KEYS) delete value[key];
    return { phaseId: action.phaseId, actionType: action.actionType, target: action.target ?? null, value };
  });
}

function insertBefore(actions, anchor, extra, label) {
  const index = actions.indexOf(anchor);
  if (index < 0) throw new Error(`The ${label} mistake has no anchor action in the work order.`);
  return [...actions.slice(0, index), ...extra, ...actions.slice(index)];
}

/** Realistic, physically possible mistakes a learner makes and corrects. */
export const MISTAKES = {
  // A CPU placed in the socket in a wrong orientation is refused (counted
  // invalid by the server replay) before the learner rotates it correctly.
  cpu_orientation(actions, count = 1) {
    const cpu = actions.find((action) => action.actionType === 'placement_attempted' && action.value.item_id === 'cpu');
    if (!cpu) throw new Error('The COC1 M2 work order has no CPU placement.');
    const wrong = ['90', '180', '270'].slice(0, count).map((orientation) => ({
      ...cpu,
      value: { ...cpu.value, orientation, compatible: false, simulation_valid: false },
    }));
    return insertBefore(actions, cpu, wrong, 'CPU orientation');
  },
  // Memory first seated in DIMM_A1 (physically possible), then removed and
  // reseated in the recommended slot: a correction counted by the replay.
  ram_reseat(actions, count = 1) {
    const ram = actions.find((action) => action.actionType === 'placement_attempted' && action.value.item_id === 'ram_1');
    if (!ram) throw new Error('The COC1 M2 work order has no memory placement.');
    const extra = [];
    for (let index = 0; index < count; index++) {
      extra.push({ ...ram, target: 'dimm_a1', value: { ...ram.value, destination_id: 'dimm_a1' } });
      extra.push({ phaseId: ram.phaseId, actionType: 'placement_removed', target: 'ram_1', value: { item_id: 'ram_1', simulation_valid: true, runtime_action_type: 'placement_removed' } });
    }
    return insertBefore(actions, ram, extra, 'memory reseat');
  },
  // The screwdriver applied to the ESD ground point is refused before the
  // wrist strap is clipped on (COC1 M1 tool phase).
  wrong_tool(actions) {
    const strap = actions.find((action) => action.actionType === 'tool_attempted' && action.value.tool_id === 'anti_static_strap');
    if (!strap) throw new Error('The COC1 M1 work order has no wrist-strap tool action.');
    const wrong = { ...strap, value: { tool_id: 'screwdriver', compatible: false, simulation_valid: false, runtime_action_type: 'tool_attempted' } };
    return insertBefore(actions, strap, [wrong], 'wrong tool');
  },
};

/** The ordered practice actions of one mission step, mistakes included. */
export function practicePlan(fixtures, step) {
  let actions = fixtureActions(fixtures, step.mission);
  for (const mistake of step.mistakes ?? []) actions = MISTAKES[mistake](actions);
  if (step.partialActions) actions = actions.slice(0, step.partialActions);
  const segments = [];
  let start = 0;
  for (const phase of step.failAfter ?? []) {
    const end = actions.findLastIndex((action) => action.phaseId === phase) + 1;
    if (end <= start) throw new Error(`${step.mission}: no actions of ${phase} to verify after.`);
    segments.push({ actions: actions.slice(start, end), verify: 'fail' });
    start = end;
  }
  if (!step.stopAfterFailures && start < actions.length) {
    segments.push({ actions: actions.slice(start), verify: step.partialActions ? 'none' : 'pass' });
  }
  return { actions, segments };
}

/** The COC1 M2 assessment actions for a named run (proven by the SQL lifecycle suite). */
export function assessmentPlan(fixtures, run) {
  let actions = fixtureActions(fixtures, 'coc1_m2');
  if (run === 'cpu_two_errors') actions = MISTAKES.cpu_orientation(actions, 2);
  else if (run === 'ram_three_corrections') actions = MISTAKES.ram_reseat(actions, 3);
  else if (run === 'unfinished') actions = actions.filter((action) => ['coc1_m2_p1', 'coc1_m2_p2'].includes(action.phaseId));
  else if (run !== 'perfect') throw new Error(`Unknown assessment run ${run}.`);
  return actions;
}

/** Deterministic UUID (v4 layout) so retried starts and submissions are idempotent. */
export function stableUuid(...parts) {
  const hex = createHash('sha256').update(parts.join('|')).digest('hex');
  const variant = ((parseInt(hex[16], 16) & 0x3) | 0x8).toString(16);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-${variant}${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
function fail(message) { throw new Error(message); }
const say = (message) => console.log(message);
const stepLog = (scope, message) => console.log(`  ${scope.padEnd(10)} ${message}`);

function parseArgs(argv) {
  const options = { target: 'local', confirm: false, remove: false, archiveTopics: false, publishTopics: false, summaryOnly: false,
    instructorEmail: null, adminEmail: null, webUrl: null, fixtures: DEFAULT_FIXTURES, qaAccounts: DEFAULT_QA_ACCOUNTS, paceMs: 150 };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    const next = () => { const value = argv[++index]; if (!value || value.startsWith('--')) fail(`${arg} needs a value.`); return value; };
    if (arg === '--target') options.target = next();
    else if (arg === '--confirm') options.confirm = true;
    else if (arg === '--remove') options.remove = true;
    else if (arg === '--archive-topics') options.archiveTopics = true;
    else if (arg === '--publish-topics') options.publishTopics = true;
    else if (arg === '--summary-only') options.summaryOnly = true;
    else if (arg === '--instructor-email') options.instructorEmail = next().toLowerCase();
    else if (arg === '--admin-email') options.adminEmail = next().toLowerCase();
    else if (arg === '--web-url') options.webUrl = next();
    else if (arg === '--practice-fixtures') options.fixtures = path.resolve(next());
    else if (arg === '--qa-accounts') options.qaAccounts = path.resolve(next());
    else if (arg === '--pace-ms') options.paceMs = Math.max(0, Number(next()) || 0);
    else if (arg === '--help' || arg === '-h') options.help = true;
    else fail(`Unknown argument ${arg}. Use --help.`);
  }
  if (!['local', 'hosted'].includes(options.target)) fail('--target must be local or hosted.');
  return options;
}

const HELP = `Seeds the labelled re-defense demo class (see docs/DEMO_DATA.md).
  node scripts/seed-demo-class.mjs [--summary-only | --remove [--archive-topics]]
      Local stack (supabase status) and the local dashboard at ${LOCAL_WEB}.
      Staff: qa.instructor / qa.admin from .tmp/local-qa-accounts.json (--qa-accounts <file>).
  node scripts/seed-demo-class.mjs --target hosted --confirm --instructor-email <email> --admin-email <email> [--publish-topics]
      Needs NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY (or _PUBLISHABLE_KEY), SUPABASE_SERVICE_ROLE_KEY,
      BYTEQUEST_DEMO_WEB_URL (or --web-url), BYTEQUEST_DEMO_INSTRUCTOR_PASSWORD and BYTEQUEST_DEMO_ADMIN_PASSWORD.
  Options: --practice-fixtures <file> (default .tmp/demo-practice-evidence.json), --web-url <url>, --pace-ms <ms>.`;

function isLocalHost(value) {
  return ['127.0.0.1', 'localhost'].includes(new URL(value).hostname);
}

function localStatus() {
  const raw = execSync('supabase status -o json', { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], shell: true });
  return JSON.parse(raw.slice(raw.indexOf('{'), raw.lastIndexOf('}') + 1));
}

function resolveTarget(options) {
  if (options.target === 'local') {
    let status;
    try { status = localStatus(); } catch { fail('The local Supabase stack is not reachable (supabase status failed).'); }
    if (status.API_URL !== LOCAL_API) fail(`Refusing a non-local Supabase target: ${status.API_URL}`);
    const web = options.webUrl ?? LOCAL_WEB;
    if (!isLocalHost(web)) fail('The local target needs a 127.0.0.1/localhost dashboard URL.');
    if (options.publishTopics) say('Note: --publish-topics only matters for the hosted target; local runs always publish the first lesson.');
    const qa = fs.existsSync(options.qaAccounts) ? JSON.parse(fs.readFileSync(options.qaAccounts, 'utf8')).accounts ?? {} : {};
    const staff = (key, email) => {
      const account = Object.values(qa).find((item) => item.email === email) ?? qa[key];
      if (!account?.password) fail(`No local password for ${email}: run node scripts/local-qa-fixtures.mjs or pass --qa-accounts <file>.`);
      return { email: account.email, password: account.password };
    };
    return {
      kind: 'local', url: status.API_URL, anon: status.ANON_KEY, serviceKey: status.SERVICE_ROLE_KEY, web,
      instructor: staff('instructor', options.instructorEmail ?? 'qa.instructor@bytequest.local'),
      admin: staff('admin', options.adminEmail ?? 'qa.admin@bytequest.local'),
      publishTopics: true,
    };
  }
  if (!options.confirm) fail('A hosted run requires --target hosted --confirm --instructor-email <email>.');
  if (!options.instructorEmail) fail('A hosted run requires --instructor-email <email>.');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const web = options.webUrl ?? process.env.BYTEQUEST_DEMO_WEB_URL;
  if (!url || !anon || !serviceKey || !web) fail('The hosted target needs NEXT_PUBLIC_SUPABASE_URL, the anon key, SUPABASE_SERVICE_ROLE_KEY and BYTEQUEST_DEMO_WEB_URL.');
  if (isLocalHost(url) || new URL(url).protocol !== 'https:') fail('--target hosted needs the https URL of the hosted project.');
  if (isLocalHost(web) || new URL(web).protocol !== 'https:') fail('--target hosted needs the https URL of the deployed dashboard.');
  if (!process.env.BYTEQUEST_DEMO_INSTRUCTOR_PASSWORD) fail('Set BYTEQUEST_DEMO_INSTRUCTOR_PASSWORD for the demo instructor.');
  if (!options.adminEmail || !process.env.BYTEQUEST_DEMO_ADMIN_PASSWORD) fail('A hosted run requires --admin-email <email> and BYTEQUEST_DEMO_ADMIN_PASSWORD (curriculum workflow).');
  return {
    kind: 'hosted', url, anon, serviceKey, web,
    instructor: { email: options.instructorEmail, password: process.env.BYTEQUEST_DEMO_INSTRUCTOR_PASSWORD },
    admin: { email: options.adminEmail, password: process.env.BYTEQUEST_DEMO_ADMIN_PASSWORD },
    publishTopics: options.publishTopics,
  };
}

async function authRetry(run, label) {
  for (let attempt = 1; ; attempt++) {
    const result = await run();
    const error = result?.error;
    const limited = error && (error.status === 429 || /rate limit/i.test(error.message ?? ''));
    if (!limited || attempt >= 8) return result;
    stepLog('auth', `${label}: rate limited, waiting 40 s (attempt ${attempt})`);
    await sleep(40_000);
  }
}

function newPassword() {
  return `Demo-${randomBytes(12).toString('base64url')}-7q`;
}

function readAccountStore() {
  if (!fs.existsSync(ACCOUNT_FILE)) return { learners: {} };
  try { return { learners: {}, ...JSON.parse(fs.readFileSync(ACCOUNT_FILE, 'utf8')) }; } catch { return { learners: {} }; }
}

function writeAccountStore(ctx, store) {
  fs.mkdirSync(path.dirname(ACCOUNT_FILE), { recursive: true });
  const content = { note: 'Synthetic re-defense demo learners (gitignored). Never commit this file.', target: ctx.target.kind, api: ctx.target.url, updated_at: new Date().toISOString(), learners: store.learners };
  fs.writeFileSync(ACCOUNT_FILE, `${JSON.stringify(content, null, 2)}\n`);
}

function rpcError(fn, error) {
  return new Error(`${fn} failed: ${error.message ?? error.code ?? JSON.stringify(error)}`);
}

async function rpc(client, fn, args) {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw rpcError(fn, error);
  return data;
}

async function rows(query, label) {
  const { data, error } = await query;
  if (error) throw new Error(`${label}: ${error.message}`);
  return data ?? [];
}

/** A staff member signed in through the dashboard's SSR cookie session. */
async function staffSession(ctx, account, role, createServerClient) {
  const jar = new Map();
  const client = createServerClient(ctx.target.url, ctx.target.anon, {
    cookies: {
      getAll: () => Array.from(jar, ([name, value]) => ({ name, value })),
      setAll: (cookies) => {
        for (const cookie of cookies) {
          if (cookie.options?.maxAge === 0 || cookie.value === '') jar.delete(cookie.name);
          else jar.set(cookie.name, cookie.value);
        }
      },
    },
  });
  const { data, error } = await authRetry(() => client.auth.signInWithPassword(account), `sign in ${account.email}`);
  if (error || !data.user) fail(`Could not sign in ${account.email}: ${error?.message ?? 'no user'}`);
  const profile = (await rows(client.from('profiles').select('role,status,full_name').eq('user_id', data.user.id), 'staff profile'))[0];
  if (profile?.role !== role || profile.status !== 'active') fail(`${account.email} must be an active ${role} (found ${profile?.role}/${profile?.status}).`);
  const session = {
    staff: true, id: data.user.id, email: account.email, name: profile.full_name, client, jar,
    cookieHeader: () => Array.from(jar, ([name, value]) => `${name}=${value}`).join('; '),
    async fresh() {
      const { data: current } = await client.auth.getSession();
      if (current.session && current.session.expires_at * 1000 - Date.now() < 5 * 60_000) await client.auth.refreshSession();
    },
    absorb(response) {
      if (typeof response.headers.getSetCookie !== 'function') return;
      for (const value of response.headers.getSetCookie()) {
        const [pair] = value.split(';', 1);
        const separator = pair.indexOf('=');
        if (separator <= 0) continue;
        const name = pair.slice(0, separator).trim();
        const cookieValue = pair.slice(separator + 1);
        if (cookieValue) jar.set(name, cookieValue); else jar.delete(name);
      }
    },
  };
  return session;
}

/** A learner signed in exactly as the mobile app is (bearer token). */
function learnerSession(ctx, spec, createClient) {
  const client = createClient(ctx.target.url, ctx.target.anon, { auth: { persistSession: false, autoRefreshToken: false } });
  let current = null;
  return {
    staff: false, spec, client, get id() { return spec.id; },
    adopt(session) { current = session; return client.auth.setSession({ access_token: session.access_token, refresh_token: session.refresh_token }); },
    async token() {
      if (!current) {
        const { data, error } = await authRetry(() => client.auth.signInWithPassword({ email: spec.email, password: spec.password }), `sign in ${spec.email}`);
        if (error || !data.session) fail(`Could not sign in ${spec.email}: ${error?.message ?? 'no session'}`);
        current = data.session;
      } else if (current.expires_at * 1000 - Date.now() < 5 * 60_000) {
        const { data, error } = await client.auth.refreshSession();
        if (error || !data.session) fail(`Could not refresh the session of ${spec.email}: ${error?.message}`);
        current = data.session;
      }
      return current.access_token;
    },
  };
}

/** Calls a dashboard route as the given actor (staff: cookies; learner: bearer). */
async function call(ctx, actor, method, pathname, { json, form, expect } = {}) {
  const headers = new Headers();
  if (actor?.staff) { await actor.fresh(); headers.set('cookie', actor.cookieHeader()); }
  else if (actor) headers.set('authorization', `Bearer ${await actor.token()}`);
  let body;
  if (json !== undefined) { headers.set('content-type', 'application/json'); body = JSON.stringify(json); }
  else if (form) body = form;
  const response = await fetch(new URL(pathname, ctx.target.web), { method, headers, body, redirect: 'manual', signal: AbortSignal.timeout(120_000) });
  if (actor?.staff) actor.absorb(response);
  const buffer = Buffer.from(await response.arrayBuffer());
  let data = null;
  if ((response.headers.get('content-type') ?? '').includes('json')) {
    try { data = JSON.parse(buffer.toString('utf8')); } catch { data = null; }
  }
  if (expect && !expect.includes(response.status)) {
    fail(`${method} ${pathname} returned ${response.status}: ${JSON.stringify(data ?? buffer.toString('utf8').slice(0, 300))}`);
  }
  return { status: response.status, data, buffer };
}

// ---------------------------------------------------------------------------
// Context and lookups
// ---------------------------------------------------------------------------
async function buildContext(options) {
  const target = resolveTarget(options);
  say(`Target: ${target.kind} · Supabase ${target.url} · dashboard ${target.web}`);
  say(`        instructor ${target.instructor.email} · admin ${target.admin.email} · topics ${target.publishTopics ? 'published + approved' : 'approved only'}`);
  const { createClient } = await import('@supabase/supabase-js');
  const { createServerClient } = await import('@supabase/ssr');
  const service = createClient(target.url, target.serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const login = await fetch(new URL('/login', target.web), { redirect: 'manual', signal: AbortSignal.timeout(30_000) }).catch(() => null);
  if (!login || login.status >= 500) fail(`The dashboard at ${target.web} is not reachable; start it against this Supabase project first.`);
  const ctx = { options, target, service, createClient, instructor: null, admin: null, learners: new Map(), ids: {}, notes: [] };
  ctx.instructor = await staffSession(ctx, target.instructor, 'instructor', createServerClient);
  ctx.admin = await staffSession(ctx, target.admin, 'admin', createServerClient);
  const [modules, outcomes, cocs, contracts] = await Promise.all([
    rows(service.from('curriculum_modules').select('id,coc_code,code,title'), 'curriculum modules'),
    rows(service.from('learning_outcomes').select('id,module_id,code'), 'learning outcomes'),
    rows(service.from('coc_modules').select('id,coc_code,title'), 'COC modules'),
    rows(service.from('practice_mission_contracts').select('mission_id,version,definition'), 'practice contracts'),
  ]);
  const lo11 = modules.find((item) => item.code === 'LO1.1');
  if (!lo11) fail('Curriculum module LO1.1 is missing; apply the curriculum migrations first.');
  ctx.ids.lo11 = lo11.id;
  ctx.ids.coc1 = cocs.find((item) => item.coc_code === 'coc1')?.id;
  ctx.outcome = (code) => outcomes.find((item) => item.module_id === lo11.id && item.code === code)?.id ?? fail(`PC ${code} of LO1.1 is missing.`);
  ctx.contracts = new Map(contracts.map((row) => [row.mission_id, row]));
  return ctx;
}

function loadFixtures(ctx) {
  const file = ctx.options.fixtures;
  if (!fs.existsSync(file)) {
    const mobile = path.join(ROOT, 'ByteQuest-Mobile-App');
    if (fs.existsSync(path.join(mobile, '.dart_tool', 'package_config.json'))) {
      say(`Exporting the practice work orders to ${path.relative(ROOT, file)} (dart run tool/export_practice_test_evidence.dart)…`);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const result = spawnSync('dart', ['run', 'tool/export_practice_test_evidence.dart', file], { cwd: mobile, stdio: 'inherit', shell: process.platform === 'win32' });
      if (result.status !== 0) fail('The practice fixture export failed.');
    } else {
      fail(`Practice fixtures not found at ${file}. Generate them first:\n  cd ByteQuest-Mobile-App && flutter pub get && dart run tool/export_practice_test_evidence.dart ../.tmp/demo-practice-evidence.json\n(or run the same command inside the Flutter container; see docs/DEMO_DATA.md).`);
    }
  }
  const fixtures = JSON.parse(fs.readFileSync(file, 'utf8'));
  // The work orders must match the contracts the server verifies against.
  for (const mission of ['coc1_m1', 'coc1_m2', 'coc1_m3', 'coc1_m4', 'coc1_m5']) {
    const contract = ctx.contracts.get(mission);
    if (!contract) fail(`No published practice contract for ${mission}.`);
    const phases = new Set((contract.definition.phases ?? []).map((phase) => phase.id));
    const used = new Set(fixtureActions(fixtures, mission).map((action) => action.phaseId));
    const missing = [...used].filter((phase) => !phases.has(phase));
    const unworked = (contract.definition.phases ?? []).filter((phase) => phase.primaryInteraction !== 'review' && !used.has(phase.id)).map((phase) => phase.id);
    if (missing.length || unworked.length) {
      fail(`The practice fixtures do not match the ${mission} contract ${contract.version} (unknown ${missing.join(',') || '-'}, unworked ${unworked.join(',') || '-'}); regenerate them.`);
    }
  }
  return fixtures;
}

/** The learner's signed-in session (signs in or refreshes before direct reads). */
async function learner(ctx, key) {
  const session = ctx.learners.get(key);
  if (!session) fail(`Learner ${key} has no session.`);
  await session.token();
  return session;
}

async function demoClass(ctx) {
  const found = await rows(ctx.service.from('classes').select('id,title,class_code,status,instructor_id').ilike('class_code', CLASS_CODE), 'demo class');
  return found[0] ?? null;
}

// ---------------------------------------------------------------------------
// Phases
// ---------------------------------------------------------------------------
async function ensureAccounts(ctx, specs) {
  const store = readAccountStore();
  const existing = await rows(ctx.service.from('profiles').select('user_id,email,role,status,full_name').in('email', specs.map((spec) => spec.email)), 'learner profiles');
  for (const base of specs) {
    const spec = { ...base };
    const profile = existing.find((row) => row.email.toLowerCase() === spec.email);
    const session = learnerSession(ctx, spec, ctx.createClient);
    if (profile) {
      if (profile.role !== 'learner') fail(`${spec.email} belongs to a ${profile.role} account; refusing to use it.`);
      if (profile.status !== 'active') fail(`${spec.email} is ${profile.status} (the demo was removed). Nothing was changed.`);
      spec.id = profile.user_id;
      spec.password = store.learners[spec.key]?.password;
      if (!spec.password) {
        spec.password = newPassword();
        const { error } = await ctx.service.auth.admin.updateUserById(spec.id, { password: spec.password });
        if (error) fail(`Could not reset the password of ${spec.email}: ${error.message}`);
        stepLog(spec.key, 'existing account: password reset (credentials were not in .tmp/demo-accounts.json)');
      } else {
        stepLog(spec.key, `account exists (${spec.email})`);
      }
      if (profile.full_name !== spec.name) await renameLearner(session, spec, profile.full_name);
    } else {
      spec.password = newPassword();
      const { data, error } = await authRetry(() => session.client.auth.signUp({ email: spec.email, password: spec.password, options: { data: { full_name: spec.name, email: spec.email } } }), `sign up ${spec.email}`);
      if (error || !data.user) fail(`Sign-up of ${spec.email} failed: ${error?.message ?? 'no user'}`);
      spec.id = data.user.id;
      if (data.session) await session.adopt(data.session);
      else {
        // Hosted projects that require email confirmation: confirm with the
        // service role (account administration), then sign in normally.
        const { error: confirmError } = await ctx.service.auth.admin.updateUserById(spec.id, { email_confirm: true });
        if (confirmError) fail(`Could not confirm ${spec.email}: ${confirmError.message}`);
      }
      stepLog(spec.key, `signed up ${spec.email} (${spec.name})`);
    }
    store.learners[spec.key] = { email: spec.email, name: spec.name, student_id: spec.studentId, user_id: spec.id, password: spec.password };
    writeAccountStore(ctx, store);
    ctx.learners.set(spec.key, session);
  }
}

/**
 * Renames an already-seeded learner (for example one created with an earlier
 * name template) exactly as the app's Edit profile screen does: the learner's
 * own update of profiles.full_name. The leaderboard entry follows through the
 * server's profile trigger.
 */
async function renameLearner(session, spec, previous) {
  await session.token();
  const { error } = await session.client.from('profiles').update({ full_name: spec.name }).eq('user_id', spec.id);
  if (error) fail(`${spec.key} could not update the profile name: ${error.message}`);
  const current = (await rows(session.client.from('profiles').select('full_name').eq('user_id', spec.id), 'own profile'))[0];
  if (current?.full_name !== spec.name) fail(`${spec.key}: the profile name is still "${current?.full_name}" after the update.`);
  stepLog(spec.key, `renamed "${previous}" → "${spec.name}" (own profile update, as the app's Edit profile does)`);
}

async function ensureClass(ctx) {
  let row = await demoClass(ctx);
  if (row) {
    if (row.instructor_id !== ctx.instructor.id) fail(`Class ${CLASS_CODE} belongs to another instructor; refusing to use it.`);
    if (row.status !== 'active') fail(`Class ${CLASS_CODE} is ${row.status} (the demo was removed). Nothing was changed.`);
    stepLog('class', `exists: ${row.title} (${row.id})`);
  } else {
    row = await rpc(ctx.instructor.client, 'create_class', { p_title: CLASS_TITLE, p_class_code: CLASS_CODE });
    stepLog('class', `created ${row.title} (${row.id})`);
  }
  ctx.ids.class = row.id;
}

async function rosterState(ctx) {
  const [members, entries] = await Promise.all([
    rows(ctx.instructor.client.from('class_memberships').select('learner_id,status').eq('class_id', ctx.ids.class), 'memberships'),
    rows(ctx.instructor.client.from('class_roster_entries').select('email_normalized,status').eq('class_id', ctx.ids.class), 'roster entries'),
  ]);
  return { members, entries };
}

async function ensureRoster(ctx) {
  const { members, entries } = await rosterState(ctx);
  const covered = LEARNERS.every((spec) => {
    const id = ctx.learners.get(spec.key)?.id;
    return (id && members.some((row) => row.learner_id === id && row.status === 'active')) || entries.some((row) => row.email_normalized === spec.email);
  });
  if (covered) { stepLog('roster', 'every demo learner is enrolled or pending; import skipped'); return; }
  const XLSX = createRequire(path.join(ROOT, 'ByteQuest-Web-Dashboard', 'package.json'))('xlsx');
  // Download the dashboard's template and fill in the twelve learners.
  const template = await call(ctx, ctx.instructor, 'GET', '/api/roster/template', { expect: [200] });
  const book = XLSX.read(template.buffer, { type: 'buffer' });
  const sheet = book.Sheets.Roster ?? fail('The roster template has no Roster sheet.');
  XLSX.utils.sheet_add_aoa(sheet, LEARNERS.map((spec) => [spec.studentId, spec.lastName, spec.firstName, spec.email, COURSE_SECTION]), { origin: -1 });
  const bytes = XLSX.write(book, { type: 'buffer', bookType: 'xlsx', compression: true });
  const upload = (extra = {}) => {
    const form = new FormData();
    form.set('file', new File([bytes], 'demo-redefense-roster.xlsx', { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
    for (const [key, value] of Object.entries(extra)) form.set(key, value);
    return form;
  };
  const preview = await call(ctx, ctx.instructor, 'POST', `/api/roster/${ctx.ids.class}/preview`, { form: upload(), expect: [200] });
  const summary = preview.data.preview.summary;
  stepLog('roster', `preview: enroll now ${summary.enroll_now}, pending ${summary.pending}, already ${summary.already_enrolled}, invalid ${summary.invalid}, conflicts ${summary.conflict_student_id}`);
  const imported = await call(ctx, ctx.instructor, 'POST', `/api/roster/${ctx.ids.class}/import`, { form: upload({ expected_sha256: preview.data.file.sha256 }), expect: [200] });
  const result = imported.data.result.summary;
  stepLog('roster', `imported (batch ${imported.data.result.batch_id}): enrolled ${result.enroll_now}, pending ${result.pending}, already ${result.already_enrolled}`);
}

async function checkPendingClaims(ctx) {
  const { members, entries } = await rosterState(ctx);
  for (const spec of LEARNERS.filter((item) => item.pendingAtImport)) {
    const id = ctx.learners.get(spec.key).id;
    const member = members.some((row) => row.learner_id === id && row.status === 'active');
    const entry = entries.find((row) => row.email_normalized === spec.email);
    stepLog(spec.key, `${member ? 'joined via roster' : 'NOT enrolled'} (roster entry ${entry?.status ?? 'none'})`);
    if (!member) ctx.notes.push(`${spec.key} did not auto-enroll after sign-up (roster entry ${entry?.status ?? 'none'}).`);
  }
}

const TOPIC_ORDER = ['draft', 'submitted', 'evaluated', 'finalized', 'approved', 'published'];

async function findTopicRevision(ctx, title) {
  const revisions = await rows(ctx.instructor.client.from('curriculum_topic_revisions').select('id,topic_id,title,status,revision_number,author_id').eq('title', title), 'topic revisions');
  if (!revisions.length) return null;
  const topics = await rows(ctx.instructor.client.from('curriculum_topics').select('id,module_id,archived_at').in('id', [...new Set(revisions.map((item) => item.topic_id))]), 'topics');
  const live = topics.filter((topic) => topic.module_id === ctx.ids.lo11 && !topic.archived_at).map((topic) => topic.id);
  return revisions.filter((item) => live.includes(item.topic_id)).sort((a, b) => b.revision_number - a.revision_number)[0] ?? null;
}

async function curriculumAction(ctx, actor, payload) {
  const reply = await call(ctx, actor, 'POST', '/api/curriculum', { json: payload, expect: [200] });
  return reply.data.record;
}

async function ensureTopic(ctx, key, targetStatus) {
  const spec = TOPICS[key];
  let revision = await findTopicRevision(ctx, spec.title);
  if (!revision) {
    const record = await curriculumAction(ctx, ctx.instructor, {
      action: 'create_topic', module_id: ctx.ids.lo11, title: spec.title, summary: spec.summary,
      body_markdown: spec.body, outcome_ids: spec.outcomes.map((code) => ctx.outcome(code)),
    });
    revision = record.revision;
    stepLog('topic', `${key}: drafted by the instructor`);
  }
  const steps = [];
  while (TOPIC_ORDER.indexOf(revision.status) < TOPIC_ORDER.indexOf(targetStatus)) {
    const id = revision.id;
    let record;
    switch (revision.status) {
      case 'draft': record = await curriculumAction(ctx, ctx.instructor, { action: 'submit', revision_id: id, note: 'Submitted for evaluation.' }); break;
      case 'submitted': record = await curriculumAction(ctx, ctx.admin, { action: 'evaluate', revision_id: id, result: 'passed', notes: 'Checked against the CSS NC II assembly procedures and LO1.1 performance criteria; accurate and ready for learners.' }); break;
      case 'evaluated': record = await curriculumAction(ctx, ctx.instructor, { action: 'finalize', revision_id: id, note: 'Content locked after a passed evaluation.' }); break;
      case 'finalized': record = await curriculumAction(ctx, ctx.admin, { action: 'approve', revision_id: id, note: 'Approved for publication.' }); break;
      case 'approved': record = await curriculumAction(ctx, ctx.admin, { action: 'publish', revision_id: id, note: 'Published to learners.' }); break;
      default: fail(`Topic ${key} is ${revision.status}; resolve it in /curriculum before re-running.`);
    }
    revision = record.revision;
    steps.push(revision.status);
  }
  stepLog('topic', `${key}: ${revision.status}${steps.length ? ` (moved through ${steps.join(' → ')})` : ' (unchanged)'}`);
  ctx.ids[`topic_${key}`] = revision.topic_id;
  ctx.ids[`topic_${key}_status`] = revision.status;
}

async function homeworkRecord(ctx) {
  const reply = await call(ctx, ctx.instructor, 'GET', `/api/activities/homework?class=${ctx.ids.class}`, { expect: [200] });
  return { homework: reply.data.homework.find((item) => item.title === HOMEWORK.title) ?? null, submissions: reply.data.submissions };
}

async function homeworkAction(ctx, actor, payload, expect = [200]) {
  return (await call(ctx, actor, 'POST', '/api/activities/homework', { json: payload, expect })).data;
}

async function ensureHomework(ctx) {
  let { homework } = await homeworkRecord(ctx);
  if (!homework) {
    const deadline = new Date(Date.now() + HOMEWORK.deadlineMinutes * 60_000).toISOString();
    const created = await homeworkAction(ctx, ctx.instructor, {
      action: 'create', class_id: ctx.ids.class, title: HOMEWORK.title, instructions: HOMEWORK.instructions, deadline_at: deadline,
      mission_code: 'coc1_m2', learning_objectives: HOMEWORK.objectives, criteria: HOMEWORK.criteria,
      max_score: HOMEWORK.criteria.reduce((sum, item) => sum + item.max_points, 0), submission_requirements: HOMEWORK.requirements,
    });
    homework = created.record;
    stepLog('homework', `created (deadline ${deadline})`);
  } else {
    stepLog('homework', `exists (${homework.status}, deadline ${homework.deadline_at})`);
  }
  if (homework.status === 'draft') {
    homework = (await homeworkAction(ctx, ctx.instructor, { action: 'publish', assignment_id: homework.id })).record;
    stepLog('homework', 'published');
  }
  ctx.ids.homework = homework.id;
  ctx.ids.homeworkDeadline = homework.deadline_at;
}

async function submitHomework(ctx, when) {
  for (const [key, plan] of Object.entries(HOMEWORK_TAKERS).filter(([, item]) => item.when === when)) {
    const session = await learner(ctx, key);
    const mine = await call(ctx, session, 'GET', `/api/activities/homework?id=${ctx.ids.homework}`, { expect: [200] });
    const existing = (mine.data.submissions ?? []).find((row) => row.learner_id === session.id);
    if (existing) { stepLog(key, `homework already submitted (${existing.evaluation_status})`); continue; }
    const reply = await homeworkAction(ctx, session, { action: 'submit', assignment_id: ctx.ids.homework, answer: checklist(plan.answer), file_ids: [] });
    const late = Number(reply.record?.lateness_seconds ?? 0) > 0;
    stepLog(key, `homework submitted ${late ? `late (${Math.round(reply.record.lateness_seconds)} s after the deadline)` : 'on time'}`);
  }
}

async function practiceState(session, mission) {
  const [completions, runs] = await Promise.all([
    rows(session.client.from('practice_mission_completions').select('mission_id').eq('learner_id', session.id).eq('mission_id', mission), 'completions'),
    rows(session.client.from('practice_mission_runs').select('outcome').eq('learner_id', session.id).eq('mission_id', mission), 'runs'),
  ]);
  return { completed: completions.length > 0, incomplete: runs.filter((run) => run.outcome === 'incomplete').length };
}

async function insertPracticeAction(ctx, session, mission, action, index) {
  const row = {
    learner_id: session.id,
    client_action_id: `demo-${session.spec.key}-${mission}-${index}`,
    mission_id: mission,
    phase_id: action.phaseId,
    action_type: action.actionType,
    target: action.target,
    value: action.value,
    client_occurred_at: new Date().toISOString(),
  };
  await session.token();
  const { error } = await session.client.from('practice_mission_actions').upsert(row, { onConflict: 'learner_id,client_action_id', ignoreDuplicates: true });
  if (error) fail(`${session.spec.key} ${mission} action ${index} was refused: ${error.message}`);
  if (ctx.options.paceMs) await sleep(ctx.options.paceMs);
}

async function verifyPractice(ctx, session, mission) {
  return call(ctx, session, 'POST', '/api/learner/practice', { json: { action: 'verify', mission }, expect: [200, 422] });
}

async function runMission(ctx, key, step) {
  const session = await learner(ctx, key);
  const state = await practiceState(session, step.mission);
  if (state.completed) { stepLog(key, `${step.mission} already verified`); return; }
  const plan = practicePlan(ctx.fixtures, step);
  const plannedFailures = plan.segments.filter((segment) => segment.verify === 'fail').length;
  if (step.stopAfterFailures && state.incomplete >= plannedFailures) { stepLog(key, `${step.mission} already has ${state.incomplete} failed verifications`); return; }
  let index = 0;
  const outcomes = [];
  for (const segment of plan.segments) {
    for (const action of segment.actions) await insertPracticeAction(ctx, session, step.mission, action, index++);
    if (segment.verify === 'none') { outcomes.push(`${segment.actions.length} actions, not verified`); continue; }
    const reply = await verifyPractice(ctx, session, step.mission);
    const run = reply.data?.run;
    const metrics = run ? ` run ${run.run_number}, ${run.invalid_count} invalid, ${run.correction_count} corrections` : '';
    if (segment.verify === 'pass' && reply.status !== 200) fail(`${key} ${step.mission} did not verify: ${JSON.stringify(reply.data)}`);
    outcomes.push(`${reply.status === 200 ? 'verified' : 'verify refused (incomplete)'}${metrics}`);
  }
  stepLog(key, `${step.mission}: ${outcomes.join('; ')}`);
}

async function completeTopic(ctx, key, topicKey) {
  const session = await learner(ctx, key);
  const topicId = ctx.ids[`topic_${topicKey}`];
  if (!topicId || ctx.ids[`topic_${topicKey}_status`] !== 'published') { stepLog(key, `lesson ${topicKey} is not published; skipped`); return; }
  const done = await rows(session.client.from('learner_topic_progress').select('topic_id').eq('learner_id', session.id).eq('topic_id', topicId), 'topic progress');
  if (done.length) { stepLog(key, `lesson ${topicKey} already completed`); return; }
  await call(ctx, session, 'POST', '/api/learner/curriculum', { json: { action: 'complete_topic', topic_id: topicId }, expect: [200] });
  stepLog(key, `lesson ${topicKey} completed`);
}

async function practiceQuiz(ctx, key, coc) {
  const session = await learner(ctx, key);
  const passed = await rows(session.client.from('practice_coc_progress').select('coc_code').eq('learner_id', session.id).eq('coc_code', coc), 'COC progress');
  if (passed.length) { stepLog(key, `${coc} practice quiz already passed`); return; }
  const begun = await call(ctx, session, 'POST', '/api/learner/practice', { json: { action: 'begin', coc }, expect: [200, 202] });
  const view = begun.data;
  // The synthetic learner knows the material: its answers come from the
  // server's stored key (read-only). Grading is done by the server.
  const stored = (await rows(ctx.service.from('practice_quiz_attempts').select('questions').eq('id', view.id), 'practice quiz key'))[0];
  const answers = Object.fromEntries(stored.questions.map((question) => [question.id, question.answer]));
  const submitted = await call(ctx, session, 'POST', '/api/learner/practice', { json: { action: 'submit', id: view.id, answers }, expect: [200] });
  stepLog(key, `${coc} practice quiz submitted: ${submitted.data.passed ? 'passed' : 'not passed'} (${submitted.data.score ?? '?'}/${submitted.data.questions?.length ?? 5})`);
}

async function runPractice(ctx) {
  for (const [key, steps] of Object.entries(PRACTICE)) {
    for (const step of steps) {
      if (step.topic) await completeTopic(ctx, key, step.topic);
      else if (step.mission) await runMission(ctx, key, step);
      else if (step.cocQuiz) await practiceQuiz(ctx, key, step.cocQuiz);
    }
  }
}

/**
 * Runs the (idempotent) simulation assessment publisher for the same target
 * when the COC1 M2 package is missing. Its temporary governance principal
 * gets a one-time password that is never printed.
 */
export function publishSimulationAssessments(ctx) {
  const args = [path.join(ROOT, 'scripts', 'publish-simulation-assessments.mjs'), ...(ctx.target.kind === 'hosted' ? ['--target', 'hosted', '--confirm'] : [])];
  stepLog('assess', `no published simulation assessment yet: running node scripts/publish-simulation-assessments.mjs${ctx.target.kind === 'hosted' ? ' --target hosted --confirm' : ''}`);
  const result = spawnSync(process.execPath, args, {
    cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env,
      NEXT_PUBLIC_SUPABASE_URL: ctx.target.url,
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: ctx.target.anon,
      NEXT_PUBLIC_SUPABASE_ANON_KEY: ctx.target.anon,
      SUPABASE_SERVICE_ROLE_KEY: ctx.target.serviceKey,
      BYTEQUEST_E2E_PASSWORD: newPassword(),
    },
  });
  if (result.status !== 0) fail(`Publishing the simulation assessments failed: ${(result.stderr || result.stdout || '').trim().slice(0, 500)}`);
  const published = JSON.parse(result.stdout.slice(result.stdout.indexOf('{')));
  stepLog('assess', `${published.status}: ${published.missions?.length ?? 0} simulation assessments, ${published.criteria ?? 0} criteria`);
  return published;
}

async function ensureAssessmentAssignment(ctx) {
  const contract = ctx.contracts.get('coc1_m2');
  const mission = (await rows(ctx.instructor.client.from('missions').select('id').eq('mission_code', 'coc1_m2'), 'mission'))[0];
  const findActivity = async () => (await rows(ctx.instructor.client.from('activity_versions').select('id,status,learner_payload').eq('mission_id', mission.id).eq('status', 'published'), 'activity versions'))
    .find((item) => item.learner_payload?.mode === 'assessment' && !item.learner_payload?.simulation_template && item.learner_payload?.definition_version === contract.version);
  let activity = await findActivity();
  if (!activity) {
    publishSimulationAssessments(ctx);
    activity = await findActivity();
  }
  if (!activity) fail('No published COC1 M2 simulation assessment for the current contract after publishing.');
  // Exactly as the dashboard's "Assign published content" form
  // (src/app/classes/[id]/page.tsx and AssignActivityForm): the approved
  // rubrics the instructor reads under their own RLS, matched to the activity
  // version, then the instructor's own assign_activity.
  const rubrics = await rows(ctx.instructor.client.from('rubric_versions').select('id,title,activity_version_id').eq('status', 'approved').order('title'), 'approved rubrics');
  const rubric = rubrics.find((item) => item.activity_version_id === activity.id);
  if (!rubric) {
    fail('The instructor cannot read an approved rubric for the COC1 M2 simulation assessment, so the dashboard would report "This activity has no approved matching rubric". Apply supabase/migrations/20261119180000_instructor_assignable_rubric_visibility.sql to this database first.');
  }
  let assignment = (await rows(ctx.instructor.client.from('assignments').select('id,attempts_allowed,retry_after_seconds').eq('class_id', ctx.ids.class).eq('activity_version_id', activity.id).eq('assignment_type', 'assessment').eq('status', 'active'), 'assignments'))[0];
  if (!assignment) {
    // The same arguments as the form: no availability window or due date.
    assignment = await rpc(ctx.instructor.client, 'assign_activity', {
      p_class_id: ctx.ids.class, p_activity_version_id: activity.id, p_rubric_version_id: rubric.id, p_assignment_type: 'assessment',
      p_title: ASSESSMENT.title, p_instructions: ASSESSMENT.instructions,
    });
    stepLog('assess', `assigned ${ASSESSMENT.title} with rubric "${rubric.title}" (${assignment.id})`);
  } else {
    stepLog('assess', `${ASSESSMENT.title} already assigned (${assignment.id}); the instructor reads its approved rubric "${rubric.title}"`);
  }
  if (assignment.attempts_allowed !== 2) {
    await rpc(ctx.instructor.client, 'configure_assignment_access', {
      p_assignment_id: assignment.id, p_attempts_allowed: 2, p_retry_enabled: true, p_retry_after_seconds: 3600,
      p_prerequisite_assignment_id: null, p_reason: 'Two attempts with a one-hour wait between them for the re-defense demonstration.',
    });
    stepLog('assess', 'access: 2 attempts, retry after 1 hour');
  }
  ctx.ids.assessment = assignment.id;
  ctx.ids.assessmentActivity = activity.id;
}

async function takeAssessment(ctx, key, plan) {
  const session = await learner(ctx, key);
  const existing = await rows(session.client.from('attempts').select('id,status').eq('assignment_id', ctx.ids.assessment).eq('learner_id', session.id), 'own attempts');
  if (existing.length && existing[0].status !== 'in_progress') return existing[0];
  const startKey = stableUuid('demo-assessment-start', key, ctx.ids.assessment);
  // The same start key resumes an interrupted attempt (as the app does).
  const attempt = await rpc(session.client, 'start_attempt', { p_assignment_id: ctx.ids.assessment, p_client_start_key: startKey });
  const recorded = (await rows(session.client.from('attempt_actions').select('sequence_number').eq('attempt_id', attempt.id), 'own attempt actions')).length;
  const started = Date.now();
  let sequence = 0;
  const append = async (actionType, target, value) => {
    sequence += 1;
    if (sequence <= recorded) return;
    await session.token();
    await rpc(session.client, 'append_attempt_action', {
      p_attempt_id: attempt.id, p_sequence_number: sequence, p_action_type: actionType, p_target: target,
      p_value: value, p_client_occurred_at: new Date().toISOString(),
    });
    if (ctx.options.paceMs) await sleep(ctx.options.paceMs);
  };
  // The app records the start, then every simulation action of the bench.
  await append('attempt_started', ctx.ids.assessmentActivity, { assignment_type: 'assessment', client_start_key: startKey });
  const actions = assessmentPlan(ctx.fixtures, plan.run);
  for (const [index, action] of actions.entries()) {
    await append(action.actionType, action.target, { ...action.value, client_action_id: `demo-${key}-assessment-${index}`, mission_id: 'coc1_m2', phase_id: action.phaseId });
  }
  const submitted = await rpc(session.client, 'submit_attempt', {
    p_attempt_id: attempt.id, p_submission_key: stableUuid('demo-assessment-submit', key, ctx.ids.assessment),
    p_elapsed_time_seconds: Math.max(1, Math.round((Date.now() - started) / 1000)),
  });
  stepLog(key, `assessment submitted (${plan.run}, ${actions.length} actions) → ${submitted.status}`);
  return submitted;
}

const STAGE_RANK = { evaluate: 0, finalize: 1, release: 2, released: 3 };
const TECHNICAL_STAGE = { evaluated: 'evaluate', under_review: 'finalize', finalized: 'release', released: 'released' };

async function evaluationAction(ctx, payload) {
  const reply = await call(ctx, ctx.instructor, 'POST', '/api/evaluations', { json: payload, expect: [200] });
  const failed = reply.data?.results?.filter((item) => !item.ok) ?? [];
  if (failed.length) fail(`Evaluation Center ${payload.kind} ${payload.action} failed: ${JSON.stringify(failed)}`);
  return reply.data;
}

async function runAssessments(ctx) {
  await ensureAssessmentAssignment(ctx);
  for (const [key, plan] of Object.entries(ASSESSMENT.takers)) {
    const taken = await takeAssessment(ctx, key, plan);
    let attempt = (await rows(ctx.instructor.client.from('attempts').select('id,status').eq('id', taken.id), 'attempt'))[0];
    const moves = [];
    while (STAGE_RANK[TECHNICAL_STAGE[attempt.status]] < STAGE_RANK[plan.stage]) {
      if (attempt.status === 'evaluated') await evaluationAction(ctx, { kind: 'technical', action: 'record_evaluation', attempt_id: attempt.id, note: plan.note ?? 'Automated step results reviewed against the evidence; confirmed.' });
      else if (attempt.status === 'under_review') await evaluationAction(ctx, { kind: 'technical', action: 'finalize', attempt_ids: [attempt.id], remarks: 'Result confirmed after instructor review.' });
      else if (attempt.status === 'finalized') await evaluationAction(ctx, { kind: 'technical', action: 'release', attempt_ids: [attempt.id], note: 'Released to the learner.' });
      else fail(`${key} assessment attempt is ${attempt.status}.`);
      attempt = (await rows(ctx.instructor.client.from('attempts').select('id,status').eq('id', attempt.id), 'attempt'))[0];
      moves.push(attempt.status);
    }
    const outcome = (await rows(ctx.instructor.client.from('score_revisions').select('outcome,percentage,revision_number').eq('attempt_id', attempt.id).order('revision_number', { ascending: false }).limit(1), 'score'))[0];
    stepLog(key, `assessment ${attempt.status} · ${outcome?.outcome ?? '-'} ${outcome?.percentage ?? '-'}%${moves.length ? ` (instructor: ${moves.join(' → ')})` : ''}`);
  }
}

async function ensureQuiz(ctx) {
  const client = ctx.instructor.client;
  let quiz = (await rows(client.from('quizzes').select('id,title').eq('title', QUIZ.title).eq('instructor_id', ctx.instructor.id), 'quizzes'))[0];
  if (!quiz) {
    quiz = await rpc(client, 'create_instructor_quiz', {
      p_title: QUIZ.title, p_topic: 'LO1.1 Assemble computer hardware', p_description: QUIZ.description, p_coc_module_id: ctx.ids.coc1,
      p_instructions: QUIZ.instructions, p_focus: QUIZ.focus, p_quiz_type: QUIZ.quizType, p_difficulty: QUIZ.difficulty, p_topic_id: null,
      p_module_ids: [ctx.ids.lo11], p_outcome_ids: QUIZ.outcomes.map((code) => ctx.outcome(code)),
      p_time_limit_minutes: QUIZ.timeLimitMinutes, p_result_release_mode: 'instructor_release',
    });
    stepLog('quiz', `created ${QUIZ.title}`);
  }
  ctx.ids.quiz = quiz.id;
  const version = (await rows(client.from('quiz_versions').select('id,status,version_number').eq('quiz_id', quiz.id).order('version_number', { ascending: false }), 'quiz versions'))[0];
  if (!version) fail('The demo quiz has no version.');
  ctx.ids.quizVersion = version.id;
  if (version.status === 'draft') {
    const items = await rows(client.from('quiz_items').select('*').eq('quiz_version_id', version.id), 'quiz items');
    for (const item of QUIZ.items) {
      let row = items.find((existing) => existing.prompt === item.prompt && !existing.removed_at);
      if (!row) {
        const essay = item.type === 'scenario_essay';
        row = await rpc(client, 'upsert_quiz_item', {
          p_quiz_version_id: version.id, p_item_type: item.type, p_prompt: item.prompt,
          p_options: item.options ?? [], p_correct_answer: essay ? item.guide : item.answer, p_explanation: item.explanation ?? null,
          p_item_id: null, p_points: essay ? null : 1, p_rubric: essay ? item.rubric : null, p_scenario: essay ? item.scenario : null,
          p_min_words: essay ? item.minWords : null, p_max_words: essay ? item.maxWords : null,
        });
        stepLog('quiz', `question ${item.key} drafted`);
      }
      if (row.review_status !== 'approved') {
        await rpc(client, 'review_quiz_item', { p_item_id: row.id, p_decision: 'approved', p_notes: 'Checked against the LO1.1 performance criteria.' });
      }
    }
    const published = await rpc(client, 'publish_and_assign_quiz', {
      p_quiz_version_id: version.id, p_class_ids: [ctx.ids.class], p_instructions: QUIZ.instructions,
      p_due_at: new Date(Date.now() + 7 * 86_400_000).toISOString(),
    });
    stepLog('quiz', `version ${version.version_number} published and assigned (${published.assignments.length} class)`);
  } else {
    const assigned = await rows(client.from('quiz_assignments').select('id').eq('quiz_version_id', version.id).eq('class_id', ctx.ids.class), 'quiz assignments');
    if (!assigned.length) fail('The demo quiz version is published but not assigned to the demo class.');
    stepLog('quiz', `version ${version.version_number} already ${version.status} and assigned`);
  }
  const items = await rows(client.from('quiz_items').select('id,prompt,item_type').eq('quiz_version_id', version.id), 'quiz items');
  ctx.quizItems = new Map(QUIZ.items.map((item) => [item.key, items.find((row) => row.prompt === item.prompt)?.id ?? fail(`Quiz item ${item.key} is missing.`)]));
}

function quizAnswer(item, choice) {
  if (choice === 'correct') return item.answer;
  if (item.type === 'true_false') return choice;
  return item.options[choice];
}

async function takeQuiz(ctx, key, plan) {
  const session = await learner(ctx, key);
  const available = await rpc(session.client, 'get_available_learner_quizzes', {});
  const row = (Array.isArray(available) ? available : []).find((item) => item.quiz_id === ctx.ids.quiz);
  if (!row) fail(`${key} cannot see the demo quiz.`);
  if (row.attempt_id && row.attempt_status !== 'in_progress') return `already ${row.status}${row.submission_kind && row.submission_kind !== 'learner' ? ` (${row.submission_kind})` : ''}`;
  if (row.attempt_id && plan.abandon) return 'in progress (left unsubmitted; the server submits it when the time limit ends)';
  const started = await rpc(session.client, 'start_learner_quiz', { p_assignment_id: row.assignment_id, p_client_start_key: stableUuid('demo-quiz-start', key, row.assignment_id) });
  for (const item of QUIZ.items) {
    const choice = item.type === 'scenario_essay' ? (plan.essay ? ESSAYS[plan.essay] : undefined) : plan.answers[item.key];
    if (choice === undefined) continue;
    const answer = item.type === 'scenario_essay' ? choice : quizAnswer(item, choice);
    await rpc(session.client, 'save_learner_quiz_answer', { p_attempt_id: started.attempt_id, p_item_id: ctx.quizItems.get(item.key), p_answer: answer });
    if (ctx.options.paceMs) await sleep(ctx.options.paceMs);
  }
  if (plan.abandon) return 'started, three answers saved, left unsubmitted (auto-submits at the 15-minute limit)';
  await rpc(session.client, 'submit_learner_quiz', { p_attempt_id: started.attempt_id, p_submission_key: stableUuid('demo-quiz-submit', key, row.assignment_id) });
  return 'submitted';
}

const QUIZ_STAGE = { pending: 'evaluate', evaluated: 'finalize', finalized: 'release', released: 'released' };

async function runQuiz(ctx) {
  await ensureQuiz(ctx);
  for (const [key, plan] of Object.entries(QUIZ_TAKERS)) {
    const outcome = await takeQuiz(ctx, key, plan);
    const session = await learner(ctx, key);
    let attempt = (await rows(ctx.instructor.client.from('quiz_attempts').select('id,status,evaluation_status,submission_kind').eq('learner_id', session.id).eq('class_id', ctx.ids.class), 'quiz attempt'))[0];
    const moves = [];
    if (attempt && !plan.abandon && plan.stage) {
      while (QUIZ_STAGE[attempt.evaluation_status] !== undefined && STAGE_RANK[QUIZ_STAGE[attempt.evaluation_status]] < STAGE_RANK[plan.stage]) {
        if (attempt.evaluation_status === 'pending') {
          await call(ctx, ctx.instructor, 'POST', '/api/quizzes/evaluation', { json: { action: 'score_essay', attempt_id: attempt.id, item_id: ctx.quizItems.get('essay'), criterion_scores: plan.scores, feedback: plan.feedback }, expect: [200] });
        } else if (attempt.evaluation_status === 'evaluated') await evaluationAction(ctx, { kind: 'quiz', action: 'finalize', attempt_ids: [attempt.id] });
        else if (attempt.evaluation_status === 'finalized') await evaluationAction(ctx, { kind: 'quiz', action: 'release', attempt_ids: [attempt.id] });
        attempt = (await rows(ctx.instructor.client.from('quiz_attempts').select('id,status,evaluation_status,submission_kind').eq('id', attempt.id), 'quiz attempt'))[0];
        moves.push(attempt.evaluation_status);
      }
    }
    stepLog(key, `quiz ${outcome} · evaluation ${attempt?.evaluation_status ?? '-'}${moves.length ? ` (instructor: ${moves.join(' → ')})` : ''}`);
  }
}

const HOMEWORK_STAGE = { submitted: 'evaluate', graded: 'finalize', finalized: 'release', released: 'released' };

async function gradeHomework(ctx) {
  const { submissions } = await homeworkRecord(ctx);
  for (const [key, plan] of Object.entries(HOMEWORK_TAKERS)) {
    const session = await learner(ctx, key);
    let submission = submissions.find((row) => row.learner_id === session.id && row.assignment_id === ctx.ids.homework);
    if (!submission) { stepLog(key, 'homework not submitted'); continue; }
    const moves = [];
    while (STAGE_RANK[HOMEWORK_STAGE[submission.status]] < STAGE_RANK[plan.stage]) {
      if (submission.status === 'submitted') {
        const total = Object.values(plan.scores).reduce((sum, value) => sum + value, 0);
        await evaluationAction(ctx, { kind: 'homework', action: 'grade', submission_id: submission.id, assignment_id: ctx.ids.homework, score: total, feedback: plan.feedback, criterion_scores: plan.scores });
      } else if (submission.status === 'graded') await evaluationAction(ctx, { kind: 'homework', action: 'finalize', submission_ids: [submission.id] });
      else if (submission.status === 'finalized') await evaluationAction(ctx, { kind: 'homework', action: 'release', submission_ids: [submission.id] });
      submission = (await homeworkRecord(ctx)).submissions.find((row) => row.id === submission.id);
      moves.push(submission.status);
    }
    stepLog(key, `homework ${submission.status}${submission.score != null ? ` ${submission.score}/20` : ''}${Number(submission.lateness_seconds) > 0 ? ' (late)' : ''}${moves.length ? ` (instructor: ${moves.join(' → ')})` : ''}`);
  }
  const missing = LEARNERS.filter((spec) => !HOMEWORK_TAKERS[spec.key]).map((spec) => spec.key);
  stepLog('homework', `missing work: ${missing.join(', ')}`);
}

async function waitForHomeworkDeadline(ctx) {
  const deadline = Date.parse(ctx.ids.homeworkDeadline ?? '');
  if (!Number.isFinite(deadline)) return;
  const wait = deadline - Date.now() + 2_000;
  if (wait > 0) {
    stepLog('homework', `waiting ${Math.ceil(wait / 1000)} s for the deadline before the late submissions`);
    await sleep(wait);
  }
}

async function optIntoLeaderboard(ctx) {
  for (const key of LEADERBOARD_OPT_IN) {
    const session = await learner(ctx, key);
    await session.token();
    const current = (await rows(session.client.from('profiles').select('show_on_leaderboard').eq('user_id', session.id), 'profile'))[0];
    if (current?.show_on_leaderboard) { stepLog(key, 'already on the class leaderboard'); continue; }
    const { error } = await session.client.from('profiles').update({ show_on_leaderboard: true }).eq('user_id', session.id);
    if (error) fail(`${key} could not opt into the leaderboard: ${error.message}`);
    stepLog(key, 'opted into the class leaderboard');
  }
}

// ---------------------------------------------------------------------------
// Summary (read-only)
// ---------------------------------------------------------------------------
function countBy(list, key) {
  return list.reduce((acc, item) => { const value = typeof key === 'function' ? key(item) : item[key]; acc[value] = (acc[value] ?? 0) + 1; return acc; }, {});
}

async function summarize(ctx) {
  const s = ctx.service;
  const classRow = await demoClass(ctx);
  if (!classRow) fail('The demo class does not exist yet.');
  const classId = classRow.id;
  const profiles = await rows(s.from('profiles').select('user_id,email,full_name,status,learner_id,learner_id_managed,show_on_leaderboard').in('email', LEARNERS.map((spec) => spec.email)), 'profiles');
  const ids = profiles.map((row) => row.user_id);
  const keyOf = new Map(profiles.map((row) => [row.user_id, LEARNERS.find((spec) => spec.email === row.email.toLowerCase())?.key]));
  const inIds = (table, columns, column = 'learner_id') => rows(s.from(table).select(columns).in(column, ids), table);
  const [memberships, rosterEntries, rosterBatches, practiceActions, practiceRuns, completions, topicProgress, cocProgress, practiceQuizzes,
    unlocks, moduleCompletions, assignments, attempts, quizAttempts, homework, points, achievements] = await Promise.all([
    rows(s.from('class_memberships').select('learner_id,status').eq('class_id', classId), 'memberships'),
    rows(s.from('class_roster_entries').select('status').eq('class_id', classId), 'roster entries'),
    rows(s.from('roster_import_batches').select('id').eq('class_id', classId), 'roster batches'),
    inIds('practice_mission_actions', 'id,mission_id'),
    inIds('practice_mission_runs', 'outcome,mission_id,invalid_count,correction_count,duration_seconds'),
    inIds('practice_mission_completions', 'mission_id'),
    inIds('learner_topic_progress', 'topic_id'),
    inIds('practice_coc_progress', 'learner_id'),
    inIds('practice_quiz_attempts', 'status,passed'),
    inIds('learner_module_unlocks', 'module_id,reason'),
    inIds('learner_module_completions', 'module_id'),
    rows(s.from('assignments').select('id,title,assignment_type').eq('class_id', classId), 'assignments'),
    rows(s.from('attempts').select('id,status,learner_id').eq('class_id', classId), 'attempts'),
    rows(s.from('quiz_attempts').select('id,status,evaluation_status,submission_kind,learner_id').eq('class_id', classId), 'quiz attempts'),
    rows(s.from('homework_assignments').select('id,title,status,deadline_at').eq('class_id', classId), 'homework'),
    inIds('learner_point_events', 'event_type,points'),
    rows(s.from('user_achievements').select('user_id').in('user_id', ids), 'achievements'),
  ]);
  const attemptIds = attempts.map((row) => row.id);
  const quizAttemptIds = quizAttempts.map((row) => row.id);
  const homeworkIds = homework.map((row) => row.id);
  const [attemptActions, criterionResults, evaluationRecords, releases, quizAnswers, essayScores, finalizations, submissions, topics] = await Promise.all([
    attemptIds.length ? rows(s.from('attempt_actions').select('id').in('attempt_id', attemptIds), 'attempt actions') : [],
    attemptIds.length ? rows(s.from('criterion_results').select('observation').in('attempt_id', attemptIds), 'criterion results') : [],
    attemptIds.length ? rows(s.from('attempt_evaluation_records').select('attempt_id').in('attempt_id', attemptIds), 'evaluation records') : [],
    attemptIds.length ? rows(s.from('result_releases').select('attempt_id').in('attempt_id', attemptIds), 'releases') : [],
    quizAttemptIds.length ? rows(s.from('quiz_answers').select('id').in('quiz_attempt_id', quizAttemptIds), 'quiz answers') : [],
    quizAttemptIds.length ? rows(s.from('quiz_essay_scores').select('id').in('attempt_id', quizAttemptIds), 'essay scores') : [],
    quizAttemptIds.length ? rows(s.from('quiz_result_finalizations').select('attempt_id,released_at').in('attempt_id', quizAttemptIds), 'finalizations') : [],
    homeworkIds.length ? rows(s.from('homework_submissions').select('learner_id,status,score,lateness_seconds').in('assignment_id', homeworkIds), 'submissions') : [],
    rows(s.from('curriculum_topic_revisions').select('title,status,revision_number').in('title', Object.values(TOPICS).map((topic) => topic.title)), 'topics'),
  ]);
  const counts = {
    learner_accounts: { total: profiles.length, active: profiles.filter((row) => row.status === 'active').length, student_ids_managed: profiles.filter((row) => row.learner_id_managed).length, leaderboard_opt_in: profiles.filter((row) => row.show_on_leaderboard).length },
    class: { title: classRow.title, code: classRow.class_code, status: classRow.status },
    class_memberships: countBy(memberships, 'status'),
    roster_entries: countBy(rosterEntries, 'status'),
    roster_import_batches: rosterBatches.length,
    curriculum_topics: Object.fromEntries(topics.map((row) => [row.title, `${row.status} (revision ${row.revision_number})`])),
    learner_topic_progress: topicProgress.length,
    practice_mission_actions: practiceActions.length,
    practice_mission_runs: countBy(practiceRuns, 'outcome'),
    practice_mission_runs_with_mistakes: practiceRuns.filter((run) => run.invalid_count > 0 || run.correction_count > 0).length,
    practice_mission_completions: countBy(completions, 'mission_id'),
    practice_quiz_attempts: countBy(practiceQuizzes, (row) => `${row.status}${row.passed ? ' (passed)' : ''}`),
    practice_coc_progress: cocProgress.length,
    learner_module_unlocks: countBy(unlocks, 'reason'),
    learner_module_completions: moduleCompletions.length,
    assessment_assignments: assignments.length,
    assessment_attempts: countBy(attempts, 'status'),
    attempt_actions: attemptActions.length,
    criterion_results: countBy(criterionResults, 'observation'),
    attempt_evaluation_records: evaluationRecords.length,
    result_releases: releases.length,
    quiz_attempts: countBy(quizAttempts, (row) => `${row.evaluation_status}${row.submission_kind && row.submission_kind !== 'learner' ? ` (${row.submission_kind})` : ''}${row.status === 'in_progress' ? ' (in progress)' : ''}`),
    quiz_answers: quizAnswers.length,
    quiz_essay_scores: essayScores.length,
    quiz_result_finalizations: { finalized: finalizations.length, released: finalizations.filter((row) => row.released_at).length },
    homework_assignments: homework.length,
    homework_submissions: countBy(submissions, (row) => `${row.status}${Number(row.lateness_seconds) > 0 ? ' (late)' : ' (on time)'}`),
    homework_missing: ids.length - submissions.length,
    learner_point_events: { count: points.length, points: points.reduce((sum, row) => sum + row.points, 0), by_type: countBy(points, 'event_type') },
    user_achievements: achievements.length,
  };

  // Evaluation Center, exactly as the dashboard queue reports it.
  const stage = async (kind) => {
    const reply = await call(ctx, ctx.instructor, 'GET', `/api/evaluations?stage=evaluate&class_id=${classId}${kind ? `&kind=${kind}` : ''}`, { expect: [200] });
    return reply.data.counts;
  };
  const evaluationCenter = { all: await stage(null), technical: await stage('technical'), quiz: await stage('quiz'), homework: await stage('homework') };

  const analyticsOverview = await rpc(ctx.instructor.client, 'get_analytics_overview', { p_filters: { class_id: classId } });
  const performance = await rpc(ctx.instructor.client, 'get_learner_performance', { p_filters: { class_id: classId } });
  const statuses = Object.fromEntries((performance.learners ?? [])
    .map((row) => [keyOf.get(row.id) ?? row.name ?? row.id, { name: row.name, status: row.status, reasons: row.reasons, progress_percent: row.progress_percent, completed_items: row.completed_items, total_items: row.total_items, quiz_avg: row.quiz_avg, missions_verified: row.missions_verified, practice_runs: row.practice_runs }])
    .sort(([a], [b]) => String(a).localeCompare(String(b))));

  const rewards = {};
  let leaderboard = null;
  for (const spec of LEARNERS) {
    const session = ctx.learners.get(spec.key);
    if (!session) continue;
    await session.token();
    const data = await rpc(session.client, 'get_learner_rewards', {});
    rewards[spec.key] = { points: data.points, level: `${data.level?.level} ${data.level?.title}`, achievements: (data.achievements ?? []).filter((item) => item.earned_at).map((item) => item.code) };
    if (spec.key === LEADERBOARD_OPT_IN[0]) leaderboard = data.leaderboard;
  }
  const summary = { generated_at: new Date().toISOString(), target: ctx.target.kind, class_id: classId, counts, evaluation_center: evaluationCenter, learner_statuses: statuses, rewards, leaderboard, analytics_overview: analyticsOverview, notes: ctx.notes };
  fs.mkdirSync(path.dirname(SUMMARY_FILE), { recursive: true });
  fs.writeFileSync(SUMMARY_FILE, `${JSON.stringify(summary, null, 2)}\n`);
  say('\nRecord counts (demo class and its twelve learners):');
  for (const [name, value] of Object.entries(counts)) say(`  ${name.padEnd(36)} ${typeof value === 'object' ? JSON.stringify(value) : value}`);
  say('\nEvaluation Center (demo class):');
  for (const [kind, value] of Object.entries(evaluationCenter)) say(`  ${kind.padEnd(10)} evaluate ${value.evaluate} · finalize ${value.finalize} · release ${value.release} · released ${value.released}`);
  say('\nLearner statuses (analytics):');
  for (const [key, value] of Object.entries(statuses)) {
    const reasons = (value.reasons ?? []).map((reason) => (typeof reason === 'string' ? reason : reason?.message ?? reason?.code ?? JSON.stringify(reason)));
    say(`  ${key} ${value.name ? `(${value.name}) ` : ''}${value.status} · progress ${value.progress_percent ?? '-'}% (${value.completed_items ?? 0}/${value.total_items ?? 0}) · quiz avg ${value.quiz_avg ?? '-'}${reasons.length ? ` · ${reasons.join('; ')}` : ''}`);
  }
  say('\nRewards:');
  for (const [key, value] of Object.entries(rewards)) say(`  ${key} ${String(value.points).padStart(4)} points · level ${value.level} · ${value.achievements.length ? value.achievements.join(', ') : 'no achievements yet'}`);
  if (leaderboard) say(`  leaderboard (as ${LEADERBOARD_OPT_IN[0]} sees it): ${leaderboard.map((row) => `#${row.rank} ${row.display_name} ${row.points}`).join(' · ')}`);
  say(`\nAnalytics overview JSON (instructor, class filter) and everything above: ${path.relative(ROOT, SUMMARY_FILE)}`);
  if (ctx.notes.length) say(`\nNotes:\n${ctx.notes.map((note) => `  - ${note}`).join('\n')}`);
  return summary;
}

// ---------------------------------------------------------------------------
// Removal (no history is deleted)
// ---------------------------------------------------------------------------
async function removeDemo(ctx) {
  const classRow = await demoClass(ctx);
  const reason = 'Re-defense demo data removed (synthetic learners).';
  const profiles = await rows(ctx.service.from('profiles').select('user_id,email,status,role').in('email', LEARNERS.map((spec) => spec.email)), 'profiles');
  if (classRow && classRow.instructor_id !== ctx.instructor.id) fail(`Class ${CLASS_CODE} belongs to another instructor.`);
  for (const profile of profiles.filter((row) => row.role === 'learner' && row.status === 'active')) {
    if (classRow?.status === 'active') {
      await rpc(ctx.instructor.client, 'instructor_deactivate_learner_account', { p_learner_id: profile.user_id, p_reason: reason });
    } else {
      await rpc(ctx.admin.client, 'admin_set_account_status', { p_user_id: profile.user_id, p_status: 'deactivated', p_reason: reason });
    }
    stepLog('remove', `deactivated ${profile.email}`);
  }
  const quiz = (await rows(ctx.instructor.client.from('quizzes').select('id,archived_at').eq('title', QUIZ.title).eq('instructor_id', ctx.instructor.id), 'quiz'))[0];
  if (quiz && !quiz.archived_at) { await rpc(ctx.instructor.client, 'archive_instructor_quiz', { p_quiz_id: quiz.id, p_reason: reason }); stepLog('remove', 'archived the demo quiz'); }
  if (classRow?.status === 'active') { await rpc(ctx.instructor.client, 'archive_class', { p_class_id: classRow.id, p_reason: reason }); stepLog('remove', `archived ${classRow.title}`); }
  if (ctx.options.archiveTopics) {
    for (const key of Object.keys(TOPICS)) {
      const revision = await findTopicRevision(ctx, TOPICS[key].title);
      if (!revision) continue;
      await curriculumAction(ctx, ctx.admin, { action: 'archive_topic', topic_id: revision.topic_id, note: reason });
      stepLog('remove', `archived lesson ${key}`);
    }
  }
  // Lessons are curriculum content every learner sees: archiving one changes
  // the required items of every learner's LO1.1, so it is opt-in.
  say(`Demo removed: class archived, learners deactivated${ctx.options.archiveTopics ? ', demo lessons archived' : '; the demo lessons stay (add --archive-topics to archive them)'}. Every attempt, result, evidence and audit record is kept.`);
}

// ---------------------------------------------------------------------------
export async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help) { say(HELP); return; }
  const ctx = await buildContext(options);
  if (options.remove) return removeDemo(ctx);
  if (!options.summaryOnly) {
    ctx.fixtures = loadFixtures(ctx);
    say('\n[1/9] Learner accounts with an account before the roster import');
    await ensureAccounts(ctx, LEARNERS.filter((spec) => !spec.pendingAtImport));
    say('[2/9] Demo class and Excel roster import');
    await ensureClass(ctx);
    // Pending learners are looked up first so a re-run sees their membership.
    const known = await rows(ctx.service.from('profiles').select('email').in('email', LEARNERS.filter((spec) => spec.pendingAtImport).map((spec) => spec.email)), 'pending learner profiles');
    if (known.length) await ensureAccounts(ctx, LEARNERS.filter((spec) => spec.pendingAtImport && known.some((row) => row.email.toLowerCase() === spec.email)));
    await ensureRoster(ctx);
    say('[3/9] Pending roster learners sign up (automatic enrollment)');
    await ensureAccounts(ctx, LEARNERS.filter((spec) => spec.pendingAtImport && !ctx.learners.has(spec.key)));
    await checkPendingClaims(ctx);
    say('[4/9] LO1.1 lessons through the publication workflow');
    await ensureTopic(ctx, 'esd', ctx.target.publishTopics ? 'published' : 'approved');
    await ensureTopic(ctx, 'handling', 'approved');
    say('[5/9] Homework published; on-time submissions');
    await ensureHomework(ctx);
    await submitHomework(ctx, 'on_time');
    say('[6/9] Practice: lessons, missions (with mistakes) and the COC1 practice quiz');
    await runPractice(ctx);
    say('[7/9] COC1 M2 simulation assessment and Evaluation Center stages');
    await runAssessments(ctx);
    say('[8/9] Curriculum quiz with a scenario essay');
    await runQuiz(ctx);
    say('[9/9] Late homework, grading stages and leaderboard opt-in');
    await waitForHomeworkDeadline(ctx);
    await submitHomework(ctx, 'late');
    await gradeHomework(ctx);
    await optIntoLeaderboard(ctx);
  } else {
    const store = readAccountStore();
    for (const spec of LEARNERS) {
      const saved = store.learners[spec.key];
      if (saved?.password && saved.user_id) ctx.learners.set(spec.key, learnerSession(ctx, { ...spec, id: saved.user_id, password: saved.password }, ctx.createClient));
    }
  }
  return summarize(ctx);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(`\nDemo seeding stopped: ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  });
}
