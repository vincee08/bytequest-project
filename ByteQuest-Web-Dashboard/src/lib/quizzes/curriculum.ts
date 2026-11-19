/**
 * Curriculum catalog for quiz authoring: COC -> module (official curriculum
 * learning outcome) -> published topic -> learning outcome (official
 * performance criterion). Built on the server from the curriculum tables.
 */
export interface CurriculumCoc {
  id: string;
  code: string;
  title: string;
}
export interface CurriculumModule {
  id: string;
  cocId: string;
  cocCode: string;
  code: string;
  title: string;
  sequenceOrder: number;
}
export interface CurriculumOutcome {
  id: string;
  moduleId: string;
  code: string;
  statement: string;
  sequenceOrder: number;
}
export interface CurriculumTopic {
  id: string;
  moduleId: string;
  title: string;
  summary: string | null;
  sequenceOrder: number;
}
export interface CurriculumCatalog {
  cocs: CurriculumCoc[];
  modules: CurriculumModule[];
  outcomes: CurriculumOutcome[];
  topics: CurriculumTopic[];
}

export function modulesForCoc(catalog: CurriculumCatalog, cocId: string) {
  return catalog.modules
    .filter((module) => module.cocId === cocId)
    .sort((a, b) => a.sequenceOrder - b.sequenceOrder);
}

/** Modules in scope: the selected modules, or every module of a whole-COC quiz. */
export function scopeModules(
  catalog: CurriculumCatalog,
  cocId: string,
  moduleIds: string[],
) {
  const modules = modulesForCoc(catalog, cocId);
  return moduleIds.length
    ? modules.filter((module) => moduleIds.includes(module.id))
    : modules;
}

export function outcomesForScope(
  catalog: CurriculumCatalog,
  cocId: string,
  moduleIds: string[],
) {
  const scope = scopeModules(catalog, cocId, moduleIds);
  const order = new Map(scope.map((module, index) => [module.id, index]));
  return catalog.outcomes
    .filter((outcome) => order.has(outcome.moduleId))
    .sort(
      (a, b) =>
        (order.get(a.moduleId) ?? 0) - (order.get(b.moduleId) ?? 0) ||
        a.sequenceOrder - b.sequenceOrder,
    );
}

export function topicsForScope(
  catalog: CurriculumCatalog,
  cocId: string,
  moduleIds: string[],
) {
  const scope = new Set(
    scopeModules(catalog, cocId, moduleIds).map((module) => module.id),
  );
  return catalog.topics
    .filter((topic) => scope.has(topic.moduleId))
    .sort((a, b) => a.sequenceOrder - b.sequenceOrder);
}

/** Keeps only selections that remain valid after the COC or modules change. */
export function pruneSelections(
  catalog: CurriculumCatalog,
  cocId: string,
  moduleIds: string[],
  topicId: string,
  outcomeIds: string[],
) {
  const validModules = modulesForCoc(catalog, cocId).map((module) => module.id);
  const modules = moduleIds.filter((id) => validModules.includes(id));
  const outcomes = new Set(
    outcomesForScope(catalog, cocId, modules).map((outcome) => outcome.id),
  );
  const topics = new Set(
    topicsForScope(catalog, cocId, modules).map((topic) => topic.id),
  );
  return {
    moduleIds: modules,
    topicId: topics.has(topicId) ? topicId : "",
    outcomeIds: outcomeIds.filter((id) => outcomes.has(id)),
  };
}

/**
 * Short learner-facing topic label stored in quizzes.topic: the chosen topic
 * title, otherwise the module codes and titles, otherwise the COC title.
 */
export function quizTopicLabel(
  catalog: CurriculumCatalog,
  cocId: string,
  moduleIds: string[],
  topicId: string,
) {
  const topic = catalog.topics.find((item) => item.id === topicId);
  if (topic) return topic.title.slice(0, 240);
  const modules = scopeModules(catalog, cocId, moduleIds);
  if (moduleIds.length && modules.length) {
    return modules
      .map((module) => `${module.code} ${module.title}`)
      .join("; ")
      .slice(0, 240);
  }
  const coc = catalog.cocs.find((item) => item.id === cocId);
  return (coc ? `${coc.code.toUpperCase()} ${coc.title}` : "Whole COC").slice(
    0,
    240,
  );
}

export function scopeSummary(
  catalog: CurriculumCatalog,
  cocId: string | null,
  moduleIds: string[],
) {
  const coc = catalog.cocs.find((item) => item.id === cocId);
  if (!coc) return "Not mapped to a COC";
  if (!moduleIds.length) return `${coc.code.toUpperCase()} · Whole COC`;
  const codes = scopeModules(catalog, coc.id, moduleIds).map(
    (module) => module.code,
  );
  return `${coc.code.toUpperCase()} · ${codes.join(", ")}`;
}
