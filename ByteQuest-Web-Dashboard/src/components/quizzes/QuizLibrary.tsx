"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Plus, Search, ChevronRight, ListChecks } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { CreateQuizForm } from "./CreateQuizForm";
import { QuizDeadlineControls, type QuizDeadlineAssignment } from './QuizDeadlineControls';

export function QuizLibrary({
  quizzes,
  modules,
  serverNow,
}: {
  quizzes: {
    id: string;
    title: string;
    topic: string;
    coc: string;
    status: string;
    version: number;
    questionCount: number;
    deadlines?: QuizDeadlineAssignment[];
  }[];
  modules: { id: string; code: string; title: string }[];
  serverNow?: string;
}) {
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("active");
  const [create, setCreate] = useState(false);
  const [dirty, setDirty] = useState(false);
  useEffect(() => {
    if (!dirty) return;
    const guard = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener("beforeunload", guard);
    return () => window.removeEventListener("beforeunload", guard);
  }, [dirty]);
  const query = search.trim().toLowerCase();
  const visible = quizzes.filter(
    (quiz) =>
      (filter === "all" ||
        (filter === "active"
          ? quiz.status !== "archived"
          : quiz.status === filter)) &&
      `${quiz.title} ${quiz.topic} ${quiz.coc}`.toLowerCase().includes(query),
  );
  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Quizzes</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Create, review and publish supplementary quizzes to your classes.
          </p>
        </div>
        <Button className="min-h-11" onClick={() => setCreate(true)}>
          <Plus className="mr-2 h-4 w-4" aria-hidden="true" />
          Create quiz
        </Button>
      </header>
      <p className="text-sm text-muted-foreground">
        {quizzes.filter((quiz) => quiz.status === "draft").length} drafts ·{" "}
        {quizzes.filter((quiz) => quiz.status === "published").length} published
        · {quizzes.filter((quiz) => quiz.status === "archived").length} archived
      </p>
      <section className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="flex flex-wrap items-center gap-3 border-b border-border p-4">
          <div className="relative min-w-0 flex-1">
            <Search
              aria-hidden="true"
              className="absolute left-3 top-3 h-4 w-4 text-muted-foreground"
            />
            <Input
              className="min-h-11 pl-9"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              aria-label="Search quizzes"
              placeholder="Search title, topic or COC"
            />
          </div>
          <select
            className="min-h-11 rounded-md border border-input bg-background px-3 text-sm focus-visible:ring-2 focus-visible:ring-ring"
            value={filter}
            onChange={(event) => setFilter(event.target.value)}
            aria-label="Filter quizzes"
          >
            {["active", "draft", "published", "archived", "all"].map(
              (value) => (
                <option key={value} value={value}>
                  {value === "active"
                    ? "Active quizzes"
                    : value[0].toUpperCase() + value.slice(1)}
                </option>
              ),
            )}
          </select>
        </div>
        <p className="sr-only" role="status">
          {visible.length} quizzes shown
        </p>
        {visible.length ? (
          <ul className="divide-y divide-border">
            {visible.map((quiz) => (
              <li key={quiz.id}>
                <Link
                  href={`/quizzes/${quiz.id}`}
                  className="flex flex-wrap items-center gap-3 px-4 py-4 transition-colors hover:bg-muted/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
                >
                  <div className="min-w-0 flex-1">
                    <h2 className="break-words text-sm font-semibold">
                      {quiz.title}
                    </h2>
                    <p className="mt-1 break-words text-xs text-muted-foreground">
                      {quiz.coc} · {quiz.topic}
                    </p>
                  </div>
                  <span className="text-xs text-muted-foreground">
                    v{quiz.version} · {quiz.questionCount} questions
                  </span>
                  <Badge
                    variant={
                      quiz.status === "published" ? "secondary" : "outline"
                    }
                  >
                    {quiz.status}
                  </Badge>
                  <ChevronRight
                    className="h-4 w-4 text-muted-foreground"
                    aria-hidden="true"
                  />
                </Link>
                {quiz.deadlines?.length ? <div className="px-4 pb-4"><QuizDeadlineControls quizTitle={quiz.title} assignments={quiz.deadlines} serverNow={serverNow ?? new Date().toISOString()} /></div> : null}
              </li>
            ))}
          </ul>
        ) : (
          <div className="px-5 py-10 text-center">
            <ListChecks
              className="mx-auto h-7 w-7 text-muted-foreground"
              aria-hidden="true"
            />
            <p className="mt-3 font-medium">
              {quizzes.length
                ? "No quizzes match your search"
                : "Create your first quiz"}
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              {quizzes.length
                ? "Try another search or filter."
                : "Add questions, review them, then choose your classes."}
            </p>
          </div>
        )}
      </section>
      <Dialog
        open={create}
        onOpenChange={(open) => {
          if (
            !open &&
            dirty &&
            !window.confirm("Discard the unsaved quiz details?")
          )
            return;
          setCreate(open);
          if (!open) setDirty(false);
        }}
      >
        <DialogContent className="max-h-[90dvh] max-w-2xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Create quiz</DialogTitle>
            <DialogDescription>
              Start with a title and topic. Your private draft opens directly in
              the question editor.
            </DialogDescription>
          </DialogHeader>
          <CreateQuizForm modules={modules} onDirtyChange={setDirty} />
        </DialogContent>
      </Dialog>
    </div>
  );
}
