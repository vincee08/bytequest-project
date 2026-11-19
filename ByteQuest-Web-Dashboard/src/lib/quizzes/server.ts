import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/types/database.generated";
import { createAdminSupabaseClient } from "@/lib/supabase/admin";
import type { CurriculumCatalog } from "./curriculum";
import {
  quizDb,
  type CurriculumModuleRow,
  type CurriculumTopicRow,
  type LearningOutcomeRow,
  type TopicRevisionRow,
} from "./types";

/** COCs, modules, performance criteria and published topics (latest published revision title). */
export async function loadCurriculumCatalog(
  client: SupabaseClient<Database>,
): Promise<CurriculumCatalog> {
  const db = quizDb(client);
  const [cocs, modules, outcomes, topics, revisions] = await Promise.all([
    client.from("coc_modules").select("id,coc_code,title").order("order_index"),
    db
      .from("curriculum_modules")
      .select("id,coc_module_id,coc_code,code,title,sequence_order")
      .order("coc_code")
      .order("sequence_order"),
    db
      .from("learning_outcomes")
      .select("id,module_id,code,statement,sequence_order")
      .order("sequence_order"),
    db
      .from("curriculum_topics")
      .select("id,module_id,sequence_order,archived_at")
      .is("archived_at", null),
    db
      .from("curriculum_topic_revisions")
      .select("topic_id,revision_number,title,summary,body_markdown,status")
      .eq("status", "published")
      .order("revision_number", { ascending: false }),
  ]);
  if (cocs.error || modules.error || outcomes.error || topics.error || revisions.error) {
    throw new Error("The curriculum catalog could not be loaded.");
  }
  const latest = new Map<string, TopicRevisionRow>();
  for (const revision of (revisions.data ?? []) as TopicRevisionRow[]) {
    if (!latest.has(revision.topic_id)) latest.set(revision.topic_id, revision);
  }
  return {
    cocs: (cocs.data ?? []).map((coc) => ({
      id: coc.id,
      code: coc.coc_code,
      title: coc.title,
    })),
    modules: ((modules.data ?? []) as CurriculumModuleRow[]).map((module) => ({
      id: module.id,
      cocId: module.coc_module_id,
      cocCode: module.coc_code,
      code: module.code,
      title: module.title,
      sequenceOrder: module.sequence_order,
    })),
    outcomes: ((outcomes.data ?? []) as LearningOutcomeRow[]).map((outcome) => ({
      id: outcome.id,
      moduleId: outcome.module_id,
      code: outcome.code,
      statement: outcome.statement,
      sequenceOrder: outcome.sequence_order,
    })),
    topics: ((topics.data ?? []) as CurriculumTopicRow[]).flatMap((topic) => {
      const revision = latest.get(topic.id);
      return revision
        ? [
            {
              id: topic.id,
              moduleId: topic.module_id,
              title: revision.title,
              summary: revision.summary,
              sequenceOrder: topic.sequence_order,
            },
          ]
        : [];
    }),
  };
}

/**
 * Instructor results read path: attempts whose time limit or deadline passed
 * are finalised (exactly once, at their expiry) before results are read.
 * Never blocks the page; a failure only means the next read processes them.
 */
export async function processExpiredQuizAttempts(actorId: string, quizId: string) {
  try {
    const admin = createAdminSupabaseClient(15000) as unknown as SupabaseClient;
    await admin.rpc("process_expired_quiz_attempts", {
      p_actor: actorId,
      p_quiz_id: quizId,
    });
  } catch {
    /* Learner RPCs and deadline changes also finalise expired attempts. */
  }
}
