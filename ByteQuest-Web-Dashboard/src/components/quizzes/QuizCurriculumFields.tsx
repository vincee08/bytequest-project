"use client";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  difficultyLabels,
  quizTypeLabels,
  releaseModeLabels,
} from "@/lib/quizzes/authoring";
import {
  modulesForCoc,
  outcomesForScope,
  pruneSelections,
  topicsForScope,
  type CurriculumCatalog,
} from "@/lib/quizzes/curriculum";
import type { QuizFormState } from "@/lib/quizzes/form";
import type {
  QuizDifficulty,
  QuizType,
  ResultReleaseMode,
} from "@/lib/quizzes/types";

const selectClass =
  "flex min-h-11 w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-60";
const choiceClass =
  "flex min-h-11 cursor-pointer items-start gap-3 rounded-lg border border-border p-3 text-sm focus-within:ring-2 focus-within:ring-ring";

function FieldError({ id, messages }: { id: string; messages?: string[] }) {
  return messages?.length ? (
    <p id={id} role="alert" className="text-sm text-destructive">
      {messages.join(" ")}
    </p>
  ) : null;
}

/**
 * COC (required) -> scope (whole COC or modules) -> published topic ->
 * performance criteria -> focus -> instructions and settings.
 */
export function QuizCurriculumFields({
  idPrefix,
  catalog,
  value,
  onChange,
  errors,
  disabled = false,
  settingsLocked = false,
  hasEssays = false,
}: {
  idPrefix: string;
  catalog: CurriculumCatalog;
  value: QuizFormState;
  onChange: (next: QuizFormState) => void;
  errors: Record<string, string[] | undefined>;
  disabled?: boolean;
  /** Published version without a draft: version settings are read-only. */
  settingsLocked?: boolean;
  hasEssays?: boolean;
}) {
  const modules = value.cocModuleId
    ? modulesForCoc(catalog, value.cocModuleId)
    : [];
  const scopeModuleIds = value.scope === "coc" ? [] : value.moduleIds;
  const outcomes = value.cocModuleId
    ? outcomesForScope(catalog, value.cocModuleId, scopeModuleIds)
    : [];
  const topics = value.cocModuleId
    ? topicsForScope(catalog, value.cocModuleId, scopeModuleIds)
    : [];
  const moduleById = new Map(catalog.modules.map((module) => [module.id, module]));
  const id = (name: string) => `${idPrefix}-${name}`;

  function update(patch: Partial<QuizFormState>) {
    const next = { ...value, ...patch };
    const pruned = pruneSelections(
      catalog,
      next.cocModuleId,
      next.scope === "coc" ? [] : next.moduleIds,
      next.topicId,
      next.outcomeIds,
    );
    onChange({
      ...next,
      moduleIds: next.scope === "coc" ? next.moduleIds : pruned.moduleIds,
      topicId: pruned.topicId,
      outcomeIds: pruned.outcomeIds,
    });
  }

  return (
    <fieldset disabled={disabled} className="space-y-5">
      <div className="space-y-2">
        <Label htmlFor={id("title")}>
          Quiz title <span aria-hidden="true">*</span>
        </Label>
        <Input
          id={id("title")}
          value={value.title}
          onChange={(event) => update({ title: event.target.value })}
          minLength={3}
          maxLength={200}
          required
          aria-invalid={!!errors.title}
          aria-describedby={errors.title ? id("title-error") : undefined}
          placeholder="Hardware assembly check"
        />
        <FieldError id={id("title-error")} messages={errors.title} />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor={id("coc")}>
            COC <span aria-hidden="true">*</span>
          </Label>
          <select
            id={id("coc")}
            className={selectClass}
            value={value.cocModuleId}
            required
            aria-invalid={!!errors.cocModuleId}
            aria-describedby={errors.cocModuleId ? id("coc-error") : undefined}
            onChange={(event) =>
              update({
                cocModuleId: event.target.value,
                moduleIds: [],
                topicId: "",
                outcomeIds: [],
              })
            }
          >
            <option value="">Select a COC</option>
            {catalog.cocs.map((coc) => (
              <option key={coc.id} value={coc.id}>
                {coc.code.toUpperCase()} — {coc.title}
              </option>
            ))}
          </select>
          <FieldError id={id("coc-error")} messages={errors.cocModuleId} />
        </div>
        <div className="space-y-2">
          <Label htmlFor={id("type")}>Quiz type</Label>
          <select
            id={id("type")}
            className={selectClass}
            value={value.quizType}
            onChange={(event) =>
              update({ quizType: event.target.value as QuizType })
            }
          >
            {Object.entries(quizTypeLabels).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
        </div>
      </div>

      <fieldset className="space-y-3" disabled={!value.cocModuleId || disabled}>
        <legend className="text-sm font-medium">
          Scope <span aria-hidden="true">*</span>
        </legend>
        <div className="grid gap-2 sm:grid-cols-2">
          {(
            [
              ["coc", "Whole COC", "Pre-assessments and summative reviews"],
              ["modules", "Selected modules", "One or more modules of this COC"],
            ] as const
          ).map(([scope, label, hint]) => (
            <label
              key={scope}
              className={`${choiceClass} ${value.scope === scope ? "border-primary bg-primary/5" : ""}`}
            >
              <input
                type="radio"
                name={id("scope")}
                className="mt-1 accent-primary"
                checked={value.scope === scope}
                onChange={() => update({ scope })}
              />
              <span>
                <span className="block font-medium">{label}</span>
                <span className="block text-xs text-muted-foreground">
                  {hint}
                </span>
              </span>
            </label>
          ))}
        </div>
        {value.scope === "modules" ? (
          value.cocModuleId ? (
            <div className="space-y-2" role="group" aria-label="Modules">
              {modules.map((module) => (
                <label key={module.id} className={choiceClass}>
                  <input
                    type="checkbox"
                    className="mt-1 h-4 w-4 accent-primary"
                    checked={value.moduleIds.includes(module.id)}
                    onChange={(event) =>
                      update({
                        moduleIds: event.target.checked
                          ? [...value.moduleIds, module.id]
                          : value.moduleIds.filter((item) => item !== module.id),
                      })
                    }
                  />
                  <span className="min-w-0 break-words">
                    <span className="font-medium">{module.code}</span>{" "}
                    {module.title}
                  </span>
                </label>
              ))}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              Select a COC to choose its modules.
            </p>
          )
        ) : null}
        <FieldError id={id("scope-error")} messages={errors.moduleIds} />
      </fieldset>

      <div className="space-y-2">
        <Label htmlFor={id("topic")}>Topic (optional)</Label>
        <select
          id={id("topic")}
          className={selectClass}
          value={value.topicId}
          disabled={!value.cocModuleId || disabled}
          onChange={(event) => update({ topicId: event.target.value })}
        >
          <option value="">
            {topics.length
              ? "No specific topic"
              : "No published topics for this scope yet"}
          </option>
          {topics.map((topic) => (
            <option key={topic.id} value={topic.id}>
              {moduleById.get(topic.moduleId)?.code} · {topic.title}
            </option>
          ))}
        </select>
        <FieldError id={id("topic-error")} messages={errors.topicId} />
      </div>

      <fieldset
        className="space-y-2"
        disabled={!value.cocModuleId || disabled}
      >
        <legend className="text-sm font-medium">
          Learning outcomes (performance criteria)
        </legend>
        <p className="text-xs text-muted-foreground">
          Official TESDA CSS NC II performance criteria of the selected scope.
        </p>
        {outcomes.length ? (
          <div className="max-h-72 space-y-2 overflow-y-auto rounded-lg border border-border p-2">
            {outcomes.map((outcome) => (
              <label key={outcome.id} className={choiceClass}>
                <input
                  type="checkbox"
                  className="mt-1 h-4 w-4 shrink-0 accent-primary"
                  checked={value.outcomeIds.includes(outcome.id)}
                  onChange={(event) =>
                    update({
                      outcomeIds: event.target.checked
                        ? [...value.outcomeIds, outcome.id]
                        : value.outcomeIds.filter((item) => item !== outcome.id),
                    })
                  }
                />
                <span className="min-w-0 break-words">
                  <span className="font-medium">
                    {moduleById.get(outcome.moduleId)?.code} · PC {outcome.code}
                  </span>{" "}
                  <span className="text-muted-foreground">
                    {outcome.statement}
                  </span>
                </span>
              </label>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            {value.cocModuleId
              ? "Select modules to list their performance criteria."
              : "Select a COC first."}
          </p>
        )}
        <FieldError id={id("outcome-error")} messages={errors.outcomeIds} />
      </fieldset>

      <div className="space-y-2">
        <Label htmlFor={id("focus")}>
          Focus — what this quiz assesses <span aria-hidden="true">*</span>
        </Label>
        <Textarea
          id={id("focus")}
          rows={3}
          maxLength={1000}
          required
          value={value.focus}
          onChange={(event) => update({ focus: event.target.value })}
          aria-invalid={!!errors.focus}
          aria-describedby={errors.focus ? id("focus-error") : undefined}
          placeholder="Safe installation of CPU, memory and storage following ESD procedures."
        />
        <FieldError id={id("focus-error")} messages={errors.focus} />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="space-y-2">
          <Label htmlFor={id("difficulty")}>Difficulty</Label>
          <select
            id={id("difficulty")}
            className={selectClass}
            value={value.difficulty}
            onChange={(event) =>
              update({ difficulty: event.target.value as QuizDifficulty })
            }
          >
            {Object.entries(difficultyLabels).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
        </div>
        <fieldset className="space-y-2" disabled={settingsLocked || disabled}>
          <legend className="text-sm font-medium">Time limit</legend>
          <label className="flex min-h-11 items-center gap-3 text-sm">
            <input
              type="checkbox"
              className="h-4 w-4 accent-primary"
              checked={value.timed}
              onChange={(event) => update({ timed: event.target.checked })}
            />
            Limit each attempt
          </label>
          {value.timed ? (
            <div className="flex items-center gap-2">
              <Input
                id={id("minutes")}
                type="number"
                inputMode="numeric"
                min={1}
                max={240}
                className="min-h-11 w-28"
                value={value.timeLimitMinutes}
                aria-label="Time limit in minutes"
                aria-invalid={!!errors.timeLimitMinutes}
                onChange={(event) =>
                  update({ timeLimitMinutes: event.target.value })
                }
              />
              <span className="text-sm text-muted-foreground">minutes</span>
            </div>
          ) : null}
          <FieldError id={id("minutes-error")} messages={errors.timeLimitMinutes} />
        </fieldset>
      </div>

      <fieldset className="space-y-2" disabled={settingsLocked || disabled}>
        <legend className="text-sm font-medium">Result release</legend>
        {(
          Object.entries(releaseModeLabels) as [ResultReleaseMode, string][]
        ).map(([mode, label]) => (
          <label
            key={mode}
            className={`${choiceClass} ${value.resultReleaseMode === mode ? "border-primary bg-primary/5" : ""}`}
          >
            <input
              type="radio"
              name={id("release")}
              className="mt-1 accent-primary"
              checked={value.resultReleaseMode === mode}
              disabled={mode === "immediate" && hasEssays}
              onChange={() => update({ resultReleaseMode: mode })}
            />
            <span>{label}</span>
          </label>
        ))}
        <p className="text-xs text-muted-foreground">
          Quizzes with scenario essays always use instructor release: you
          score each essay, then finalize and release the result.
        </p>
      </fieldset>

      <div className="space-y-2">
        <Label htmlFor={id("instructions")}>Learner instructions (optional)</Label>
        <Textarea
          id={id("instructions")}
          rows={2}
          maxLength={2000}
          value={value.instructions}
          disabled={settingsLocked || disabled}
          onChange={(event) => update({ instructions: event.target.value })}
          placeholder="Read each scenario before answering."
        />
        {settingsLocked ? (
          <p className="text-xs text-muted-foreground">
            The published version keeps its instructions, time limit and
            release mode. Create a new draft version to change them.
          </p>
        ) : null}
      </div>

      <div className="space-y-2">
        <Label htmlFor={id("description")}>
          Instructor description (optional)
        </Label>
        <Textarea
          id={id("description")}
          rows={2}
          maxLength={2000}
          value={value.description}
          onChange={(event) => update({ description: event.target.value })}
          placeholder="Purpose, intended learner group, or review notes."
        />
      </div>
    </fieldset>
  );
}
