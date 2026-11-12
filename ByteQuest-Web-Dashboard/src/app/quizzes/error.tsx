"use client";

import { Button } from "@/components/ui/button";

export default function QuizError({ reset }: { reset: () => void }) {
  return (
    <div role="alert" className="mx-auto max-w-xl space-y-3 p-6">
      <h1 className="text-xl font-semibold">Quiz data could not be loaded</h1>
      <p className="text-sm text-muted-foreground">
        Check your connection and try again. Your saved quizzes and learner
        results are retained.
      </p>
      <Button onClick={reset}>Try again</Button>
    </div>
  );
}
