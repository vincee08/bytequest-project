import type { Database, Json } from '@/types/database.generated';
import type { SupabaseClient } from '@supabase/supabase-js';

/** Feature-local types for the curriculum tables (the generated types predate them). */
export type ContentStatus =
  | 'draft' | 'submitted' | 'needs_revision' | 'evaluated' | 'finalized'
  | 'approved' | 'published' | 'unpublished' | 'archived';

export type CurriculumModule = {
  id: string; coc_module_id: string; coc_code: string; code: string; title: string;
  element_title: string | null; sequence_order: number; source_reference: string; created_at: string;
};
export type LearningOutcome = {
  id: string; module_id: string; code: string; statement: string; sequence_order: number;
  source_reference: string; created_at: string;
};
export type CurriculumTopic = {
  id: string; module_id: string; sequence_order: number; created_by: string | null;
  created_at: string; archived_at: string | null;
};
export type TopicRevision = {
  id: string; topic_id: string; revision_number: number; title: string; summary: string | null;
  body_markdown: string; outcome_ids: string[]; status: ContentStatus; author_id: string | null;
  submitted_at: string | null; evaluated_by: string | null; evaluated_at: string | null;
  evaluation_notes: string | null; finalized_by: string | null; finalized_at: string | null;
  approved_by: string | null; approved_at: string | null; published_by: string | null;
  published_at: string | null; unpublished_by: string | null; unpublished_at: string | null;
  created_at: string; updated_at: string;
};
export type PublicationEvent = {
  id: number; entity_type: 'topic'; entity_id: string; revision_id: string | null;
  from_status: ContentStatus | null; to_status: ContentStatus; actor_id: string | null;
  note: string | null; occurred_at: string;
};
export type MissionLink = { mission_code: string; module_id: string; pc_codes: string[]; sequence_order: number };

export type StaffCurriculumAction =
  | 'create_topic' | 'edit_revision' | 'submit' | 'evaluate' | 'finalize'
  | 'approve' | 'publish' | 'unpublish' | 'archive_topic';

/** Everything the /curriculum workspace needs, as returned by GET /api/curriculum. */
export type CurriculumWorkspace = {
  role: 'admin' | 'instructor';
  actorId: string;
  cocs: { coc_code: string; title: string; order_index: number }[];
  modules: CurriculumModule[];
  outcomes: LearningOutcome[];
  topics: CurriculumTopic[];
  revisions: TopicRevision[];
  events: PublicationEvent[];
  missions: (MissionLink & { title: string })[];
  people: Record<string, string>;
};

type Table<T> = { Row: T; Insert: Partial<T>; Update: Partial<T>; Relationships: [] };
export type CurriculumDatabase = Omit<Database, 'public'> & {
  public: Omit<Database['public'], 'Tables' | 'Functions'> & {
    Tables: Database['public']['Tables'] & {
      curriculum_modules: Table<CurriculumModule>;
      learning_outcomes: Table<LearningOutcome>;
      curriculum_topics: Table<CurriculumTopic>;
      curriculum_topic_revisions: Table<TopicRevision>;
      content_publication_events: Table<PublicationEvent>;
      mission_curriculum_links: Table<MissionLink>;
    };
    Functions: Database['public']['Functions'] & {
      manage_curriculum_content: { Args: { p_actor: string; p_action: string; p_payload: Json }; Returns: Json };
      get_learner_curriculum: { Args: Record<string, never>; Returns: Json };
    };
  };
};

/** Re-types an authenticated or service Supabase client for the curriculum schema. */
export function curriculumClient(client: object) {
  return client as unknown as SupabaseClient<CurriculumDatabase>;
}
