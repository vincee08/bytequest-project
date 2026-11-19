"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { ChevronRight, ListChecks, Plus, Search } from "lucide-react";
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
import { quizTypeLabels } from "@/lib/quizzes/authoring";
import {
  modulesForCoc,
  topicsForScope,
  type CurriculumCatalog,
} from "@/lib/quizzes/curriculum";
import {
  defaultLibraryFilters,
  filterLibrary,
  libraryStatusLabels,
  type LibraryFilters,
  type LibraryQuiz,
} from "@/lib/quizzes/library";
import { CreateQuizForm } from "./CreateQuizForm";
import {
  QuizDeadlineControls,
  type QuizDeadlineAssignment,
} from "./QuizDeadlineControls";

const selectClass =
  "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60";

export type LibraryQuizWithDeadlines = LibraryQuiz & {
  deadlines: QuizDeadlineAssignment[];
};

export function QuizLibrary({
  quizzes,
  catalog,
  serverNow,
}: {
  quizzes: LibraryQuizWithDeadlines[];
  catalog: CurriculumCatalog;
  serverNow: string;
}) {
  const [filters, setFilters] = useState<LibraryFilters>(defaultLibraryFilters);
  const [create, setCreate] = useState(false);
  const [dirty, setDirty] = useState(false);
  useEffect(() => {
    if (!dirty) return;
    const guard = (event: BeforeUnloadEvent) => event.preventDefault();
    window.addEventListener("beforeunload", guard);
    return () => window.removeEventListener("beforeunload", guard);
  }, [dirty]);
  const moduleCoc = useMemo(
    () => new Map(catalog.modules.map((module) => [module.id, module.cocId])),
    [catalog.modules],
  );
  const visible = filterLibrary(quizzes, filters, moduleCoc);
  const modules = filters.cocId
    ? modulesForCoc(catalog, filters.cocId)
    : catalog.modules;
  const topics = filters.cocId
    ? topicsForScope(
        catalog,
        filters.cocId,
        filters.moduleId ? [filters.moduleId] : [],
      )
    : catalog.topics;
  const set = (patch: Partial<LibraryFilters>) =>
    setFilters((current) => ({ ...current, ...patch }));
  const counts = (status: string) =>
    quizzes.filter((quiz) => quiz.status === status).length;
  const filtered =
    JSON.stringify({ ...filters, sort: "updated" }) !==
    JSON.stringify(defaultLibraryFilters);

  return (
    <div className="space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Quizzes</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Curriculum-based quizzes organised by COC, module, topic and
            learning outcome.
          </p>
        </div>
        <Button className="min-h-11" onClick={() => setCreate(true)}>
          <Plus className="mr-2 h-4 w-4" aria-hidden="true" />
          Create quiz
        </Button>
      </header>
      <p className="text-sm text-muted-foreground">
        {counts("draft")} drafts · {counts("published")} published ·{" "}
        {counts("closed")} closed · {counts("archived")} archived
      </p>
      <section className="overflow-hidden rounded-xl border border-border bg-card">
        <div className="grid gap-3 border-b border-border p-4 sm:grid-cols-2 lg:grid-cols-6">
          <div className="relative min-w-0 sm:col-span-2">
            <Search
              aria-hidden="true"
              className="absolute left-3 top-3.5 h-4 w-4 text-muted-foreground"
            />
            <Input
              className="min-h-11 pl-9"
              value={filters.search}
              onChange={(event) => set({ search: event.target.value })}
              aria-label="Search quizzes"
              placeholder="Search title, topic or module"
            />
          </div>
          <select
            className={selectClass}
            aria-label="Filter by COC"
            value={filters.cocId}
            onChange={(event) =>
              set({ cocId: event.target.value, moduleId: "", topicId: "" })
            }
          >
            <option value="">All COCs</option>
            {catalog.cocs.map((coc) => (
              <option key={coc.id} value={coc.id}>
                {coc.code.toUpperCase()}
              </option>
            ))}
          </select>
          <select
            className={selectClass}
            aria-label="Filter by module"
            value={filters.moduleId}
            onChange={(event) => set({ moduleId: event.target.value, topicId: "" })}
          >
            <option value="">All modules</option>
            {modules.map((module) => (
              <option key={module.id} value={module.id}>
                {module.code} {module.title}
              </option>
            ))}
          </select>
          <select
            className={selectClass}
            aria-label="Filter by topic"
            value={filters.topicId}
            onChange={(event) => set({ topicId: event.target.value })}
          >
            <option value="">All topics</option>
            {topics.map((topic) => (
              <option key={topic.id} value={topic.id}>
                {topic.title}
              </option>
            ))}
          </select>
          <select
            className={selectClass}
            aria-label="Filter by quiz type"
            value={filters.quizType}
            onChange={(event) => set({ quizType: event.target.value })}
          >
            <option value="">All types</option>
            {Object.entries(quizTypeLabels).map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
          <select
            className={selectClass}
            aria-label="Filter by status"
            value={filters.status}
            onChange={(event) => set({ status: event.target.value })}
          >
            <option value="active">Not archived</option>
            <option value="draft">Draft</option>
            <option value="published">Published</option>
            <option value="closed">Closed</option>
            <option value="archived">Archived</option>
            <option value="all">All statuses</option>
          </select>
          <select
            className={selectClass}
            aria-label="Sort quizzes"
            value={filters.sort}
            onChange={(event) =>
              set({ sort: event.target.value as LibraryFilters["sort"] })
            }
          >
            <option value="updated">Recently updated</option>
            <option value="title">Title A–Z</option>
            <option value="due">Next deadline</option>
            <option value="status">Status</option>
          </select>
          {filtered ? (
            <Button
              variant="ghost"
              className="min-h-11"
              onClick={() => setFilters(defaultLibraryFilters)}
            >
              Clear filters
            </Button>
          ) : null}
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
                      {quiz.coc}
                      {quiz.mapped
                        ? quiz.moduleCodes.length
                          ? ` · ${quiz.moduleCodes.join(", ")}`
                          : " · Whole COC"
                        : " · Not mapped to a module"}{" "}
                      · {quiz.topic}
                    </p>
                  </div>
                  <span className="text-xs text-muted-foreground">
                    v{quiz.version} · {quiz.questionCount} questions
                    {quiz.essayCount ? ` · ${quiz.essayCount} essay` : ""}
                    {quiz.timeLimitMinutes
                      ? ` · ${quiz.timeLimitMinutes} min`
                      : ""}
                  </span>
                  {quiz.quizType ? (
                    <Badge variant="outline">{quizTypeLabels[quiz.quizType]}</Badge>
                  ) : null}
                  {!quiz.mapped ? (
                    <Badge variant="outline">Not mapped</Badge>
                  ) : null}
                  <Badge
                    variant={
                      quiz.status === "published"
                        ? "secondary"
                        : quiz.status === "closed"
                          ? "default"
                          : "outline"
                    }
                  >
                    {libraryStatusLabels[quiz.status]}
                    {quiz.hasDraft && quiz.status !== "draft" ? " · draft open" : ""}
                  </Badge>
                  <ChevronRight
                    className="h-4 w-4 text-muted-foreground"
                    aria-hidden="true"
                  />
                </Link>
                {quiz.deadlines.length ? (
                  <div className="px-4 pb-4">
                    <QuizDeadlineControls
                      quizTitle={quiz.title}
                      assignments={quiz.deadlines}
                      serverNow={serverNow}
                    />
                  </div>
                ) : null}
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
                ? "No quizzes match these filters"
                : "Create your first quiz"}
            </p>
            <p className="mt-1 text-sm text-muted-foreground">
              {quizzes.length
                ? "Try another COC, module, type or status."
                : "Choose a COC and modules, state the focus, then add and review questions."}
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
              Place the quiz in the curriculum and state its focus. Your
              private draft opens directly in the question editor.
            </DialogDescription>
          </DialogHeader>
          <CreateQuizForm catalog={catalog} onDirtyChange={setDirty} />
        </DialogContent>
      </Dialog>
    </div>
  );
}
