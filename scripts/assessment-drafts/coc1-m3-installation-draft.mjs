// Review artifact only. Deliberately not imported by either publishing script.
// Expected values are server-side proposals, never Flutter assets or payloads.
import { fields, option, sequence, single, buildLearnerPayload } from '../mission-assessment-packages.mjs';

const source = 'PROPOSED — instructor review required. ByteQuest Interactive 2D Mobile App Todo List, Phase 3 COC1 M3. This PDF is a project requirement, not approval of a TESDA assessment rubric.';
const prefix = 'COC1-M3-INSTALL-DRAFT';
const proposed = {
  packageId: 'coc1-m3-installation-pdf-review-v1',
  missionCode: 'coc1_m3',
  localMissionCode: 'COC1-M3',
  cocCode: 'coc1',
  unitCode: 'ELC724331',
  unitTitle: 'Install and Configure Computer Systems',
  title: 'Install and Configure a Workstation OS — review draft',
  description: 'Configure a blank GPT workstation for UEFI installation, install the OS and Ethernet driver, restart, test boot and device readiness, interpret the measurements, and review the evidence before submitting.',
  criteria: [
    fields({
      code: `${prefix}-01-SETUP`, title: 'Prepare firmware, storage and destination',
      instruction: 'Apply the boot, storage and installation-destination settings for the specified workstation.',
      actionType: 'coc1_m3_install_setup_applied', source,
      fields: [
        { id: 'boot_mode', label: 'Boot mode', options: [option('legacy', 'Legacy BIOS'), option('uefi', 'UEFI')], expected: 'uefi' },
        { id: 'storage_mode', label: 'Storage controller', options: [option('ahci', 'AHCI'), option('disabled', 'Disabled')], expected: 'ahci' },
        { id: 'install_target', label: 'Destination', options: [option('usb_media', 'Installation USB media'), option('system_disk', 'Internal GPT system disk')], expected: 'system_disk' },
      ],
    }),
    sequence({
      code: `${prefix}-02-INSTALL`, title: 'Perform installation in safe order',
      instruction: 'Operate the installation workflow and record each performed step in order.',
      actionType: 'coc1_m3_install_step_performed', source,
      steps: [option('boot_media', 'Boot installation media'), option('select_disk', 'Select the internal target disk'), option('copy_files', 'Copy operating-system files'), option('configure_device', 'Configure device drivers')],
    }),
    fields({
      code: `${prefix}-03-DRIVER`, title: 'Configure the installed network adapter',
      instruction: 'Apply the driver matching the workstation network hardware.',
      actionType: 'coc1_m3_install_driver_applied', source,
      fields: [{ id: 'network_driver', label: 'Adapter driver', options: [option('wireless', 'Wireless adapter driver'), option('ethernet', 'Ethernet adapter driver')], expected: 'ethernet' }],
    }),
    sequence({
      code: `${prefix}-04-VERIFY`, title: 'Restart and verify the installed system',
      instruction: 'Restart after applying the driver, then measure startup and adapter status.',
      actionType: 'coc1_m3_install_verification_performed', source,
      steps: [option('restart_workstation', 'Restart the workstation'), option('test_boot', 'Test installed-system boot'), option('test_adapter', 'Test network-adapter initialization')],
    }),
    single({
      code: `${prefix}-05-INTERPRET`, title: 'Interpret the final verification record',
      instruction: 'Interpret the final boot and adapter measurements and attach the measured outputs to the submission.',
      actionType: 'coc1_m3_install_interpretation_recorded', source,
      options: [option('configuration_unresolved', 'A setup or driver fault remains unresolved'), option('verified_ready', 'The installed system boots and the adapter initializes')],
      expected: 'verified_ready',
    }),
  ],
};

export const coc1M3InstallationDraft = {
  schemaVersion: 1,
  status: 'DRAFT_REQUIRES_INSTRUCTOR_REVIEW',
  publishable: false,
  approval: { instructor: null, contentGovernance: null, approvedAt: null },
  reference: {
    path: 'docs/reference/ByteQuest_Interactive_2D_Mobile_App_Todo_List.pdf',
    sha256: '16993438ced913718b2b0295d0adf773675ae7a87671f89ae3f538bd22bcc9eb',
    requirements: ['P03-19', 'P03-20', 'P03-21', 'P03-22', 'P03-23', 'P03-24', 'P03-25', 'P03-26', 'P19-01'],
  },
  preservesPackageId: 'coc1-m3-authoritative-v1',
  historyPolicy: 'Create a distinct version only after approval. Never update, relabel, migrate, re-evaluate or release existing attempts.',
  resultVisibility: 'released_only',
  releaseAuthority: 'authenticated_instructor',
  definition: proposed,
  reviewGates: [
    'An instructor must validate technical criteria and source mapping; no approved TESDA claim is made by this draft.',
    'The typed runtime must emit performed equipment actions, not a detached answer form, through the authoritative evidence gateway.',
    'The trusted backend must reconstruct operating state from ordered actions; never trust client simulation_valid, measured_result or equipment_snapshot as a grade.',
    'The backend must bind verification to the latest configuration revision and require restart after the final driver change.',
    'Interpretation must be evaluated against the trusted measurements; selecting verified_ready alone cannot satisfy verification.',
    'Run negative, missing-evidence, duplicate, restart, offline-retry, RLS, instructor-finalization and release tests on an isolated backend before publication.',
    'Obtain separate explicit approval before publishing or assigning the new version. Do not import this draft into the bulk publisher.',
  ],
};

export function installationDraftLearnerPreview() {
  return { ...buildLearnerPayload(proposed), review_only: true, publishable: false };
}

export function installationDraftRubricProposal() {
  return proposed.criteria.map(({ criterion }, index) => ({
    ...criterion,
    order_index: index + 1,
    is_required: true,
    status: 'DRAFT_REQUIRES_INSTRUCTOR_REVIEW',
    scoring_rule: { status: 'PENDING_INSTRUCTOR_VALIDATION' },
  }));
}
