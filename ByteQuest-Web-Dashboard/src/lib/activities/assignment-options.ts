// Choices of the class "Assign published content" form.
//
// The 20 simulation assessments are published with delivery_mode
// 'assessment'. An attempt enters Evaluate -> Finalize -> Release only when it
// was assigned as an Assessment (submit_attempt evaluates assessment-type
// attempts only), so assessment-only activities cannot be assigned as
// Practice.

export type DeliveryMode = 'practice' | 'assessment' | 'both';
export type AssignmentType = 'practice' | 'assessment';

export function assignmentTypesFor(mode: DeliveryMode): AssignmentType[] {
  return mode === 'assessment' ? ['assessment'] : ['practice', 'assessment'];
}

export function defaultAssignmentType(mode: DeliveryMode): AssignmentType {
  return mode === 'assessment' ? 'assessment' : 'practice';
}

/** activity_curriculum_links.delivery_kind as the dashboard labels it (spec WS2). */
export function deliveryKindLabel(kind: string | null | undefined): string | null {
  if (kind === 'simulation') return 'Simulation assessment';
  if (kind === 'form_based' || kind === 'protected_reference') return 'Form-based assessment';
  return null;
}

export interface ApprovedRubricOption {
  id: string;
  activityVersionId: string;
  title: string;
  versionNumber: number;
}

/**
 * The approved rubric of exactly this published activity version: the newest
 * approved version when there are several. Never a rubric of another version.
 */
export function approvedRubricFor<T extends ApprovedRubricOption>(rubrics: readonly T[], activityVersionId: string): T | undefined {
  if (!activityVersionId) return undefined;
  return rubrics
    .filter((rubric) => rubric.activityVersionId === activityVersionId)
    .reduce<T | undefined>((best, rubric) => (!best || rubric.versionNumber > best.versionNumber ? rubric : best), undefined);
}
