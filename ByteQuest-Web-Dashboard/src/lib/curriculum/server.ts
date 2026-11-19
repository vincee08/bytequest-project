import 'server-only';
import { curriculumClient, type CurriculumWorkspace } from './types';

type Actor = { id: string; role: string; client: object; service: object };

/**
 * Loads the staff curriculum workspace with the caller's own RLS (staff can
 * read every module, outcome, topic, revision and publication event). Only
 * the display names of the people in the history are read with the service
 * client, because instructors cannot read other staff profiles directly.
 */
export async function loadCurriculumWorkspace(actor: Actor): Promise<CurriculumWorkspace> {
  if (actor.role !== 'admin' && actor.role !== 'instructor') throw new Error('STAFF_REQUIRED');
  const db = curriculumClient(actor.client);
  const [cocs, modules, outcomes, topics, revisions, events, links, missions] = await Promise.all([
    db.from('coc_modules').select('coc_code,title,order_index').eq('status', 'published').order('order_index'),
    db.from('curriculum_modules').select('*').order('coc_code').order('sequence_order'),
    db.from('learning_outcomes').select('*').order('sequence_order'),
    db.from('curriculum_topics').select('*').order('sequence_order'),
    db.from('curriculum_topic_revisions').select('*').order('revision_number'),
    db.from('content_publication_events').select('*').order('occurred_at', { ascending: false }).order('id', { ascending: false }).limit(1000),
    db.from('mission_curriculum_links').select('*').order('sequence_order'),
    db.from('missions').select('mission_code,title'),
  ]);
  const failed = [cocs, modules, outcomes, topics, revisions, events, links, missions].find((result) => result.error);
  if (failed?.error) throw new Error('CURRICULUM_LOAD_FAILED');

  const titleByMission = new Map((missions.data ?? []).map((mission) => [mission.mission_code, mission.title]));
  const ids = new Set<string>();
  for (const topic of topics.data ?? []) if (topic.created_by) ids.add(topic.created_by);
  for (const revision of revisions.data ?? []) {
    for (const id of [revision.author_id, revision.evaluated_by, revision.finalized_by, revision.approved_by, revision.published_by, revision.unpublished_by]) {
      if (id) ids.add(id);
    }
  }
  for (const event of events.data ?? []) if (event.actor_id) ids.add(event.actor_id);
  const people: Record<string, string> = {};
  if (ids.size) {
    const { data, error } = await curriculumClient(actor.service)
      .from('profiles').select('user_id,full_name,email').in('user_id', [...ids]);
    if (!error) for (const person of data ?? []) people[person.user_id] = person.full_name?.trim() || person.email || 'Staff member';
  }

  return {
    role: actor.role === 'admin' ? 'admin' : 'instructor',
    actorId: actor.id,
    cocs: cocs.data ?? [],
    modules: modules.data ?? [],
    outcomes: outcomes.data ?? [],
    topics: topics.data ?? [],
    revisions: revisions.data ?? [],
    events: events.data ?? [],
    missions: (links.data ?? []).map((link) => ({ ...link, title: titleByMission.get(link.mission_code) ?? link.mission_code })),
    people,
  };
}
