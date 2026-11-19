-- Re-defense WS4: scenario-based essay questions scored by the instructor
-- against a rubric. A new enum value cannot be used in the transaction that
-- adds it, so it is committed on its own before the authoring migration.
begin;
alter type public.quiz_item_type add value if not exists 'scenario_essay';
commit;
