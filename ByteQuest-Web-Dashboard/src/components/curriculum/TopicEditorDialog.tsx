"use client";

import React, { useState } from "react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import type { LearningOutcome } from "@/lib/curriculum/types";
import { MarkdownPreview } from "./MarkdownPreview";

export type TopicDraft = { title: string; summary: string; body_markdown: string; outcome_ids: string[] };

/** Revision editor: title, summary, Markdown body with preview and outcome multi-select. */
export function TopicEditorDialog({
  open,
  heading,
  description,
  initial,
  outcomes,
  saving,
  onCancel,
  onSave,
}: {
  open: boolean;
  heading: string;
  description: string;
  initial: TopicDraft;
  outcomes: LearningOutcome[];
  saving: boolean;
  onCancel: () => void;
  onSave: (draft: TopicDraft) => void;
}) {
  // The parent remounts this dialog (key) for each editing session.
  const [draft, setDraft] = useState<TopicDraft>(initial);
  const titleValid = draft.title.trim().length >= 2 && draft.title.trim().length <= 200;
  const toggle = (id: string, checked: boolean) =>
    setDraft((current) => ({
      ...current,
      outcome_ids: checked ? [...new Set([...current.outcome_ids, id])] : current.outcome_ids.filter((value) => value !== id),
    }));

  return (
    <Dialog open={open} onOpenChange={(next) => (!next && !saving ? onCancel() : undefined)}>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>{heading}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            if (titleValid) onSave({ ...draft, title: draft.title.trim(), summary: draft.summary.trim() });
          }}
        >
          <div className="space-y-1.5">
            <Label htmlFor="topic-title">Title</Label>
            <Input
              id="topic-title"
              value={draft.title}
              maxLength={200}
              required
              aria-invalid={!titleValid}
              onChange={(event) => setDraft({ ...draft, title: event.target.value })}
            />
            {!titleValid ? <p className="text-xs text-destructive">Use a title between 2 and 200 characters.</p> : null}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="topic-summary">Summary</Label>
            <Textarea
              id="topic-summary"
              value={draft.summary}
              maxLength={1000}
              rows={2}
              onChange={(event) => setDraft({ ...draft, summary: event.target.value })}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="topic-body">Lesson content (Markdown)</Label>
            <Tabs defaultValue="write">
              <TabsList>
                <TabsTrigger value="write">Write</TabsTrigger>
                <TabsTrigger value="preview">Preview</TabsTrigger>
              </TabsList>
              <TabsContent value="write">
                <Textarea
                  id="topic-body"
                  value={draft.body_markdown}
                  maxLength={60000}
                  rows={12}
                  className="font-mono text-sm"
                  onChange={(event) => setDraft({ ...draft, body_markdown: event.target.value })}
                />
                <p className="mt-1 text-xs text-muted-foreground">
                  Supports # headings, - bullets, 1. numbered steps, **bold**, *italic*, `code` and &gt; notes. HTML is shown as plain text.
                </p>
              </TabsContent>
              <TabsContent value="preview" className="rounded-lg border border-border p-4">
                <MarkdownPreview source={draft.body_markdown} />
              </TabsContent>
            </Tabs>
          </div>
          <fieldset className="space-y-2">
            <legend className="text-sm font-medium">Learning outcomes (official performance criteria)</legend>
            {outcomes.length === 0 ? <p className="text-sm text-muted-foreground">This module has no performance criteria.</p> : null}
            <div className="grid gap-2">
              {outcomes.map((outcome) => (
                <label key={outcome.id} className="flex min-h-11 cursor-pointer items-start gap-3 rounded-lg border border-border p-2.5 text-sm">
                  <Checkbox
                    checked={draft.outcome_ids.includes(outcome.id)}
                    onCheckedChange={(checked) => toggle(outcome.id, checked === true)}
                    aria-label={`PC ${outcome.code}`}
                    className="mt-0.5"
                  />
                  <span>
                    <span className="font-semibold">{outcome.code}</span> {outcome.statement}
                  </span>
                </label>
              ))}
            </div>
          </fieldset>
          <DialogFooter className="gap-2">
            <Button type="button" variant="outline" onClick={onCancel} disabled={saving}>
              Cancel
            </Button>
            <Button type="submit" disabled={saving || !titleValid}>
              {saving ? "Saving…" : "Save draft"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
