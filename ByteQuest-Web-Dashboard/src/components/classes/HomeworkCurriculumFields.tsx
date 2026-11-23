"use client";

import { useEffect, useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  SUBMISSION_FORMATS,
  criteriaTotal,
  formatRequiresFiles,
  formatTakesFiles,
  selectCoc,
  selectMission,
  submissionFormatLabels,
  submissionRuleSummary,
  type CurriculumDraft,
} from "@/lib/evaluations/homework";
import { evaluationsClient, type CurriculumOptions } from "@/lib/evaluations/types";
import { createClient } from "@/lib/supabase/client";

const selectClass = "h-11 w-full min-w-0 rounded-lg border border-input bg-card px-3 text-sm shadow-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/25";
const newId = () => (typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `c${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`);

/** Loads the COC -> mission -> module catalog through the instructor's RLS when not provided. */
export function useCurriculumOptions(initial?: CurriculumOptions | null) {
  const [options, setOptions] = useState<CurriculumOptions | null>(initial ?? null);
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    if (options) return;
    let cancelled = false;
    const client = evaluationsClient(createClient());
    void Promise.all([
      client.from("coc_modules").select("id,coc_code,title").order("coc_code"),
      client.from("missions").select("mission_code,title,coc_id").order("mission_code"),
      client.from("curriculum_modules").select("id,coc_module_id,coc_code,code,title,sequence_order").order("coc_code").order("sequence_order"),
      client.from("mission_curriculum_links").select("mission_code,module_id"),
    ]).then(([cocs, missions, modules, links]) => {
      if (cancelled) return;
      if (cocs.error || missions.error || modules.error || links.error) { setError(true); return; }
      setOptions({ cocs: cocs.data ?? [], missions: missions.data ?? [], modules: modules.data ?? [], links: links.data ?? [] });
    }, () => { if (!cancelled) setError(true); });
    return () => { cancelled = true; };
  }, [options, attempt]);
  return { options, error, retry: () => { setError(false); setAttempt((value) => value + 1); } };
}

/** COC -> mission -> module, learning objectives, criteria with points and requirements. */
export function HomeworkCurriculumFields({
  value,
  onChange,
  options,
  idPrefix,
}: {
  value: CurriculumDraft;
  onChange: (next: CurriculumDraft) => void;
  options: CurriculumOptions;
  idPrefix: string;
}) {
  const missions = options.missions.filter((m) => !value.coc_module_id || m.coc_id === value.coc_module_id);
  const modules = options.modules.filter((m) => !value.coc_module_id || m.coc_module_id === value.coc_module_id);
  const total = criteriaTotal(value.criteria.map((c) => ({ max_points: Number(c.max_points) || 0 })));
  const set = (patch: Partial<CurriculumDraft>) => onChange({ ...value, ...patch });

  return (
    <div className="space-y-5">
      <fieldset className="space-y-3">
        <legend className="text-sm font-semibold">Competency</legend>
        <div className="grid gap-3 md:grid-cols-3">
          <div className="space-y-1.5">
            <Label htmlFor={`${idPrefix}-coc`}>COC</Label>
            <select id={`${idPrefix}-coc`} className={selectClass} value={value.coc_module_id}
              onChange={(event) => onChange(selectCoc(value, event.target.value, options))}>
              <option value="">Not linked to a COC</option>
              {options.cocs.map((coc) => <option key={coc.id} value={coc.id}>{coc.coc_code.toUpperCase()} · {coc.title}</option>)}
            </select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor={`${idPrefix}-mission`}>Mission</Label>
            <select id={`${idPrefix}-mission`} className={selectClass} value={value.mission_code} disabled={!value.coc_module_id}
              onChange={(event) => onChange(selectMission(value, event.target.value, options))}>
              <option value="">{value.coc_module_id ? "No specific mission" : "Choose a COC first"}</option>
              {missions.map((mission) => <option key={mission.mission_code} value={mission.mission_code}>{mission.mission_code.toUpperCase().replace("_", " ")} · {mission.title}</option>)}
            </select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor={`${idPrefix}-module`}>Module (learning outcome)</Label>
            <select id={`${idPrefix}-module`} className={selectClass} value={value.module_id} disabled={!value.coc_module_id}
              onChange={(event) => set({ module_id: event.target.value })}>
              <option value="">{value.coc_module_id ? "No specific module" : "Choose a COC first"}</option>
              {modules.map((module) => <option key={module.id} value={module.id}>{module.code} {module.title}</option>)}
            </select>
          </div>
        </div>
        <p className="text-xs text-muted-foreground">Choosing a mission selects its curriculum module; you can change the module.</p>
      </fieldset>

      <fieldset className="space-y-2">
        <legend className="text-sm font-semibold">Learning objectives</legend>
        {value.learning_objectives.map((objective, index) => (
          <div key={index} className="flex items-center gap-2">
            <Label htmlFor={`${idPrefix}-objective-${index}`} className="sr-only">Learning objective {index + 1}</Label>
            <Input id={`${idPrefix}-objective-${index}`} className="min-h-11" maxLength={500} value={objective}
              onChange={(event) => set({ learning_objectives: value.learning_objectives.map((item, i) => i === index ? event.target.value : item) })} />
            <Button type="button" variant="ghost" size="icon" className="h-11 w-11 shrink-0" aria-label={`Remove learning objective ${index + 1}`}
              onClick={() => set({ learning_objectives: value.learning_objectives.filter((_, i) => i !== index) })}>
              <Trash2 className="h-4 w-4" aria-hidden="true" />
            </Button>
          </div>
        ))}
        <Button type="button" variant="outline" className="min-h-11" disabled={value.learning_objectives.length >= 20}
          onClick={() => set({ learning_objectives: [...value.learning_objectives, ""] })}>
          <Plus className="mr-2 h-4 w-4" aria-hidden="true" />Add objective
        </Button>
      </fieldset>

      <fieldset className="space-y-2">
        <legend className="text-sm font-semibold">Evaluation criteria</legend>
        {value.criteria.map((criterion, index) => (
          <div key={criterion.id} className="grid gap-2 rounded-lg border border-border p-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)_7rem_auto] md:items-end">
            <div className="space-y-1">
              <Label htmlFor={`${idPrefix}-criterion-${index}`}>Criterion</Label>
              <Input id={`${idPrefix}-criterion-${index}`} className="min-h-11" maxLength={200} value={criterion.criterion}
                onChange={(event) => set({ criteria: value.criteria.map((item, i) => i === index ? { ...item, criterion: event.target.value } : item) })} />
            </div>
            <div className="space-y-1">
              <Label htmlFor={`${idPrefix}-criterion-description-${index}`}>Description (optional)</Label>
              <Input id={`${idPrefix}-criterion-description-${index}`} className="min-h-11" maxLength={1000} value={criterion.description}
                onChange={(event) => set({ criteria: value.criteria.map((item, i) => i === index ? { ...item, description: event.target.value } : item) })} />
            </div>
            <div className="space-y-1">
              <Label htmlFor={`${idPrefix}-criterion-points-${index}`}>Points</Label>
              <Input id={`${idPrefix}-criterion-points-${index}`} className="min-h-11" type="number" min={0.5} max={1000} step="0.5" value={criterion.max_points}
                onChange={(event) => set({ criteria: value.criteria.map((item, i) => i === index ? { ...item, max_points: event.target.value } : item) })} />
            </div>
            <Button type="button" variant="ghost" size="icon" className="h-11 w-11" aria-label={`Remove criterion ${index + 1}`}
              onClick={() => set({ criteria: value.criteria.filter((_, i) => i !== index) })}>
              <Trash2 className="h-4 w-4" aria-hidden="true" />
            </Button>
          </div>
        ))}
        <div className="flex flex-wrap items-end gap-3">
          <Button type="button" variant="outline" className="min-h-11" disabled={value.criteria.length >= 20}
            onClick={() => set({ criteria: [...value.criteria, { id: newId(), criterion: "", description: "", max_points: "10" }] })}>
            <Plus className="mr-2 h-4 w-4" aria-hidden="true" />Add criterion
          </Button>
          <div className="space-y-1">
            <Label htmlFor={`${idPrefix}-max-score`}>Maximum score</Label>
            <Input id={`${idPrefix}-max-score`} className="min-h-11 w-32" type="number" min={1} max={1000} step="0.5"
              value={value.criteria.length ? String(total) : value.max_score} readOnly={value.criteria.length > 0}
              aria-describedby={`${idPrefix}-max-score-help`}
              onChange={(event) => set({ max_score: event.target.value })} />
          </div>
        </div>
        <p id={`${idPrefix}-max-score-help`} className="text-xs text-muted-foreground" aria-live="polite">
          {value.criteria.length ? `The maximum score is the criteria total: ${total} points.` : "Without criteria, choose the maximum score directly (default 100)."}
        </p>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="text-sm font-semibold">Learner submission</legend>
        <div className="grid gap-3 md:grid-cols-3">
          <div className="space-y-1.5">
            <Label htmlFor={`${idPrefix}-submission-format`}>Learner submits</Label>
            <select id={`${idPrefix}-submission-format`} className={selectClass} value={value.submission_format}
              onChange={(event) => set({ submission_format: event.target.value as CurriculumDraft["submission_format"] })}>
              {SUBMISSION_FORMATS.map((format) => <option key={format} value={format}>{submissionFormatLabels[format]}</option>)}
            </select>
          </div>
          {formatRequiresFiles(value.submission_format) ? (
            <div className="space-y-1.5">
              <Label htmlFor={`${idPrefix}-required-files`}>Required files (at least)</Label>
              <select id={`${idPrefix}-required-files`} className={selectClass} value={value.required_file_count}
                onChange={(event) => set({ required_file_count: event.target.value })}>
                {[1, 2, 3, 4, 5].map((count) => <option key={count} value={String(count)}>{count}</option>)}
              </select>
            </div>
          ) : null}
          {formatTakesFiles(value.submission_format) ? (
            <div className="space-y-1.5">
              <Label htmlFor={`${idPrefix}-file-types`}>Accepted files</Label>
              <select id={`${idPrefix}-file-types`} className={selectClass} value={value.accepted_file_types}
                onChange={(event) => set({ accepted_file_types: event.target.value as CurriculumDraft["accepted_file_types"] })}>
                <option value="any">Any supported file (PDF, image, text)</option>
                <option value="image">Images only (JPG, PNG, WEBP)</option>
              </select>
            </div>
          ) : null}
        </div>
        <p className="text-xs text-muted-foreground" aria-live="polite">
          Learners see this rule in the app and cannot submit until it is met: {submissionRuleSummary({
            submission_format: value.submission_format,
            required_file_count: formatRequiresFiles(value.submission_format) ? Number(value.required_file_count) || 1 : 0,
            accepted_file_types: value.accepted_file_types,
          })}
        </p>
        <div className="space-y-1.5">
          <Label htmlFor={`${idPrefix}-requirements`}>Additional instructions for the submission (optional)</Label>
          <Textarea id={`${idPrefix}-requirements`} rows={3} maxLength={5000} value={value.submission_requirements}
            placeholder="For example: photograph each crimped end in good light"
            onChange={(event) => set({ submission_requirements: event.target.value })} />
        </div>
      </fieldset>
    </div>
  );
}
