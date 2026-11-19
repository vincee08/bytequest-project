export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      achievements: {
        Row: {
          achievement_code: string
          condition_type: Database["public"]["Enums"]["condition_type"]
          condition_value: Json
          created_at: string
          description: string | null
          icon: string | null
          icon_url: string | null
          id: string
          rule: Json | null
          sort_order: number
          title: string
          updated_at: string
        }
        Insert: {
          achievement_code: string
          condition_type: Database["public"]["Enums"]["condition_type"]
          condition_value?: Json
          created_at?: string
          description?: string | null
          icon?: string | null
          icon_url?: string | null
          id?: string
          rule?: Json | null
          sort_order?: number
          title: string
          updated_at?: string
        }
        Update: {
          achievement_code?: string
          condition_type?: Database["public"]["Enums"]["condition_type"]
          condition_value?: Json
          created_at?: string
          description?: string | null
          icon?: string | null
          icon_url?: string | null
          id?: string
          rule?: Json | null
          sort_order?: number
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      activity_curriculum_links: {
        Row: {
          activity_version_id: string
          delivery_kind: string
          linked_at: string
          module_id: string
        }
        Insert: {
          activity_version_id: string
          delivery_kind: string
          linked_at?: string
          module_id: string
        }
        Update: {
          activity_version_id?: string
          delivery_kind?: string
          linked_at?: string
          module_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "activity_curriculum_links_activity_version_id_fkey"
            columns: ["activity_version_id"]
            isOneToOne: true
            referencedRelation: "activity_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_curriculum_links_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      activity_logs: {
        Row: {
          action: string
          created_at: string
          description: string | null
          entity_id: string | null
          entity_type: string | null
          id: string
          metadata: Json
          user_id: string | null
        }
        Insert: {
          action: string
          created_at?: string
          description?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          user_id?: string | null
        }
        Update: {
          action?: string
          created_at?: string
          description?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          metadata?: Json
          user_id?: string | null
        }
        Relationships: []
      }
      activity_versions: {
        Row: {
          created_at: string
          created_by: string
          delivery_mode: Database["public"]["Enums"]["activity_delivery_mode"]
          evaluator_config: Json
          id: string
          instructions: string | null
          learner_payload: Json
          mission_id: string
          module_version_id: string
          published_at: string | null
          published_by: string | null
          retired_at: string | null
          status: Database["public"]["Enums"]["content_version_status"]
          title: string
          updated_at: string
          version_number: number
        }
        Insert: {
          created_at?: string
          created_by: string
          delivery_mode?: Database["public"]["Enums"]["activity_delivery_mode"]
          evaluator_config?: Json
          id?: string
          instructions?: string | null
          learner_payload?: Json
          mission_id: string
          module_version_id: string
          published_at?: string | null
          published_by?: string | null
          retired_at?: string | null
          status?: Database["public"]["Enums"]["content_version_status"]
          title: string
          updated_at?: string
          version_number: number
        }
        Update: {
          created_at?: string
          created_by?: string
          delivery_mode?: Database["public"]["Enums"]["activity_delivery_mode"]
          evaluator_config?: Json
          id?: string
          instructions?: string | null
          learner_payload?: Json
          mission_id?: string
          module_version_id?: string
          published_at?: string | null
          published_by?: string | null
          retired_at?: string | null
          status?: Database["public"]["Enums"]["content_version_status"]
          title?: string
          updated_at?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "activity_versions_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "activity_versions_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
          {
            foreignKeyName: "activity_versions_module_version_id_fkey"
            columns: ["module_version_id"]
            isOneToOne: false
            referencedRelation: "module_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      ai_quiz_generations: {
        Row: {
          completed_at: string | null
          failure_code: string | null
          generated_count: number
          id: string
          input_context: Json
          instructor_id: string
          model: string
          provider: string
          quiz_version_id: string
          requested_at: string
          requested_count: number
          status: Database["public"]["Enums"]["ai_generation_status"]
        }
        Insert: {
          completed_at?: string | null
          failure_code?: string | null
          generated_count?: number
          id?: string
          input_context?: Json
          instructor_id: string
          model: string
          provider?: string
          quiz_version_id: string
          requested_at?: string
          requested_count: number
          status?: Database["public"]["Enums"]["ai_generation_status"]
        }
        Update: {
          completed_at?: string | null
          failure_code?: string | null
          generated_count?: number
          id?: string
          input_context?: Json
          instructor_id?: string
          model?: string
          provider?: string
          quiz_version_id?: string
          requested_at?: string
          requested_count?: number
          status?: Database["public"]["Enums"]["ai_generation_status"]
        }
        Relationships: [
          {
            foreignKeyName: "ai_quiz_generations_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      app_release_config: {
        Row: {
          key: string
          updated_at: string
          value: string
        }
        Insert: {
          key: string
          updated_at?: string
          value: string
        }
        Update: {
          key?: string
          updated_at?: string
          value?: string
        }
        Relationships: []
      }
      assessment_criteria: {
        Row: {
          created_at: string
          criteria_name: string
          description: string | null
          id: string
          max_score: number
          mission_id: string
          order_index: number
          updated_at: string
          weight: number
        }
        Insert: {
          created_at?: string
          criteria_name: string
          description?: string | null
          id?: string
          max_score?: number
          mission_id: string
          order_index?: number
          updated_at?: string
          weight?: number
        }
        Update: {
          created_at?: string
          criteria_name?: string
          description?: string | null
          id?: string
          max_score?: number
          mission_id?: string
          order_index?: number
          updated_at?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "assessment_criteria_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assessment_criteria_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      assignments: {
        Row: {
          activity_version_id: string
          assigned_by: string
          assignment_type: Database["public"]["Enums"]["assignment_type"]
          attempts_allowed: number | null
          available_at: string | null
          class_id: string
          close_reason: string | null
          closed_at: string | null
          created_at: string
          due_at: string | null
          id: string
          instructions: string | null
          prerequisite_assignment_id: string | null
          retry_after_seconds: number | null
          retry_enabled: boolean
          rubric_version_id: string | null
          status: Database["public"]["Enums"]["assignment_status"]
          title: string
          updated_at: string
        }
        Insert: {
          activity_version_id: string
          assigned_by: string
          assignment_type?: Database["public"]["Enums"]["assignment_type"]
          attempts_allowed?: number | null
          available_at?: string | null
          class_id: string
          close_reason?: string | null
          closed_at?: string | null
          created_at?: string
          due_at?: string | null
          id?: string
          instructions?: string | null
          prerequisite_assignment_id?: string | null
          retry_after_seconds?: number | null
          retry_enabled?: boolean
          rubric_version_id?: string | null
          status?: Database["public"]["Enums"]["assignment_status"]
          title: string
          updated_at?: string
        }
        Update: {
          activity_version_id?: string
          assigned_by?: string
          assignment_type?: Database["public"]["Enums"]["assignment_type"]
          attempts_allowed?: number | null
          available_at?: string | null
          class_id?: string
          close_reason?: string | null
          closed_at?: string | null
          created_at?: string
          due_at?: string | null
          id?: string
          instructions?: string | null
          prerequisite_assignment_id?: string | null
          retry_after_seconds?: number | null
          retry_enabled?: boolean
          rubric_version_id?: string | null
          status?: Database["public"]["Enums"]["assignment_status"]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "assignments_activity_version_id_fkey"
            columns: ["activity_version_id"]
            isOneToOne: false
            referencedRelation: "activity_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_prerequisite_assignment_id_fkey"
            columns: ["prerequisite_assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assignments_rubric_version_id_fkey"
            columns: ["rubric_version_id"]
            isOneToOne: false
            referencedRelation: "rubric_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      attempt_actions: {
        Row: {
          action_type: string
          attempt_id: string
          client_occurred_at: string
          id: string
          recorded_at: string
          sequence_number: number
          target: string | null
          value: Json
        }
        Insert: {
          action_type: string
          attempt_id: string
          client_occurred_at: string
          id?: string
          recorded_at?: string
          sequence_number: number
          target?: string | null
          value?: Json
        }
        Update: {
          action_type?: string
          attempt_id?: string
          client_occurred_at?: string
          id?: string
          recorded_at?: string
          sequence_number?: number
          target?: string | null
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "attempt_actions_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: false
            referencedRelation: "attempts"
            referencedColumns: ["id"]
          },
        ]
      }
      attempt_evaluation_records: {
        Row: {
          adjustment_revision_id: string | null
          attempt_id: string
          criterion_overrides: Json
          note: string | null
          outcome: Database["public"]["Enums"]["evaluation_outcome"]
          recorded_at: string
          recorded_by: string
        }
        Insert: {
          adjustment_revision_id?: string | null
          attempt_id: string
          criterion_overrides?: Json
          note?: string | null
          outcome: Database["public"]["Enums"]["evaluation_outcome"]
          recorded_at?: string
          recorded_by: string
        }
        Update: {
          adjustment_revision_id?: string | null
          attempt_id?: string
          criterion_overrides?: Json
          note?: string | null
          outcome?: Database["public"]["Enums"]["evaluation_outcome"]
          recorded_at?: string
          recorded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "attempt_evaluation_records_adjustment_revision_id_fkey"
            columns: ["adjustment_revision_id"]
            isOneToOne: false
            referencedRelation: "score_revisions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attempt_evaluation_records_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: true
            referencedRelation: "attempts"
            referencedColumns: ["id"]
          },
        ]
      }
      attempts: {
        Row: {
          activity_version_id: string
          assignment_id: string
          class_id: string
          client_start_key: string
          created_at: string
          elapsed_time_seconds: number | null
          evaluated_at: string | null
          finalized_at: string | null
          id: string
          learner_id: string
          legacy_mission_result_id: string | null
          released_at: string | null
          rubric_version_id: string | null
          started_at: string
          status: Database["public"]["Enums"]["attempt_status"]
          submission_key: string | null
          submitted_at: string | null
          tesda_source_id: string | null
          updated_at: string
        }
        Insert: {
          activity_version_id: string
          assignment_id: string
          class_id: string
          client_start_key: string
          created_at?: string
          elapsed_time_seconds?: number | null
          evaluated_at?: string | null
          finalized_at?: string | null
          id?: string
          learner_id: string
          legacy_mission_result_id?: string | null
          released_at?: string | null
          rubric_version_id?: string | null
          started_at?: string
          status?: Database["public"]["Enums"]["attempt_status"]
          submission_key?: string | null
          submitted_at?: string | null
          tesda_source_id?: string | null
          updated_at?: string
        }
        Update: {
          activity_version_id?: string
          assignment_id?: string
          class_id?: string
          client_start_key?: string
          created_at?: string
          elapsed_time_seconds?: number | null
          evaluated_at?: string | null
          finalized_at?: string | null
          id?: string
          learner_id?: string
          legacy_mission_result_id?: string | null
          released_at?: string | null
          rubric_version_id?: string | null
          started_at?: string
          status?: Database["public"]["Enums"]["attempt_status"]
          submission_key?: string | null
          submitted_at?: string | null
          tesda_source_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "attempts_activity_version_id_fkey"
            columns: ["activity_version_id"]
            isOneToOne: false
            referencedRelation: "activity_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attempts_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attempts_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attempts_legacy_mission_result_id_fkey"
            columns: ["legacy_mission_result_id"]
            isOneToOne: true
            referencedRelation: "mission_results"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attempts_rubric_version_id_fkey"
            columns: ["rubric_version_id"]
            isOneToOne: false
            referencedRelation: "rubric_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attempts_tesda_source_id_fkey"
            columns: ["tesda_source_id"]
            isOneToOne: false
            referencedRelation: "tesda_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_events: {
        Row: {
          action: string
          actor_id: string | null
          actor_role: Database["public"]["Enums"]["user_role"] | null
          created_at: string
          id: string
          metadata: Json
          new_value: Json | null
          old_value: Json | null
          outcome: string
          reason: string | null
          target_id: string | null
          target_type: string
        }
        Insert: {
          action: string
          actor_id?: string | null
          actor_role?: Database["public"]["Enums"]["user_role"] | null
          created_at?: string
          id?: string
          metadata?: Json
          new_value?: Json | null
          old_value?: Json | null
          outcome?: string
          reason?: string | null
          target_id?: string | null
          target_type: string
        }
        Update: {
          action?: string
          actor_id?: string | null
          actor_role?: Database["public"]["Enums"]["user_role"] | null
          created_at?: string
          id?: string
          metadata?: Json
          new_value?: Json | null
          old_value?: Json | null
          outcome?: string
          reason?: string | null
          target_id?: string | null
          target_type?: string
        }
        Relationships: []
      }
      badges: {
        Row: {
          badge_code: string
          condition_type: Database["public"]["Enums"]["condition_type"]
          condition_value: Json
          created_at: string
          description: string | null
          icon_url: string | null
          id: string
          title: string
          updated_at: string
          xp_reward: number
        }
        Insert: {
          badge_code: string
          condition_type: Database["public"]["Enums"]["condition_type"]
          condition_value?: Json
          created_at?: string
          description?: string | null
          icon_url?: string | null
          id?: string
          title: string
          updated_at?: string
          xp_reward?: number
        }
        Update: {
          badge_code?: string
          condition_type?: Database["public"]["Enums"]["condition_type"]
          condition_value?: Json
          created_at?: string
          description?: string | null
          icon_url?: string | null
          id?: string
          title?: string
          updated_at?: string
          xp_reward?: number
        }
        Relationships: []
      }
      class_memberships: {
        Row: {
          class_id: string
          created_at: string
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          enrolled_at: string
          enrolled_by: string
          id: string
          learner_id: string
          status: Database["public"]["Enums"]["membership_status"]
          updated_at: string
        }
        Insert: {
          class_id: string
          created_at?: string
          deactivated_at?: string | null
          deactivated_by?: string | null
          deactivation_reason?: string | null
          enrolled_at?: string
          enrolled_by: string
          id?: string
          learner_id: string
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
        }
        Update: {
          class_id?: string
          created_at?: string
          deactivated_at?: string | null
          deactivated_by?: string | null
          deactivation_reason?: string | null
          enrolled_at?: string
          enrolled_by?: string
          id?: string
          learner_id?: string
          status?: Database["public"]["Enums"]["membership_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "class_memberships_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      class_roster_entries: {
        Row: {
          claimed_at: string | null
          claimed_user_id: string | null
          class_id: string
          course_section: string | null
          created_at: string
          created_by: string
          email_normalized: string
          first_name: string
          id: string
          import_batch_id: string | null
          last_name: string
          status: string
          student_id: string | null
          updated_at: string
        }
        Insert: {
          claimed_at?: string | null
          claimed_user_id?: string | null
          class_id: string
          course_section?: string | null
          created_at?: string
          created_by: string
          email_normalized: string
          first_name: string
          id?: string
          import_batch_id?: string | null
          last_name: string
          status?: string
          student_id?: string | null
          updated_at?: string
        }
        Update: {
          claimed_at?: string | null
          claimed_user_id?: string | null
          class_id?: string
          course_section?: string | null
          created_at?: string
          created_by?: string
          email_normalized?: string
          first_name?: string
          id?: string
          import_batch_id?: string | null
          last_name?: string
          status?: string
          student_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "class_roster_entries_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "class_roster_entries_import_batch_id_fkey"
            columns: ["import_batch_id"]
            isOneToOne: false
            referencedRelation: "roster_import_batches"
            referencedColumns: ["id"]
          },
        ]
      }
      classes: {
        Row: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          class_code: string | null
          created_at: string
          created_by: string
          id: string
          instructor_id: string
          status: Database["public"]["Enums"]["class_status"]
          title: string
          updated_at: string
        }
        Insert: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          class_code?: string | null
          created_at?: string
          created_by: string
          id?: string
          instructor_id: string
          status?: Database["public"]["Enums"]["class_status"]
          title: string
          updated_at?: string
        }
        Update: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          class_code?: string | null
          created_at?: string
          created_by?: string
          id?: string
          instructor_id?: string
          status?: Database["public"]["Enums"]["class_status"]
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      coc_bypasses: {
        Row: {
          class_id: string
          created_at: string
          granted_at: string
          id: string
          instructor_id: string
          learner_id: string
          module_version_id: string
          reason: string
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          scope: Json
        }
        Insert: {
          class_id: string
          created_at?: string
          granted_at?: string
          id?: string
          instructor_id: string
          learner_id: string
          module_version_id: string
          reason: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          scope?: Json
        }
        Update: {
          class_id?: string
          created_at?: string
          granted_at?: string
          id?: string
          instructor_id?: string
          learner_id?: string
          module_version_id?: string
          reason?: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          scope?: Json
        }
        Relationships: [
          {
            foreignKeyName: "coc_bypasses_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coc_bypasses_module_version_id_fkey"
            columns: ["module_version_id"]
            isOneToOne: false
            referencedRelation: "module_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      coc_modules: {
        Row: {
          coc_code: string
          color_hex: string | null
          competency_area: string | null
          competency_id: string | null
          created_at: string
          description: string | null
          difficulty: Database["public"]["Enums"]["difficulty_level"]
          icon_url: string | null
          id: string
          module_name: string
          order_index: number
          status: Database["public"]["Enums"]["mission_status"]
          title: string
          total_missions: number
          updated_at: string
          xp_reward: number
        }
        Insert: {
          coc_code: string
          color_hex?: string | null
          competency_area?: string | null
          competency_id?: string | null
          created_at?: string
          description?: string | null
          difficulty?: Database["public"]["Enums"]["difficulty_level"]
          icon_url?: string | null
          id?: string
          module_name: string
          order_index?: number
          status?: Database["public"]["Enums"]["mission_status"]
          title: string
          total_missions?: number
          updated_at?: string
          xp_reward?: number
        }
        Update: {
          coc_code?: string
          color_hex?: string | null
          competency_area?: string | null
          competency_id?: string | null
          created_at?: string
          description?: string | null
          difficulty?: Database["public"]["Enums"]["difficulty_level"]
          icon_url?: string | null
          id?: string
          module_name?: string
          order_index?: number
          status?: Database["public"]["Enums"]["mission_status"]
          title?: string
          total_missions?: number
          updated_at?: string
          xp_reward?: number
        }
        Relationships: [
          {
            foreignKeyName: "coc_modules_competency_id_fkey"
            columns: ["competency_id"]
            isOneToOne: false
            referencedRelation: "competencies"
            referencedColumns: ["id"]
          },
        ]
      }
      competencies: {
        Row: {
          competency_code: string
          created_at: string
          description: string | null
          id: string
          name: string
          order_index: number
          source_trace: string | null
          tesda_source_id: string | null
          updated_at: string
        }
        Insert: {
          competency_code: string
          created_at?: string
          description?: string | null
          id?: string
          name: string
          order_index?: number
          source_trace?: string | null
          tesda_source_id?: string | null
          updated_at?: string
        }
        Update: {
          competency_code?: string
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          order_index?: number
          source_trace?: string | null
          tesda_source_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "competencies_tesda_source_id_fkey"
            columns: ["tesda_source_id"]
            isOneToOne: false
            referencedRelation: "tesda_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      content_publication_events: {
        Row: {
          actor_id: string | null
          entity_id: string
          entity_type: string
          from_status:
            | Database["public"]["Enums"]["content_publication_status"]
            | null
          id: number
          note: string | null
          occurred_at: string
          revision_id: string | null
          to_status: Database["public"]["Enums"]["content_publication_status"]
        }
        Insert: {
          actor_id?: string | null
          entity_id: string
          entity_type: string
          from_status?:
            | Database["public"]["Enums"]["content_publication_status"]
            | null
          id?: never
          note?: string | null
          occurred_at?: string
          revision_id?: string | null
          to_status: Database["public"]["Enums"]["content_publication_status"]
        }
        Update: {
          actor_id?: string | null
          entity_id?: string
          entity_type?: string
          from_status?:
            | Database["public"]["Enums"]["content_publication_status"]
            | null
          id?: never
          note?: string | null
          occurred_at?: string
          revision_id?: string | null
          to_status?: Database["public"]["Enums"]["content_publication_status"]
        }
        Relationships: [
          {
            foreignKeyName: "content_publication_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "content_publication_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
        ]
      }
      criterion_results: {
        Row: {
          attempt_id: string
          evaluated_at: string
          evaluation_run_id: string
          expected_rule: Json
          id: string
          observation: Database["public"]["Enums"]["criterion_observation"]
          observed_evidence: Json
          remarks: string | null
          rubric_criterion_id: string
          score_value: number | null
        }
        Insert: {
          attempt_id: string
          evaluated_at?: string
          evaluation_run_id: string
          expected_rule: Json
          id?: string
          observation: Database["public"]["Enums"]["criterion_observation"]
          observed_evidence: Json
          remarks?: string | null
          rubric_criterion_id: string
          score_value?: number | null
        }
        Update: {
          attempt_id?: string
          evaluated_at?: string
          evaluation_run_id?: string
          expected_rule?: Json
          id?: string
          observation?: Database["public"]["Enums"]["criterion_observation"]
          observed_evidence?: Json
          remarks?: string | null
          rubric_criterion_id?: string
          score_value?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "criterion_results_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: false
            referencedRelation: "attempts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "criterion_results_rubric_criterion_id_fkey"
            columns: ["rubric_criterion_id"]
            isOneToOne: false
            referencedRelation: "rubric_criteria"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_modules: {
        Row: {
          coc_code: string
          coc_module_id: string
          code: string
          created_at: string
          element_title: string | null
          id: string
          sequence_order: number
          source_reference: string
          title: string
        }
        Insert: {
          coc_code: string
          coc_module_id: string
          code: string
          created_at?: string
          element_title?: string | null
          id?: string
          sequence_order: number
          source_reference: string
          title: string
        }
        Update: {
          coc_code?: string
          coc_module_id?: string
          code?: string
          created_at?: string
          element_title?: string | null
          id?: string
          sequence_order?: number
          source_reference?: string
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_modules_coc_module_id_fkey"
            columns: ["coc_module_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      curriculum_topic_revisions: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          author_id: string | null
          body_markdown: string
          created_at: string
          evaluated_at: string | null
          evaluated_by: string | null
          evaluation_notes: string | null
          finalized_at: string | null
          finalized_by: string | null
          id: string
          outcome_ids: string[]
          published_at: string | null
          published_by: string | null
          revision_number: number
          status: Database["public"]["Enums"]["content_publication_status"]
          submitted_at: string | null
          summary: string | null
          title: string
          topic_id: string
          unpublished_at: string | null
          unpublished_by: string | null
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          author_id?: string | null
          body_markdown?: string
          created_at?: string
          evaluated_at?: string | null
          evaluated_by?: string | null
          evaluation_notes?: string | null
          finalized_at?: string | null
          finalized_by?: string | null
          id?: string
          outcome_ids?: string[]
          published_at?: string | null
          published_by?: string | null
          revision_number: number
          status?: Database["public"]["Enums"]["content_publication_status"]
          submitted_at?: string | null
          summary?: string | null
          title: string
          topic_id: string
          unpublished_at?: string | null
          unpublished_by?: string | null
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          author_id?: string | null
          body_markdown?: string
          created_at?: string
          evaluated_at?: string | null
          evaluated_by?: string | null
          evaluation_notes?: string | null
          finalized_at?: string | null
          finalized_by?: string | null
          id?: string
          outcome_ids?: string[]
          published_at?: string | null
          published_by?: string | null
          revision_number?: number
          status?: Database["public"]["Enums"]["content_publication_status"]
          submitted_at?: string | null
          summary?: string | null
          title?: string
          topic_id?: string
          unpublished_at?: string | null
          unpublished_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_topic_revisions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_evaluated_by_fkey"
            columns: ["evaluated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_evaluated_by_fkey"
            columns: ["evaluated_by"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_finalized_by_fkey"
            columns: ["finalized_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_finalized_by_fkey"
            columns: ["finalized_by"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_published_by_fkey"
            columns: ["published_by"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "curriculum_topics"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_unpublished_by_fkey"
            columns: ["unpublished_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topic_revisions_unpublished_by_fkey"
            columns: ["unpublished_by"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
        ]
      }
      curriculum_topics: {
        Row: {
          archived_at: string | null
          created_at: string
          created_by: string | null
          id: string
          module_id: string
          sequence_order: number
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          module_id: string
          sequence_order?: number
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          module_id?: string
          sequence_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "curriculum_topics_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topics_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "curriculum_topics_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      file_upload_intents: {
        Row: {
          actor_id: string
          bucket: string
          created_at: string
          expires_at: string
          id: string
          lease_id: string | null
          lease_until: string | null
          object_path: string
          purpose: string
          result: Json | null
          spec: Json
          state: string
          target_id: string
          updated_at: string
        }
        Insert: {
          actor_id: string
          bucket: string
          created_at?: string
          expires_at: string
          id: string
          lease_id?: string | null
          lease_until?: string | null
          object_path: string
          purpose: string
          result?: Json | null
          spec: Json
          state?: string
          target_id: string
          updated_at?: string
        }
        Update: {
          actor_id?: string
          bucket?: string
          created_at?: string
          expires_at?: string
          id?: string
          lease_id?: string | null
          lease_until?: string | null
          object_path?: string
          purpose?: string
          result?: Json | null
          spec?: Json
          state?: string
          target_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      gamification_events: {
        Row: {
          created_at: string
          created_by: string | null
          event_type: string
          id: string
          idempotency_key: string
          learner_id: string
          metadata: Json
          points_delta: number
          source_id: string | null
          source_type: string
          xp_delta: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          event_type: string
          id?: string
          idempotency_key: string
          learner_id: string
          metadata?: Json
          points_delta?: number
          source_id?: string | null
          source_type: string
          xp_delta?: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          event_type?: string
          id?: string
          idempotency_key?: string
          learner_id?: string
          metadata?: Json
          points_delta?: number
          source_id?: string | null
          source_type?: string
          xp_delta?: number
        }
        Relationships: []
      }
      gamification_leaderboard_entries: {
        Row: {
          display_name: string
          is_active_learner: boolean
          learner_id: string
          points: number
          show_on_leaderboard: boolean
          updated_at: string
        }
        Insert: {
          display_name?: string
          is_active_learner?: boolean
          learner_id: string
          points?: number
          show_on_leaderboard?: boolean
          updated_at?: string
        }
        Update: {
          display_name?: string
          is_active_learner?: boolean
          learner_id?: string
          points?: number
          show_on_leaderboard?: boolean
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "gamification_leaderboard_entries_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "gamification_leaderboard_entries_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: true
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
        ]
      }
      gamification_levels: {
        Row: {
          level: number
          min_points: number
          title: string
        }
        Insert: {
          level: number
          min_points: number
          title: string
        }
        Update: {
          level?: number
          min_points?: number
          title?: string
        }
        Relationships: []
      }
      gamification_point_rules: {
        Row: {
          active: boolean
          created_at: string
          event_type: string
          label: string
          points: number
          sort_order: number
          updated_at: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          event_type: string
          label: string
          points: number
          sort_order?: number
          updated_at?: string
        }
        Update: {
          active?: boolean
          created_at?: string
          event_type?: string
          label?: string
          points?: number
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      homework_assignments: {
        Row: {
          class_id: string
          coc_module_id: string | null
          created_at: string
          criteria: Json
          deadline_at: string | null
          id: string
          instructions: string
          instructor_id: string
          learning_objectives: string[]
          max_score: number
          mission_code: string | null
          module_id: string | null
          published_at: string | null
          revision: number
          status: string
          submission_requirements: string | null
          title: string
          updated_at: string
        }
        Insert: {
          class_id: string
          coc_module_id?: string | null
          created_at?: string
          criteria?: Json
          deadline_at?: string | null
          id?: string
          instructions: string
          instructor_id: string
          learning_objectives?: string[]
          max_score?: number
          mission_code?: string | null
          module_id?: string | null
          published_at?: string | null
          revision?: number
          status?: string
          submission_requirements?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          class_id?: string
          coc_module_id?: string | null
          created_at?: string
          criteria?: Json
          deadline_at?: string | null
          id?: string
          instructions?: string
          instructor_id?: string
          learning_objectives?: string[]
          max_score?: number
          mission_code?: string | null
          module_id?: string | null
          published_at?: string | null
          revision?: number
          status?: string
          submission_requirements?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "homework_assignments_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "homework_assignments_coc_module_id_fkey"
            columns: ["coc_module_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "homework_assignments_mission_code_fkey"
            columns: ["mission_code"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["mission_code"]
          },
          {
            foreignKeyName: "homework_assignments_mission_code_fkey"
            columns: ["mission_code"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_code"]
          },
          {
            foreignKeyName: "homework_assignments_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      homework_files: {
        Row: {
          assignment_id: string
          created_at: string
          filename: string
          id: string
          kind: string
          mime_type: string
          object_path: string
          owner_id: string
          size_bytes: number
          submission_id: string | null
        }
        Insert: {
          assignment_id: string
          created_at?: string
          filename: string
          id: string
          kind: string
          mime_type: string
          object_path: string
          owner_id: string
          size_bytes: number
          submission_id?: string | null
        }
        Update: {
          assignment_id?: string
          created_at?: string
          filename?: string
          id?: string
          kind?: string
          mime_type?: string
          object_path?: string
          owner_id?: string
          size_bytes?: number
          submission_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "homework_files_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "homework_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "homework_files_submission_id_fkey"
            columns: ["submission_id"]
            isOneToOne: false
            referencedRelation: "homework_submissions"
            referencedColumns: ["id"]
          },
        ]
      }
      homework_submissions: {
        Row: {
          answer: string
          assignment_id: string
          criterion_scores: Json | null
          deadline_revision: number
          effective_deadline_at: string | null
          feedback: string | null
          finalized_at: string | null
          finalized_by: string | null
          graded_at: string | null
          graded_by: string | null
          id: string
          lateness_seconds: number | null
          learner_id: string
          released_at: string | null
          released_by: string | null
          score: number | null
          status: string
          submitted_at: string
        }
        Insert: {
          answer?: string
          assignment_id: string
          criterion_scores?: Json | null
          deadline_revision: number
          effective_deadline_at?: string | null
          feedback?: string | null
          finalized_at?: string | null
          finalized_by?: string | null
          graded_at?: string | null
          graded_by?: string | null
          id?: string
          lateness_seconds?: number | null
          learner_id: string
          released_at?: string | null
          released_by?: string | null
          score?: number | null
          status?: string
          submitted_at: string
        }
        Update: {
          answer?: string
          assignment_id?: string
          criterion_scores?: Json | null
          deadline_revision?: number
          effective_deadline_at?: string | null
          feedback?: string | null
          finalized_at?: string | null
          finalized_by?: string | null
          graded_at?: string | null
          graded_by?: string | null
          id?: string
          lateness_seconds?: number | null
          learner_id?: string
          released_at?: string | null
          released_by?: string | null
          score?: number | null
          status?: string
          submitted_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "homework_submissions_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "homework_assignments"
            referencedColumns: ["id"]
          },
        ]
      }
      leaderboard_entries: {
        Row: {
          coc_id: string | null
          completed_at: string | null
          created_at: string
          id: string
          incorrect_attempts: number
          leaderboard_type: Database["public"]["Enums"]["leaderboard_type"]
          mission_id: string | null
          mission_result_id: string | null
          ranking_points: number
          score: number
          time_spent_seconds: number
          user_id: string
          xp: number
        }
        Insert: {
          coc_id?: string | null
          completed_at?: string | null
          created_at?: string
          id?: string
          incorrect_attempts?: number
          leaderboard_type?: Database["public"]["Enums"]["leaderboard_type"]
          mission_id?: string | null
          mission_result_id?: string | null
          ranking_points?: number
          score?: number
          time_spent_seconds?: number
          user_id: string
          xp?: number
        }
        Update: {
          coc_id?: string | null
          completed_at?: string | null
          created_at?: string
          id?: string
          incorrect_attempts?: number
          leaderboard_type?: Database["public"]["Enums"]["leaderboard_type"]
          mission_id?: string | null
          mission_result_id?: string | null
          ranking_points?: number
          score?: number
          time_spent_seconds?: number
          user_id?: string
          xp?: number
        }
        Relationships: [
          {
            foreignKeyName: "leaderboard_entries_coc_id_fkey"
            columns: ["coc_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leaderboard_entries_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leaderboard_entries_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
          {
            foreignKeyName: "leaderboard_entries_mission_result_id_fkey"
            columns: ["mission_result_id"]
            isOneToOne: false
            referencedRelation: "mission_results"
            referencedColumns: ["id"]
          },
        ]
      }
      learner_module_completions: {
        Row: {
          completed_at: string
          learner_id: string
          module_id: string
        }
        Insert: {
          completed_at?: string
          learner_id: string
          module_id: string
        }
        Update: {
          completed_at?: string
          learner_id?: string
          module_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "learner_module_completions_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "learner_module_completions_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "learner_module_completions_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      learner_module_unlocks: {
        Row: {
          learner_id: string
          module_id: string
          reason: string
          unlocked_at: string
        }
        Insert: {
          learner_id: string
          module_id: string
          reason: string
          unlocked_at?: string
        }
        Update: {
          learner_id?: string
          module_id?: string
          reason?: string
          unlocked_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "learner_module_unlocks_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "learner_module_unlocks_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "learner_module_unlocks_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      learner_point_events: {
        Row: {
          awarded_at: string
          detail: string | null
          event_type: string
          id: string
          learner_id: string
          points: number
          source_id: string
        }
        Insert: {
          awarded_at?: string
          detail?: string | null
          event_type: string
          id?: string
          learner_id: string
          points: number
          source_id: string
        }
        Update: {
          awarded_at?: string
          detail?: string | null
          event_type?: string
          id?: string
          learner_id?: string
          points?: number
          source_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "learner_point_events_event_type_fkey"
            columns: ["event_type"]
            isOneToOne: false
            referencedRelation: "gamification_point_rules"
            referencedColumns: ["event_type"]
          },
        ]
      }
      learner_progress: {
        Row: {
          attempts_count: number
          best_score: number
          coc_id: string
          completed_at: string | null
          completion_percentage: number
          created_at: string
          id: string
          last_activity_at: string | null
          latest_score: number
          mission_id: string
          started_at: string | null
          status: Database["public"]["Enums"]["progress_status"]
          total_time_spent_seconds: number
          unlocked_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          attempts_count?: number
          best_score?: number
          coc_id: string
          completed_at?: string | null
          completion_percentage?: number
          created_at?: string
          id?: string
          last_activity_at?: string | null
          latest_score?: number
          mission_id: string
          started_at?: string | null
          status?: Database["public"]["Enums"]["progress_status"]
          total_time_spent_seconds?: number
          unlocked_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          attempts_count?: number
          best_score?: number
          coc_id?: string
          completed_at?: string | null
          completion_percentage?: number
          created_at?: string
          id?: string
          last_activity_at?: string | null
          latest_score?: number
          mission_id?: string
          started_at?: string | null
          status?: Database["public"]["Enums"]["progress_status"]
          total_time_spent_seconds?: number
          unlocked_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "learner_progress_coc_id_fkey"
            columns: ["coc_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "learner_progress_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "learner_progress_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      learner_topic_progress: {
        Row: {
          completed_at: string
          learner_id: string
          revision_id: string | null
          topic_id: string
        }
        Insert: {
          completed_at?: string
          learner_id: string
          revision_id?: string | null
          topic_id: string
        }
        Update: {
          completed_at?: string
          learner_id?: string
          revision_id?: string | null
          topic_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "learner_topic_progress_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "learner_topic_progress_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "learner_topic_progress_revision_id_fkey"
            columns: ["revision_id"]
            isOneToOne: false
            referencedRelation: "curriculum_topic_revisions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "learner_topic_progress_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "curriculum_topics"
            referencedColumns: ["id"]
          },
        ]
      }
      learning_outcomes: {
        Row: {
          code: string
          created_at: string
          id: string
          module_id: string
          sequence_order: number
          source_reference: string
          statement: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: string
          module_id: string
          sequence_order: number
          source_reference: string
          statement: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: string
          module_id?: string
          sequence_order?: number
          source_reference?: string
          statement?: string
        }
        Relationships: [
          {
            foreignKeyName: "learning_outcomes_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      learning_resources: {
        Row: {
          class_id: string
          created_at: string
          deleted_at: string | null
          deleted_by: string | null
          deletion_reason: string | null
          description: string | null
          id: string
          mime_type: string | null
          size_bytes: number | null
          status: Database["public"]["Enums"]["resource_status"]
          storage_bucket: string
          storage_path: string
          title: string
          uploaded_by: string
        }
        Insert: {
          class_id: string
          created_at?: string
          deleted_at?: string | null
          deleted_by?: string | null
          deletion_reason?: string | null
          description?: string | null
          id?: string
          mime_type?: string | null
          size_bytes?: number | null
          status?: Database["public"]["Enums"]["resource_status"]
          storage_bucket: string
          storage_path: string
          title: string
          uploaded_by: string
        }
        Update: {
          class_id?: string
          created_at?: string
          deleted_at?: string | null
          deleted_by?: string | null
          deletion_reason?: string | null
          description?: string | null
          id?: string
          mime_type?: string | null
          size_bytes?: number | null
          status?: Database["public"]["Enums"]["resource_status"]
          storage_bucket?: string
          storage_path?: string
          title?: string
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "learning_resources_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      legacy_result_quarantine: {
        Row: {
          created_at: string
          duplicate_group_key: string
          integrity_flags: string[]
          legacy_mission_result_id: string
          migration_status: string
          review_reason: string | null
          reviewed_at: string | null
          reviewed_by: string | null
        }
        Insert: {
          created_at?: string
          duplicate_group_key: string
          integrity_flags?: string[]
          legacy_mission_result_id: string
          migration_status?: string
          review_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
        }
        Update: {
          created_at?: string
          duplicate_group_key?: string
          integrity_flags?: string[]
          legacy_mission_result_id?: string
          migration_status?: string
          review_reason?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "legacy_result_quarantine_legacy_mission_result_id_fkey"
            columns: ["legacy_mission_result_id"]
            isOneToOne: true
            referencedRelation: "mission_results"
            referencedColumns: ["id"]
          },
        ]
      }
      levels: {
        Row: {
          badge_icon: string | null
          created_at: string
          id: string
          level_name: string
          level_number: number
          max_xp: number | null
          min_xp: number
        }
        Insert: {
          badge_icon?: string | null
          created_at?: string
          id?: string
          level_name: string
          level_number: number
          max_xp?: number | null
          min_xp?: number
        }
        Update: {
          badge_icon?: string | null
          created_at?: string
          id?: string
          level_name?: string
          level_number?: number
          max_xp?: number | null
          min_xp?: number
        }
        Relationships: []
      }
      mission_catalog_history: {
        Row: {
          id: number
          mission_code: string
          previous: Json
          replaced_at: string
        }
        Insert: {
          id?: never
          mission_code: string
          previous: Json
          replaced_at?: string
        }
        Update: {
          id?: never
          mission_code?: string
          previous?: Json
          replaced_at?: string
        }
        Relationships: []
      }
      mission_curriculum_links: {
        Row: {
          mission_code: string
          module_id: string
          pc_codes: string[]
          sequence_order: number
        }
        Insert: {
          mission_code: string
          module_id: string
          pc_codes?: string[]
          sequence_order: number
        }
        Update: {
          mission_code?: string
          module_id?: string
          pc_codes?: string[]
          sequence_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "mission_curriculum_links_mission_code_fkey"
            columns: ["mission_code"]
            isOneToOne: true
            referencedRelation: "missions"
            referencedColumns: ["mission_code"]
          },
          {
            foreignKeyName: "mission_curriculum_links_mission_code_fkey"
            columns: ["mission_code"]
            isOneToOne: true
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_code"]
          },
          {
            foreignKeyName: "mission_curriculum_links_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
        ]
      }
      mission_results: {
        Row: {
          accuracy: number | null
          attempt_number: number
          coc_id: string | null
          competency_status:
            | Database["public"]["Enums"]["competency_status"]
            | null
          completed_at: string | null
          completed_tasks: number
          created_at: string
          earned_points: number
          feedback: string | null
          hints_used: number
          id: string
          incorrect_attempts: number
          max_score: number
          mission_id: string
          mission_title: string | null
          mistakes: string[]
          passed: boolean
          percentage: number
          rating: Database["public"]["Enums"]["rating_type"] | null
          remarks: string | null
          score: number
          time_spent_seconds: number
          total_tasks: number
          user_id: string
          xp_earned: number
        }
        Insert: {
          accuracy?: number | null
          attempt_number?: number
          coc_id?: string | null
          competency_status?:
            | Database["public"]["Enums"]["competency_status"]
            | null
          completed_at?: string | null
          completed_tasks?: number
          created_at?: string
          earned_points?: number
          feedback?: string | null
          hints_used?: number
          id?: string
          incorrect_attempts?: number
          max_score?: number
          mission_id: string
          mission_title?: string | null
          mistakes?: string[]
          passed?: boolean
          percentage?: number
          rating?: Database["public"]["Enums"]["rating_type"] | null
          remarks?: string | null
          score?: number
          time_spent_seconds?: number
          total_tasks?: number
          user_id: string
          xp_earned?: number
        }
        Update: {
          accuracy?: number | null
          attempt_number?: number
          coc_id?: string | null
          competency_status?:
            | Database["public"]["Enums"]["competency_status"]
            | null
          completed_at?: string | null
          completed_tasks?: number
          created_at?: string
          earned_points?: number
          feedback?: string | null
          hints_used?: number
          id?: string
          incorrect_attempts?: number
          max_score?: number
          mission_id?: string
          mission_title?: string | null
          mistakes?: string[]
          passed?: boolean
          percentage?: number
          rating?: Database["public"]["Enums"]["rating_type"] | null
          remarks?: string | null
          score?: number
          time_spent_seconds?: number
          total_tasks?: number
          user_id?: string
          xp_earned?: number
        }
        Relationships: [
          {
            foreignKeyName: "mission_results_coc_id_fkey"
            columns: ["coc_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mission_results_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mission_results_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      missions: {
        Row: {
          asset_path: string | null
          challenge_description: string | null
          coc_id: string
          competency_id: string | null
          created_at: string
          description: string | null
          difficulty: Database["public"]["Enums"]["difficulty_level"]
          estimated_time_minutes: number
          hint_count: number
          icon_url: string | null
          id: string
          is_locked: boolean
          mission_code: string
          mission_number: number
          mission_type: Database["public"]["Enums"]["mission_type"]
          objective: string | null
          order_index: number
          passing_score: number
          points_reward: number
          scenario: string | null
          skills_assessed: string[]
          status: Database["public"]["Enums"]["mission_status"]
          time_limit_seconds: number | null
          title: string
          updated_at: string
          xp_reward: number
        }
        Insert: {
          asset_path?: string | null
          challenge_description?: string | null
          coc_id: string
          competency_id?: string | null
          created_at?: string
          description?: string | null
          difficulty?: Database["public"]["Enums"]["difficulty_level"]
          estimated_time_minutes?: number
          hint_count?: number
          icon_url?: string | null
          id?: string
          is_locked?: boolean
          mission_code: string
          mission_number: number
          mission_type?: Database["public"]["Enums"]["mission_type"]
          objective?: string | null
          order_index?: number
          passing_score?: number
          points_reward?: number
          scenario?: string | null
          skills_assessed?: string[]
          status?: Database["public"]["Enums"]["mission_status"]
          time_limit_seconds?: number | null
          title: string
          updated_at?: string
          xp_reward?: number
        }
        Update: {
          asset_path?: string | null
          challenge_description?: string | null
          coc_id?: string
          competency_id?: string | null
          created_at?: string
          description?: string | null
          difficulty?: Database["public"]["Enums"]["difficulty_level"]
          estimated_time_minutes?: number
          hint_count?: number
          icon_url?: string | null
          id?: string
          is_locked?: boolean
          mission_code?: string
          mission_number?: number
          mission_type?: Database["public"]["Enums"]["mission_type"]
          objective?: string | null
          order_index?: number
          passing_score?: number
          points_reward?: number
          scenario?: string | null
          skills_assessed?: string[]
          status?: Database["public"]["Enums"]["mission_status"]
          time_limit_seconds?: number | null
          title?: string
          updated_at?: string
          xp_reward?: number
        }
        Relationships: [
          {
            foreignKeyName: "missions_coc_id_fkey"
            columns: ["coc_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "missions_competency_id_fkey"
            columns: ["competency_id"]
            isOneToOne: false
            referencedRelation: "competencies"
            referencedColumns: ["id"]
          },
        ]
      }
      module_versions: {
        Row: {
          content_metadata: Json
          created_at: string
          created_by: string
          description: string | null
          id: string
          module_id: string
          published_at: string | null
          published_by: string | null
          retired_at: string | null
          source_trace: Json
          status: Database["public"]["Enums"]["content_version_status"]
          tesda_source_id: string
          title: string
          updated_at: string
          version_number: number
        }
        Insert: {
          content_metadata?: Json
          created_at?: string
          created_by: string
          description?: string | null
          id?: string
          module_id: string
          published_at?: string | null
          published_by?: string | null
          retired_at?: string | null
          source_trace?: Json
          status?: Database["public"]["Enums"]["content_version_status"]
          tesda_source_id: string
          title: string
          updated_at?: string
          version_number: number
        }
        Update: {
          content_metadata?: Json
          created_at?: string
          created_by?: string
          description?: string | null
          id?: string
          module_id?: string
          published_at?: string | null
          published_by?: string | null
          retired_at?: string | null
          source_trace?: Json
          status?: Database["public"]["Enums"]["content_version_status"]
          tesda_source_id?: string
          title?: string
          updated_at?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "module_versions_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "module_versions_tesda_source_id_fkey"
            columns: ["tesda_source_id"]
            isOneToOne: false
            referencedRelation: "tesda_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          created_at: string
          event_key: string | null
          id: string
          is_read: boolean
          message: string
          metadata: Json
          read_at: string | null
          related_coc_id: string | null
          related_mission_id: string | null
          title: string
          type: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Insert: {
          created_at?: string
          event_key?: string | null
          id?: string
          is_read?: boolean
          message: string
          metadata?: Json
          read_at?: string | null
          related_coc_id?: string | null
          related_mission_id?: string | null
          title: string
          type?: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Update: {
          created_at?: string
          event_key?: string | null
          id?: string
          is_read?: boolean
          message?: string
          metadata?: Json
          read_at?: string | null
          related_coc_id?: string | null
          related_mission_id?: string | null
          title?: string
          type?: Database["public"]["Enums"]["notification_type"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_related_coc_id_fkey"
            columns: ["related_coc_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_related_mission_id_fkey"
            columns: ["related_mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_related_mission_id_fkey"
            columns: ["related_mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      practice_coc_progress: {
        Row: {
          coc_code: string
          completed_at: string
          learner_id: string
          quiz_attempt_id: string
        }
        Insert: {
          coc_code: string
          completed_at?: string
          learner_id: string
          quiz_attempt_id: string
        }
        Update: {
          coc_code?: string
          completed_at?: string
          learner_id?: string
          quiz_attempt_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "practice_coc_progress_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "practice_coc_progress_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "practice_progress_quiz_fk"
            columns: ["quiz_attempt_id"]
            isOneToOne: false
            referencedRelation: "practice_quiz_attempts"
            referencedColumns: ["id"]
          },
        ]
      }
      practice_mission_actions: {
        Row: {
          action_type: string
          client_action_id: string
          client_occurred_at: string
          created_at: string
          id: number
          learner_id: string
          mission_id: string
          phase_id: string
          target: string | null
          value: Json
        }
        Insert: {
          action_type: string
          client_action_id: string
          client_occurred_at: string
          created_at?: string
          id?: never
          learner_id: string
          mission_id: string
          phase_id: string
          target?: string | null
          value?: Json
        }
        Update: {
          action_type?: string
          client_action_id?: string
          client_occurred_at?: string
          created_at?: string
          id?: never
          learner_id?: string
          mission_id?: string
          phase_id?: string
          target?: string | null
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "practice_mission_actions_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "practice_mission_actions_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
        ]
      }
      practice_mission_completions: {
        Row: {
          contract_version: string
          evidence_through_id: number
          learner_id: string
          mission_id: string
          verified_at: string
        }
        Insert: {
          contract_version: string
          evidence_through_id: number
          learner_id: string
          mission_id: string
          verified_at?: string
        }
        Update: {
          contract_version?: string
          evidence_through_id?: number
          learner_id?: string
          mission_id?: string
          verified_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "practice_mission_completions_evidence_through_id_fkey"
            columns: ["evidence_through_id"]
            isOneToOne: false
            referencedRelation: "practice_mission_actions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "practice_mission_completions_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "practice_mission_completions_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "practice_mission_completions_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "practice_mission_contracts"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      practice_mission_contracts: {
        Row: {
          definition: Json
          mission_id: string
          version: string
        }
        Insert: {
          definition: Json
          mission_id: string
          version: string
        }
        Update: {
          definition?: Json
          mission_id?: string
          version?: string
        }
        Relationships: []
      }
      practice_mission_runs: {
        Row: {
          action_count: number
          contract_version: string
          correction_count: number
          created_at: string
          duration_seconds: number | null
          ended_at: string | null
          failure_code: string | null
          id: string
          invalid_count: number
          learner_id: string
          mission_id: string
          outcome: string
          run_number: number
          started_at: string | null
          step_results: Json
        }
        Insert: {
          action_count?: number
          contract_version: string
          correction_count?: number
          created_at?: string
          duration_seconds?: number | null
          ended_at?: string | null
          failure_code?: string | null
          id?: string
          invalid_count?: number
          learner_id: string
          mission_id: string
          outcome: string
          run_number: number
          started_at?: string | null
          step_results?: Json
        }
        Update: {
          action_count?: number
          contract_version?: string
          correction_count?: number
          created_at?: string
          duration_seconds?: number | null
          ended_at?: string | null
          failure_code?: string | null
          id?: string
          invalid_count?: number
          learner_id?: string
          mission_id?: string
          outcome?: string
          run_number?: number
          started_at?: string | null
          step_results?: Json
        }
        Relationships: [
          {
            foreignKeyName: "practice_mission_runs_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "practice_mission_runs_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
        ]
      }
      practice_quiz_attempts: {
        Row: {
          answers: Json
          coc_code: string
          created_at: string
          id: string
          learner_id: string
          passed: boolean | null
          passing_percent: number
          questions: Json
          score: number | null
          source: string
          status: string
          submitted_at: string | null
        }
        Insert: {
          answers?: Json
          coc_code: string
          created_at?: string
          id?: string
          learner_id: string
          passed?: boolean | null
          passing_percent?: number
          questions: Json
          score?: number | null
          source?: string
          status?: string
          submitted_at?: string | null
        }
        Update: {
          answers?: Json
          coc_code?: string
          created_at?: string
          id?: string
          learner_id?: string
          passed?: boolean | null
          passing_percent?: number
          questions?: Json
          score?: number | null
          source?: string
          status?: string
          submitted_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "practice_quiz_attempts_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "practice_quiz_attempts_learner_id_fkey"
            columns: ["learner_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          completed_missions: number
          course_section: string | null
          created_at: string
          current_level: number
          current_streak: number
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          email: string
          full_name: string
          id: string
          last_activity_at: string | null
          last_login_at: string | null
          learner_id: string | null
          learner_id_managed: boolean
          role: Database["public"]["Enums"]["user_role"]
          school: string | null
          show_on_leaderboard: boolean
          status: Database["public"]["Enums"]["account_status"]
          total_badges: number
          total_points: number
          total_xp: number
          updated_at: string
          user_id: string
        }
        Insert: {
          avatar_url?: string | null
          completed_missions?: number
          course_section?: string | null
          created_at?: string
          current_level?: number
          current_streak?: number
          deactivated_at?: string | null
          deactivated_by?: string | null
          deactivation_reason?: string | null
          email?: string
          full_name?: string
          id?: string
          last_activity_at?: string | null
          last_login_at?: string | null
          learner_id?: string | null
          learner_id_managed?: boolean
          role?: Database["public"]["Enums"]["user_role"]
          school?: string | null
          show_on_leaderboard?: boolean
          status?: Database["public"]["Enums"]["account_status"]
          total_badges?: number
          total_points?: number
          total_xp?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          avatar_url?: string | null
          completed_missions?: number
          course_section?: string | null
          created_at?: string
          current_level?: number
          current_streak?: number
          deactivated_at?: string | null
          deactivated_by?: string | null
          deactivation_reason?: string | null
          email?: string
          full_name?: string
          id?: string
          last_activity_at?: string | null
          last_login_at?: string | null
          learner_id?: string | null
          learner_id_managed?: boolean
          role?: Database["public"]["Enums"]["user_role"]
          school?: string | null
          show_on_leaderboard?: boolean
          status?: Database["public"]["Enums"]["account_status"]
          total_badges?: number
          total_points?: number
          total_xp?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      quiz_answers: {
        Row: {
          answer: Json
          answered_at: string
          id: string
          is_correct: boolean | null
          quiz_attempt_id: string
          quiz_item_id: string
          quiz_version_id: string
          updated_at: string
        }
        Insert: {
          answer: Json
          answered_at?: string
          id?: string
          is_correct?: boolean | null
          quiz_attempt_id: string
          quiz_item_id: string
          quiz_version_id: string
          updated_at?: string
        }
        Update: {
          answer?: Json
          answered_at?: string
          id?: string
          is_correct?: boolean | null
          quiz_attempt_id?: string
          quiz_item_id?: string
          quiz_version_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_answers_attempt_version_fkey"
            columns: ["quiz_attempt_id", "quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_attempts"
            referencedColumns: ["id", "quiz_version_id"]
          },
          {
            foreignKeyName: "quiz_answers_item_version_fkey"
            columns: ["quiz_item_id", "quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_items"
            referencedColumns: ["id", "quiz_version_id"]
          },
          {
            foreignKeyName: "quiz_answers_quiz_attempt_id_fkey"
            columns: ["quiz_attempt_id"]
            isOneToOne: false
            referencedRelation: "quiz_attempts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_answers_quiz_item_id_fkey"
            columns: ["quiz_item_id"]
            isOneToOne: false
            referencedRelation: "quiz_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_answers_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_assignments: {
        Row: {
          assigned_by: string
          attempts_allowed: number | null
          available_at: string | null
          class_id: string
          close_reason: string | null
          closed_at: string | null
          created_at: string
          due_at: string | null
          id: string
          instructions: string | null
          quiz_version_id: string
          status: Database["public"]["Enums"]["assignment_status"]
          updated_at: string
        }
        Insert: {
          assigned_by: string
          attempts_allowed?: number | null
          available_at?: string | null
          class_id: string
          close_reason?: string | null
          closed_at?: string | null
          created_at?: string
          due_at?: string | null
          id?: string
          instructions?: string | null
          quiz_version_id: string
          status?: Database["public"]["Enums"]["assignment_status"]
          updated_at?: string
        }
        Update: {
          assigned_by?: string
          attempts_allowed?: number | null
          available_at?: string | null
          class_id?: string
          close_reason?: string | null
          closed_at?: string | null
          created_at?: string
          due_at?: string | null
          id?: string
          instructions?: string | null
          quiz_version_id?: string
          status?: Database["public"]["Enums"]["assignment_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_assignments_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_assignments_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_attempts: {
        Row: {
          class_id: string
          client_start_key: string
          completed_at: string | null
          created_at: string
          evaluation_status: string
          id: string
          learner_id: string
          quiz_assignment_id: string
          quiz_version_id: string
          started_at: string
          status: Database["public"]["Enums"]["quiz_attempt_status"]
          submission_key: string | null
          submission_kind: string
          submitted_at: string | null
          time_limit_minutes: number | null
          updated_at: string
        }
        Insert: {
          class_id: string
          client_start_key: string
          completed_at?: string | null
          created_at?: string
          evaluation_status?: string
          id?: string
          learner_id: string
          quiz_assignment_id: string
          quiz_version_id: string
          started_at?: string
          status?: Database["public"]["Enums"]["quiz_attempt_status"]
          submission_key?: string | null
          submission_kind?: string
          submitted_at?: string | null
          time_limit_minutes?: number | null
          updated_at?: string
        }
        Update: {
          class_id?: string
          client_start_key?: string
          completed_at?: string | null
          created_at?: string
          evaluation_status?: string
          id?: string
          learner_id?: string
          quiz_assignment_id?: string
          quiz_version_id?: string
          started_at?: string
          status?: Database["public"]["Enums"]["quiz_attempt_status"]
          submission_key?: string | null
          submission_kind?: string
          submitted_at?: string | null
          time_limit_minutes?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_attempts_assignment_identity_fkey"
            columns: ["quiz_assignment_id", "class_id", "quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_assignments"
            referencedColumns: ["id", "class_id", "quiz_version_id"]
          },
          {
            foreignKeyName: "quiz_attempts_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_attempts_quiz_assignment_id_fkey"
            columns: ["quiz_assignment_id"]
            isOneToOne: false
            referencedRelation: "quiz_assignments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_attempts_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_essay_scores: {
        Row: {
          attempt_id: string
          criterion_scores: Json
          evaluated_at: string
          evaluated_by: string
          feedback: string | null
          id: string
          item_id: string
          sequence: number
          total: number
        }
        Insert: {
          attempt_id: string
          criterion_scores: Json
          evaluated_at?: string
          evaluated_by: string
          feedback?: string | null
          id?: string
          item_id: string
          sequence?: never
          total: number
        }
        Update: {
          attempt_id?: string
          criterion_scores?: Json
          evaluated_at?: string
          evaluated_by?: string
          feedback?: string | null
          id?: string
          item_id?: string
          sequence?: never
          total?: number
        }
        Relationships: [
          {
            foreignKeyName: "quiz_essay_scores_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: false
            referencedRelation: "quiz_attempts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_essay_scores_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "quiz_items"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_items: {
        Row: {
          ai_generation_id: string | null
          correct_answer: Json
          created_at: string
          created_by: string
          explanation: string | null
          id: string
          item_code: string
          item_type: Database["public"]["Enums"]["quiz_item_type"]
          max_words: number | null
          min_words: number | null
          options: Json
          order_index: number
          origin: Database["public"]["Enums"]["quiz_item_origin"]
          points: number
          prompt: string
          quiz_version_id: string
          removal_reason: string | null
          removed_at: string | null
          removed_by: string | null
          review_notes: string | null
          review_status: Database["public"]["Enums"]["quiz_item_review_status"]
          reviewed_at: string | null
          reviewed_by: string | null
          rubric: Json | null
          scenario: string | null
          updated_at: string
        }
        Insert: {
          ai_generation_id?: string | null
          correct_answer: Json
          created_at?: string
          created_by: string
          explanation?: string | null
          id?: string
          item_code: string
          item_type: Database["public"]["Enums"]["quiz_item_type"]
          max_words?: number | null
          min_words?: number | null
          options?: Json
          order_index: number
          origin?: Database["public"]["Enums"]["quiz_item_origin"]
          points?: number
          prompt: string
          quiz_version_id: string
          removal_reason?: string | null
          removed_at?: string | null
          removed_by?: string | null
          review_notes?: string | null
          review_status?: Database["public"]["Enums"]["quiz_item_review_status"]
          reviewed_at?: string | null
          reviewed_by?: string | null
          rubric?: Json | null
          scenario?: string | null
          updated_at?: string
        }
        Update: {
          ai_generation_id?: string | null
          correct_answer?: Json
          created_at?: string
          created_by?: string
          explanation?: string | null
          id?: string
          item_code?: string
          item_type?: Database["public"]["Enums"]["quiz_item_type"]
          max_words?: number | null
          min_words?: number | null
          options?: Json
          order_index?: number
          origin?: Database["public"]["Enums"]["quiz_item_origin"]
          points?: number
          prompt?: string
          quiz_version_id?: string
          removal_reason?: string | null
          removed_at?: string | null
          removed_by?: string | null
          review_notes?: string | null
          review_status?: Database["public"]["Enums"]["quiz_item_review_status"]
          reviewed_at?: string | null
          reviewed_by?: string | null
          rubric?: Json | null
          scenario?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_items_ai_generation_id_fkey"
            columns: ["ai_generation_id"]
            isOneToOne: false
            referencedRelation: "ai_quiz_generations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_items_quiz_version_id_fkey"
            columns: ["quiz_version_id"]
            isOneToOne: false
            referencedRelation: "quiz_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_learning_outcomes: {
        Row: {
          created_at: string
          outcome_id: string
          quiz_id: string
        }
        Insert: {
          created_at?: string
          outcome_id: string
          quiz_id: string
        }
        Update: {
          created_at?: string
          outcome_id?: string
          quiz_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_learning_outcomes_outcome_id_fkey"
            columns: ["outcome_id"]
            isOneToOne: false
            referencedRelation: "learning_outcomes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_learning_outcomes_quiz_id_fkey"
            columns: ["quiz_id"]
            isOneToOne: false
            referencedRelation: "quizzes"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_modules: {
        Row: {
          created_at: string
          module_id: string
          quiz_id: string
        }
        Insert: {
          created_at?: string
          module_id: string
          quiz_id: string
        }
        Update: {
          created_at?: string
          module_id?: string
          quiz_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_modules_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "curriculum_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quiz_modules_quiz_id_fkey"
            columns: ["quiz_id"]
            isOneToOne: false
            referencedRelation: "quizzes"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_result_finalizations: {
        Row: {
          attempt_id: string
          essay_points: number
          finalized_at: string
          finalized_by: string
          max_points: number
          objective_points: number
          percent: number
          released_at: string | null
          released_by: string | null
          total_points: number
        }
        Insert: {
          attempt_id: string
          essay_points: number
          finalized_at?: string
          finalized_by: string
          max_points: number
          objective_points: number
          percent: number
          released_at?: string | null
          released_by?: string | null
          total_points: number
        }
        Update: {
          attempt_id?: string
          essay_points?: number
          finalized_at?: string
          finalized_by?: string
          max_points?: number
          objective_points?: number
          percent?: number
          released_at?: string | null
          released_by?: string | null
          total_points?: number
        }
        Relationships: [
          {
            foreignKeyName: "quiz_result_finalizations_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: true
            referencedRelation: "quiz_attempts"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_results: {
        Row: {
          correct_count: number
          created_at: string
          evaluated_at: string
          id: string
          item_results: Json
          max_points: number | null
          objective_points: number | null
          question_count: number
          quiz_attempt_id: string
        }
        Insert: {
          correct_count: number
          created_at?: string
          evaluated_at?: string
          id?: string
          item_results: Json
          max_points?: number | null
          objective_points?: number | null
          question_count: number
          quiz_attempt_id: string
        }
        Update: {
          correct_count?: number
          created_at?: string
          evaluated_at?: string
          id?: string
          item_results?: Json
          max_points?: number | null
          objective_points?: number | null
          question_count?: number
          quiz_attempt_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "quiz_results_quiz_attempt_id_fkey"
            columns: ["quiz_attempt_id"]
            isOneToOne: true
            referencedRelation: "quiz_attempts"
            referencedColumns: ["id"]
          },
        ]
      }
      quiz_versions: {
        Row: {
          change_summary: string | null
          created_at: string
          created_by: string
          id: string
          instructions: string | null
          published_at: string | null
          published_by: string | null
          quiz_id: string
          result_release_mode: string
          retired_at: string | null
          status: Database["public"]["Enums"]["content_version_status"]
          time_limit_minutes: number | null
          updated_at: string
          version_number: number
        }
        Insert: {
          change_summary?: string | null
          created_at?: string
          created_by: string
          id?: string
          instructions?: string | null
          published_at?: string | null
          published_by?: string | null
          quiz_id: string
          result_release_mode?: string
          retired_at?: string | null
          status?: Database["public"]["Enums"]["content_version_status"]
          time_limit_minutes?: number | null
          updated_at?: string
          version_number: number
        }
        Update: {
          change_summary?: string | null
          created_at?: string
          created_by?: string
          id?: string
          instructions?: string | null
          published_at?: string | null
          published_by?: string | null
          quiz_id?: string
          result_release_mode?: string
          retired_at?: string | null
          status?: Database["public"]["Enums"]["content_version_status"]
          time_limit_minutes?: number | null
          updated_at?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "quiz_versions_quiz_id_fkey"
            columns: ["quiz_id"]
            isOneToOne: false
            referencedRelation: "quizzes"
            referencedColumns: ["id"]
          },
        ]
      }
      quizzes: {
        Row: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          coc_module_id: string | null
          created_at: string
          created_by: string
          description: string | null
          difficulty: string | null
          focus: string | null
          id: string
          instructor_id: string
          quiz_type: string | null
          title: string
          topic: string
          topic_id: string | null
          updated_at: string
        }
        Insert: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          coc_module_id?: string | null
          created_at?: string
          created_by: string
          description?: string | null
          difficulty?: string | null
          focus?: string | null
          id?: string
          instructor_id: string
          quiz_type?: string | null
          title: string
          topic: string
          topic_id?: string | null
          updated_at?: string
        }
        Update: {
          archive_reason?: string | null
          archived_at?: string | null
          archived_by?: string | null
          coc_module_id?: string | null
          created_at?: string
          created_by?: string
          description?: string | null
          difficulty?: string | null
          focus?: string | null
          id?: string
          instructor_id?: string
          quiz_type?: string | null
          title?: string
          topic?: string
          topic_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "quizzes_coc_module_id_fkey"
            columns: ["coc_module_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "quizzes_topic_id_fkey"
            columns: ["topic_id"]
            isOneToOne: false
            referencedRelation: "curriculum_topics"
            referencedColumns: ["id"]
          },
        ]
      }
      reports: {
        Row: {
          created_at: string
          data: Json
          filters: Json
          generated_by: string | null
          id: string
          report_type: Database["public"]["Enums"]["report_type"]
          title: string
        }
        Insert: {
          created_at?: string
          data?: Json
          filters?: Json
          generated_by?: string | null
          id?: string
          report_type: Database["public"]["Enums"]["report_type"]
          title: string
        }
        Update: {
          created_at?: string
          data?: Json
          filters?: Json
          generated_by?: string | null
          id?: string
          report_type?: Database["public"]["Enums"]["report_type"]
          title?: string
        }
        Relationships: []
      }
      resource_upload_jobs: {
        Row: {
          class_id: string
          id: string
          instructor_id: string
          state: string
          storage_path: string
          updated_at: string
        }
        Insert: {
          class_id: string
          id: string
          instructor_id: string
          state?: string
          storage_path: string
          updated_at?: string
        }
        Update: {
          class_id?: string
          id?: string
          instructor_id?: string
          state?: string
          storage_path?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "resource_upload_jobs_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "resource_upload_jobs_instructor_id_fkey"
            columns: ["instructor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["user_id"]
          },
          {
            foreignKeyName: "resource_upload_jobs_instructor_id_fkey"
            columns: ["instructor_id"]
            isOneToOne: false
            referencedRelation: "view_leaderboard_overall"
            referencedColumns: ["user_id"]
          },
        ]
      }
      result_releases: {
        Row: {
          attempt_id: string
          created_at: string
          id: string
          is_current: boolean
          release_number: number
          release_reason: string | null
          released_at: string
          released_by: string
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          score_revision_id: string
        }
        Insert: {
          attempt_id: string
          created_at?: string
          id?: string
          is_current?: boolean
          release_number: number
          release_reason?: string | null
          released_at?: string
          released_by: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          score_revision_id: string
        }
        Update: {
          attempt_id?: string
          created_at?: string
          id?: string
          is_current?: boolean
          release_number?: number
          release_reason?: string | null
          released_at?: string
          released_by?: string
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          score_revision_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "result_releases_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: false
            referencedRelation: "attempts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "result_releases_score_revision_id_fkey"
            columns: ["score_revision_id"]
            isOneToOne: false
            referencedRelation: "score_revisions"
            referencedColumns: ["id"]
          },
        ]
      }
      roster_import_batches: {
        Row: {
          class_id: string
          created_at: string
          enrolled_count: number
          file_name: string | null
          id: string
          instructor_id: string
          invalid_count: number
          pending_count: number
          row_count: number
          skipped_count: number
        }
        Insert: {
          class_id: string
          created_at?: string
          enrolled_count?: number
          file_name?: string | null
          id?: string
          instructor_id: string
          invalid_count?: number
          pending_count?: number
          row_count: number
          skipped_count?: number
        }
        Update: {
          class_id?: string
          created_at?: string
          enrolled_count?: number
          file_name?: string | null
          id?: string
          instructor_id?: string
          invalid_count?: number
          pending_count?: number
          row_count?: number
          skipped_count?: number
        }
        Relationships: [
          {
            foreignKeyName: "roster_import_batches_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      rubric_criteria: {
        Row: {
          created_at: string
          criterion_code: string
          description: string | null
          evidence_rule: Json
          id: string
          is_required: boolean
          max_value: number | null
          order_index: number
          rubric_version_id: string
          scoring_rule: Json
          source_trace: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          criterion_code: string
          description?: string | null
          evidence_rule?: Json
          id?: string
          is_required?: boolean
          max_value?: number | null
          order_index: number
          rubric_version_id: string
          scoring_rule?: Json
          source_trace: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          criterion_code?: string
          description?: string | null
          evidence_rule?: Json
          id?: string
          is_required?: boolean
          max_value?: number | null
          order_index?: number
          rubric_version_id?: string
          scoring_rule?: Json
          source_trace?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rubric_criteria_rubric_version_id_fkey"
            columns: ["rubric_version_id"]
            isOneToOne: false
            referencedRelation: "rubric_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      rubric_versions: {
        Row: {
          activity_version_id: string
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          id: string
          passing_rule: Json
          retired_at: string | null
          scoring_method: string
          status: Database["public"]["Enums"]["rubric_status"]
          tesda_source_id: string
          title: string
          updated_at: string
          version_number: number
        }
        Insert: {
          activity_version_id: string
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by: string
          id?: string
          passing_rule?: Json
          retired_at?: string | null
          scoring_method?: string
          status?: Database["public"]["Enums"]["rubric_status"]
          tesda_source_id: string
          title: string
          updated_at?: string
          version_number: number
        }
        Update: {
          activity_version_id?: string
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string
          id?: string
          passing_rule?: Json
          retired_at?: string | null
          scoring_method?: string
          status?: Database["public"]["Enums"]["rubric_status"]
          tesda_source_id?: string
          title?: string
          updated_at?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "rubric_versions_activity_version_id_fkey"
            columns: ["activity_version_id"]
            isOneToOne: false
            referencedRelation: "activity_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rubric_versions_tesda_source_id_fkey"
            columns: ["tesda_source_id"]
            isOneToOne: false
            referencedRelation: "tesda_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      score_revisions: {
        Row: {
          actor_id: string | null
          actor_role: Database["public"]["Enums"]["user_role"] | null
          attempt_id: string
          created_at: string
          criterion_values: Json
          evaluation_run_id: string | null
          id: string
          max_value: number | null
          outcome: Database["public"]["Enums"]["evaluation_outcome"]
          percentage: number | null
          reason: string | null
          remarks: string | null
          revision_number: number
          revision_type: Database["public"]["Enums"]["score_revision_type"]
          rubric_version_id: string
          supersedes_revision_id: string | null
          tesda_source_id: string
          total_value: number | null
        }
        Insert: {
          actor_id?: string | null
          actor_role?: Database["public"]["Enums"]["user_role"] | null
          attempt_id: string
          created_at?: string
          criterion_values?: Json
          evaluation_run_id?: string | null
          id?: string
          max_value?: number | null
          outcome: Database["public"]["Enums"]["evaluation_outcome"]
          percentage?: number | null
          reason?: string | null
          remarks?: string | null
          revision_number: number
          revision_type: Database["public"]["Enums"]["score_revision_type"]
          rubric_version_id: string
          supersedes_revision_id?: string | null
          tesda_source_id: string
          total_value?: number | null
        }
        Update: {
          actor_id?: string | null
          actor_role?: Database["public"]["Enums"]["user_role"] | null
          attempt_id?: string
          created_at?: string
          criterion_values?: Json
          evaluation_run_id?: string | null
          id?: string
          max_value?: number | null
          outcome?: Database["public"]["Enums"]["evaluation_outcome"]
          percentage?: number | null
          reason?: string | null
          remarks?: string | null
          revision_number?: number
          revision_type?: Database["public"]["Enums"]["score_revision_type"]
          rubric_version_id?: string
          supersedes_revision_id?: string | null
          tesda_source_id?: string
          total_value?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "score_revisions_attempt_id_fkey"
            columns: ["attempt_id"]
            isOneToOne: false
            referencedRelation: "attempts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "score_revisions_rubric_version_id_fkey"
            columns: ["rubric_version_id"]
            isOneToOne: false
            referencedRelation: "rubric_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "score_revisions_supersedes_revision_id_fkey"
            columns: ["supersedes_revision_id"]
            isOneToOne: false
            referencedRelation: "score_revisions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "score_revisions_tesda_source_id_fkey"
            columns: ["tesda_source_id"]
            isOneToOne: false
            referencedRelation: "tesda_sources"
            referencedColumns: ["id"]
          },
        ]
      }
      simulation_tasks: {
        Row: {
          accepted_component_ids: string[]
          component_id: string | null
          correct_answer: string | null
          correct_target: string | null
          created_at: string
          feedback_correct: string | null
          feedback_incorrect: string | null
          hint_text: string | null
          id: string
          instruction: string
          is_required: boolean
          mission_id: string
          options: Json
          order_index: number
          points: number
          question_text: string | null
          required_order: number | null
          requires_previous_task: boolean
          target_zone_id: string | null
          task_code: string | null
          task_number: number
          task_type: Database["public"]["Enums"]["mission_type"]
          updated_at: string
        }
        Insert: {
          accepted_component_ids?: string[]
          component_id?: string | null
          correct_answer?: string | null
          correct_target?: string | null
          created_at?: string
          feedback_correct?: string | null
          feedback_incorrect?: string | null
          hint_text?: string | null
          id?: string
          instruction: string
          is_required?: boolean
          mission_id: string
          options?: Json
          order_index?: number
          points?: number
          question_text?: string | null
          required_order?: number | null
          requires_previous_task?: boolean
          target_zone_id?: string | null
          task_code?: string | null
          task_number: number
          task_type?: Database["public"]["Enums"]["mission_type"]
          updated_at?: string
        }
        Update: {
          accepted_component_ids?: string[]
          component_id?: string | null
          correct_answer?: string | null
          correct_target?: string | null
          created_at?: string
          feedback_correct?: string | null
          feedback_incorrect?: string | null
          hint_text?: string | null
          id?: string
          instruction?: string
          is_required?: boolean
          mission_id?: string
          options?: Json
          order_index?: number
          points?: number
          question_text?: string | null
          required_order?: number | null
          requires_previous_task?: boolean
          target_zone_id?: string | null
          task_code?: string | null
          task_number?: number
          task_type?: Database["public"]["Enums"]["mission_type"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "simulation_tasks_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "simulation_tasks_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      support_concerns: {
        Row: {
          class_id: string | null
          created_at: string
          details: string
          history: Json
          id: string
          opened_by: string
          resolved_at: string | null
          scope: string
          status: string
          status_reason: string | null
          title: string
          updated_at: string
        }
        Insert: {
          class_id?: string | null
          created_at?: string
          details: string
          history?: Json
          id?: string
          opened_by?: string
          resolved_at?: string | null
          scope: string
          status?: string
          status_reason?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          class_id?: string | null
          created_at?: string
          details?: string
          history?: Json
          id?: string
          opened_by?: string
          resolved_at?: string | null
          scope?: string
          status?: string
          status_reason?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_concerns_class_id_fkey"
            columns: ["class_id"]
            isOneToOne: false
            referencedRelation: "classes"
            referencedColumns: ["id"]
          },
        ]
      }
      system_settings: {
        Row: {
          description: string | null
          setting_key: string
          setting_value: Json
          updated_at: string
          updated_by: string
        }
        Insert: {
          description?: string | null
          setting_key: string
          setting_value: Json
          updated_at?: string
          updated_by: string
        }
        Update: {
          description?: string | null
          setting_key?: string
          setting_value?: Json
          updated_at?: string
          updated_by?: string
        }
        Relationships: []
      }
      task_results: {
        Row: {
          attempts: number
          completed_at: string | null
          correct_answer: string | null
          correct_target: string | null
          created_at: string
          feedback: string | null
          hint_used: boolean
          id: string
          is_completed: boolean
          is_correct: boolean | null
          max_score: number
          mission_id: string
          mission_result_id: string
          score_obtained: number
          selected_answer: string | null
          selected_target: string | null
          task_id: string | null
          user_id: string
        }
        Insert: {
          attempts?: number
          completed_at?: string | null
          correct_answer?: string | null
          correct_target?: string | null
          created_at?: string
          feedback?: string | null
          hint_used?: boolean
          id?: string
          is_completed?: boolean
          is_correct?: boolean | null
          max_score?: number
          mission_id: string
          mission_result_id: string
          score_obtained?: number
          selected_answer?: string | null
          selected_target?: string | null
          task_id?: string | null
          user_id: string
        }
        Update: {
          attempts?: number
          completed_at?: string | null
          correct_answer?: string | null
          correct_target?: string | null
          created_at?: string
          feedback?: string | null
          hint_used?: boolean
          id?: string
          is_completed?: boolean
          is_correct?: boolean | null
          max_score?: number
          mission_id?: string
          mission_result_id?: string
          score_obtained?: number
          selected_answer?: string | null
          selected_target?: string | null
          task_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_results_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_results_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
          {
            foreignKeyName: "task_results_mission_result_id_fkey"
            columns: ["mission_result_id"]
            isOneToOne: false
            referencedRelation: "mission_results"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_results_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "simulation_tasks"
            referencedColumns: ["id"]
          },
        ]
      }
      tesda_sources: {
        Row: {
          activated_at: string | null
          activated_by: string | null
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          document_storage_path: string | null
          edition: string | null
          effective_date: string | null
          id: string
          publication_date: string | null
          qualification_code: string
          source_reference: string
          status: Database["public"]["Enums"]["tesda_source_status"]
          title: string
          updated_at: string
          validation_notes: string | null
        }
        Insert: {
          activated_at?: string | null
          activated_by?: string | null
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by: string
          document_storage_path?: string | null
          edition?: string | null
          effective_date?: string | null
          id?: string
          publication_date?: string | null
          qualification_code: string
          source_reference: string
          status?: Database["public"]["Enums"]["tesda_source_status"]
          title: string
          updated_at?: string
          validation_notes?: string | null
        }
        Update: {
          activated_at?: string | null
          activated_by?: string | null
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string
          document_storage_path?: string | null
          edition?: string | null
          effective_date?: string | null
          id?: string
          publication_date?: string | null
          qualification_code?: string
          source_reference?: string
          status?: Database["public"]["Enums"]["tesda_source_status"]
          title?: string
          updated_at?: string
          validation_notes?: string | null
        }
        Relationships: []
      }
      user_achievements: {
        Row: {
          achievement_id: string
          coc_id: string | null
          created_at: string
          earned_at: string
          id: string
          mission_id: string | null
          user_id: string
        }
        Insert: {
          achievement_id: string
          coc_id?: string | null
          created_at?: string
          earned_at?: string
          id?: string
          mission_id?: string | null
          user_id: string
        }
        Update: {
          achievement_id?: string
          coc_id?: string | null
          created_at?: string
          earned_at?: string
          id?: string
          mission_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_achievements_achievement_id_fkey"
            columns: ["achievement_id"]
            isOneToOne: false
            referencedRelation: "achievements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_achievements_coc_id_fkey"
            columns: ["coc_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_achievements_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_achievements_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      user_badges: {
        Row: {
          badge_id: string
          coc_id: string | null
          created_at: string
          earned_at: string
          id: string
          mission_id: string | null
          user_id: string
        }
        Insert: {
          badge_id: string
          coc_id?: string | null
          created_at?: string
          earned_at?: string
          id?: string
          mission_id?: string | null
          user_id: string
        }
        Update: {
          badge_id?: string
          coc_id?: string | null
          created_at?: string
          earned_at?: string
          id?: string
          mission_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_badges_badge_id_fkey"
            columns: ["badge_id"]
            isOneToOne: false
            referencedRelation: "badges"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_badges_coc_id_fkey"
            columns: ["coc_id"]
            isOneToOne: false
            referencedRelation: "coc_modules"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_badges_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_badges_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "view_mission_performance_summary"
            referencedColumns: ["mission_id"]
          },
        ]
      }
      user_settings: {
        Row: {
          created_at: string
          id: string
          language: string
          notifications_enabled: boolean
          sound_enabled: boolean
          theme_mode: string
          updated_at: string
          user_id: string
          vibration_enabled: boolean
        }
        Insert: {
          created_at?: string
          id?: string
          language?: string
          notifications_enabled?: boolean
          sound_enabled?: boolean
          theme_mode?: string
          updated_at?: string
          user_id: string
          vibration_enabled?: boolean
        }
        Update: {
          created_at?: string
          id?: string
          language?: string
          notifications_enabled?: boolean
          sound_enabled?: boolean
          theme_mode?: string
          updated_at?: string
          user_id?: string
          vibration_enabled?: boolean
        }
        Relationships: []
      }
    }
    Views: {
      learner_achievements: {
        Row: {
          code: string | null
          earned_at: string | null
          learner_id: string | null
        }
        Relationships: []
      }
      view_leaderboard_overall: {
        Row: {
          avatar_url: string | null
          completed_missions: number | null
          current_level: number | null
          full_name: string | null
          rank: number | null
          total_badges: number | null
          total_points: number | null
          total_xp: number | null
          user_id: string | null
        }
        Relationships: []
      }
      view_mission_performance_summary: {
        Row: {
          average_score: number | null
          average_time_seconds: number | null
          coc_code: string | null
          failed_count: number | null
          mission_code: string | null
          mission_id: string | null
          mission_title: string | null
          module_name: string | null
          passed_count: number | null
          total_attempts: number | null
          unique_learners: number | null
        }
        Relationships: []
      }
    }
    Functions: {
      activate_tesda_source: {
        Args: { p_reason: string; p_source_id: string }
        Returns: {
          activated_at: string | null
          activated_by: string | null
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          document_storage_path: string | null
          edition: string | null
          effective_date: string | null
          id: string
          publication_date: string | null
          qualification_code: string
          source_reference: string
          status: Database["public"]["Enums"]["tesda_source_status"]
          title: string
          updated_at: string
          validation_notes: string | null
        }
        SetofOptions: {
          from: "*"
          to: "tesda_sources"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_account_removal_readiness: {
        Args: { p_user_id: string }
        Returns: Json
      }
      admin_change_user_role: {
        Args: {
          p_new_role: Database["public"]["Enums"]["user_role"]
          p_reason: string
          p_user_id: string
        }
        Returns: {
          avatar_url: string | null
          completed_missions: number
          course_section: string | null
          created_at: string
          current_level: number
          current_streak: number
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          email: string
          full_name: string
          id: string
          last_activity_at: string | null
          last_login_at: string | null
          learner_id: string | null
          learner_id_managed: boolean
          role: Database["public"]["Enums"]["user_role"]
          school: string | null
          show_on_leaderboard: boolean
          status: Database["public"]["Enums"]["account_status"]
          total_badges: number
          total_points: number
          total_xp: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_set_account_status: {
        Args: {
          p_reason?: string
          p_status: Database["public"]["Enums"]["account_status"]
          p_user_id: string
        }
        Returns: {
          avatar_url: string | null
          completed_missions: number
          course_section: string | null
          created_at: string
          current_level: number
          current_streak: number
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          email: string
          full_name: string
          id: string
          last_activity_at: string | null
          last_login_at: string | null
          learner_id: string | null
          learner_id_managed: boolean
          role: Database["public"]["Enums"]["user_role"]
          school: string | null
          show_on_leaderboard: boolean
          status: Database["public"]["Enums"]["account_status"]
          total_badges: number
          total_points: number
          total_xp: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      admin_update_system_setting: {
        Args: {
          p_description: string
          p_reason: string
          p_setting_key: string
          p_setting_value: Json
        }
        Returns: {
          description: string | null
          setting_key: string
          setting_value: Json
          updated_at: string
          updated_by: string
        }
        SetofOptions: {
          from: "*"
          to: "system_settings"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      append_attempt_action: {
        Args: {
          p_action_type: string
          p_attempt_id: string
          p_client_occurred_at: string
          p_sequence_number: number
          p_target: string
          p_value: Json
        }
        Returns: {
          action_type: string
          attempt_id: string
          client_occurred_at: string
          id: string
          recorded_at: string
          sequence_number: number
          target: string | null
          value: Json
        }
        SetofOptions: {
          from: "*"
          to: "attempt_actions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_rubric_version: {
        Args: {
          p_passing_rule: Json
          p_reason: string
          p_rubric_version_id: string
          p_scoring_method: string
        }
        Returns: {
          activity_version_id: string
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          id: string
          passing_rule: Json
          retired_at: string | null
          scoring_method: string
          status: Database["public"]["Enums"]["rubric_status"]
          tesda_source_id: string
          title: string
          updated_at: string
          version_number: number
        }
        SetofOptions: {
          from: "*"
          to: "rubric_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_tesda_source: {
        Args: { p_source_id: string; p_validation_notes: string }
        Returns: {
          activated_at: string | null
          activated_by: string | null
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          document_storage_path: string | null
          edition: string | null
          effective_date: string | null
          id: string
          publication_date: string | null
          qualification_code: string
          source_reference: string
          status: Database["public"]["Enums"]["tesda_source_status"]
          title: string
          updated_at: string
          validation_notes: string | null
        }
        SetofOptions: {
          from: "*"
          to: "tesda_sources"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      archive_class: {
        Args: { p_class_id: string; p_reason: string }
        Returns: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          class_code: string | null
          created_at: string
          created_by: string
          id: string
          instructor_id: string
          status: Database["public"]["Enums"]["class_status"]
          title: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "classes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      archive_instructor_quiz: {
        Args: { p_quiz_id: string; p_reason: string }
        Returns: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          coc_module_id: string | null
          created_at: string
          created_by: string
          description: string | null
          difficulty: string | null
          focus: string | null
          id: string
          instructor_id: string
          quiz_type: string | null
          title: string
          topic: string
          topic_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quizzes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      assign_activity: {
        Args: {
          p_activity_version_id: string
          p_assignment_type: Database["public"]["Enums"]["assignment_type"]
          p_available_at?: string
          p_class_id: string
          p_due_at?: string
          p_instructions?: string
          p_rubric_version_id: string
          p_title: string
        }
        Returns: {
          activity_version_id: string
          assigned_by: string
          assignment_type: Database["public"]["Enums"]["assignment_type"]
          attempts_allowed: number | null
          available_at: string | null
          class_id: string
          close_reason: string | null
          closed_at: string | null
          created_at: string
          due_at: string | null
          id: string
          instructions: string | null
          prerequisite_assignment_id: string | null
          retry_after_seconds: number | null
          retry_enabled: boolean
          rubric_version_id: string | null
          status: Database["public"]["Enums"]["assignment_status"]
          title: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "assignments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      assign_published_quiz: {
        Args: {
          p_attempts_allowed?: number
          p_available_at?: string
          p_class_id: string
          p_due_at?: string
          p_instructions?: string
          p_quiz_version_id: string
        }
        Returns: {
          assigned_by: string
          attempts_allowed: number | null
          available_at: string | null
          class_id: string
          close_reason: string | null
          closed_at: string | null
          created_at: string
          due_at: string | null
          id: string
          instructions: string | null
          quiz_version_id: string
          status: Database["public"]["Enums"]["assignment_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quiz_assignments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      begin_ai_quiz_generation: {
        Args: {
          p_input_context: Json
          p_model: string
          p_provider: string
          p_quiz_version_id: string
          p_requested_count: number
        }
        Returns: {
          completed_at: string | null
          failure_code: string | null
          generated_count: number
          id: string
          input_context: Json
          instructor_id: string
          model: string
          provider: string
          quiz_version_id: string
          requested_at: string
          requested_count: number
          status: Database["public"]["Enums"]["ai_generation_status"]
        }
        SetofOptions: {
          from: "*"
          to: "ai_quiz_generations"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cancel_class_roster_entry: {
        Args: { p_actor: string; p_entry_id: string }
        Returns: Json
      }
      close_assignment: {
        Args: { p_assignment_id: string; p_reason: string }
        Returns: {
          activity_version_id: string
          assigned_by: string
          assignment_type: Database["public"]["Enums"]["assignment_type"]
          attempts_allowed: number | null
          available_at: string | null
          class_id: string
          close_reason: string | null
          closed_at: string | null
          created_at: string
          due_at: string | null
          id: string
          instructions: string | null
          prerequisite_assignment_id: string | null
          retry_after_seconds: number | null
          retry_enabled: boolean
          rubric_version_id: string | null
          status: Database["public"]["Enums"]["assignment_status"]
          title: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "assignments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      complete_ai_quiz_draft: {
        Args: {
          p_actor: string
          p_generation_id: string
          p_items: Json
          p_model: string
          p_provider: string
          p_replace_item_id?: string
          p_replace_reason?: string
        }
        Returns: Json
      }
      complete_ai_quiz_generation: {
        Args: {
          p_actor_id: string
          p_generation_id: string
          p_items: Json
          p_model: string
          p_provider: string
        }
        Returns: number
      }
      configure_assignment_access: {
        Args: {
          p_assignment_id: string
          p_attempts_allowed?: number
          p_prerequisite_assignment_id?: string
          p_reason?: string
          p_retry_after_seconds?: number
          p_retry_enabled?: boolean
        }
        Returns: {
          activity_version_id: string
          assigned_by: string
          assignment_type: Database["public"]["Enums"]["assignment_type"]
          attempts_allowed: number | null
          available_at: string | null
          class_id: string
          close_reason: string | null
          closed_at: string | null
          created_at: string
          due_at: string | null
          id: string
          instructions: string | null
          prerequisite_assignment_id: string | null
          retry_after_seconds: number | null
          retry_enabled: boolean
          rubric_version_id: string | null
          status: Database["public"]["Enums"]["assignment_status"]
          title: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "assignments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_class: {
        Args: { p_class_code?: string; p_title: string }
        Returns: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          class_code: string | null
          created_at: string
          created_by: string
          id: string
          instructor_id: string
          status: Database["public"]["Enums"]["class_status"]
          title: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "classes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_instructor_quiz: {
        Args: {
          p_coc_module_id?: string
          p_description?: string
          p_difficulty?: string
          p_focus?: string
          p_instructions?: string
          p_module_ids?: string[]
          p_outcome_ids?: string[]
          p_quiz_type?: string
          p_result_release_mode?: string
          p_time_limit_minutes?: number
          p_title: string
          p_topic: string
          p_topic_id?: string
        }
        Returns: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          coc_module_id: string | null
          created_at: string
          created_by: string
          description: string | null
          difficulty: string | null
          focus: string | null
          id: string
          instructor_id: string
          quiz_type: string | null
          title: string
          topic: string
          topic_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quizzes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_learning_resource: {
        Args: {
          p_class_id: string
          p_description: string
          p_mime_type: string
          p_resource_id: string
          p_size_bytes: number
          p_storage_path: string
          p_title: string
        }
        Returns: {
          class_id: string
          created_at: string
          deleted_at: string | null
          deleted_by: string | null
          deletion_reason: string | null
          description: string | null
          id: string
          mime_type: string | null
          size_bytes: number | null
          status: Database["public"]["Enums"]["resource_status"]
          storage_bucket: string
          storage_path: string
          title: string
          uploaded_by: string
        }
        SetofOptions: {
          from: "*"
          to: "learning_resources"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_quiz_version: {
        Args: {
          p_change_summary?: string
          p_instructions?: string
          p_quiz_id: string
        }
        Returns: {
          change_summary: string | null
          created_at: string
          created_by: string
          id: string
          instructions: string | null
          published_at: string | null
          published_by: string | null
          quiz_id: string
          result_release_mode: string
          retired_at: string | null
          status: Database["public"]["Enums"]["content_version_status"]
          time_limit_minutes: number | null
          updated_at: string
          version_number: number
        }
        SetofOptions: {
          from: "*"
          to: "quiz_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      current_app_role: {
        Args: never
        Returns: Database["public"]["Enums"]["user_role"]
      }
      deactivate_class_membership: {
        Args: { p_membership_id: string; p_reason: string }
        Returns: {
          class_id: string
          created_at: string
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          enrolled_at: string
          enrolled_by: string
          id: string
          learner_id: string
          status: Database["public"]["Enums"]["membership_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "class_memberships"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      delete_learning_resource: {
        Args: { p_reason: string; p_resource_id: string }
        Returns: {
          class_id: string
          created_at: string
          deleted_at: string | null
          deleted_by: string | null
          deletion_reason: string | null
          description: string | null
          id: string
          mime_type: string | null
          size_bytes: number | null
          status: Database["public"]["Enums"]["resource_status"]
          storage_bucket: string
          storage_path: string
          title: string
          uploaded_by: string
        }
        SetofOptions: {
          from: "*"
          to: "learning_resources"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enroll_learner: {
        Args: { p_class_id: string; p_learner_id: string }
        Returns: {
          class_id: string
          created_at: string
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          enrolled_at: string
          enrolled_by: string
          id: string
          learner_id: string
          status: Database["public"]["Enums"]["membership_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "class_memberships"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      enroll_learner_by_email: {
        Args: { p_class_id: string; p_email: string }
        Returns: {
          class_id: string
          created_at: string
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          enrolled_at: string
          enrolled_by: string
          id: string
          learner_id: string
          status: Database["public"]["Enums"]["membership_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "class_memberships"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      evaluate_submitted_attempt: {
        Args: { p_attempt_id: string }
        Returns: {
          actor_id: string | null
          actor_role: Database["public"]["Enums"]["user_role"] | null
          attempt_id: string
          created_at: string
          criterion_values: Json
          evaluation_run_id: string | null
          id: string
          max_value: number | null
          outcome: Database["public"]["Enums"]["evaluation_outcome"]
          percentage: number | null
          reason: string | null
          remarks: string | null
          revision_number: number
          revision_type: Database["public"]["Enums"]["score_revision_type"]
          rubric_version_id: string
          supersedes_revision_id: string | null
          tesda_source_id: string
          total_value: number | null
        }
        SetofOptions: {
          from: "*"
          to: "score_revisions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fail_ai_quiz_generation: {
        Args: {
          p_actor_id: string
          p_failure_code: string
          p_generation_id: string
        }
        Returns: undefined
      }
      finalize_attempt: {
        Args: {
          p_attempt_id: string
          p_criterion_values: Json
          p_max_value: number
          p_outcome: Database["public"]["Enums"]["evaluation_outcome"]
          p_percentage: number
          p_reason?: string
          p_remarks?: string
          p_total_value: number
        }
        Returns: {
          actor_id: string | null
          actor_role: Database["public"]["Enums"]["user_role"] | null
          attempt_id: string
          created_at: string
          criterion_values: Json
          evaluation_run_id: string | null
          id: string
          max_value: number | null
          outcome: Database["public"]["Enums"]["evaluation_outcome"]
          percentage: number | null
          reason: string | null
          remarks: string | null
          revision_number: number
          revision_type: Database["public"]["Enums"]["score_revision_type"]
          rubric_version_id: string
          supersedes_revision_id: string | null
          tesda_source_id: string
          total_value: number | null
        }
        SetofOptions: {
          from: "*"
          to: "score_revisions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      gamification_level_for_points: {
        Args: { p_points: number }
        Returns: Json
      }
      get_admin_system_analytics: {
        Args: { p_from?: string; p_to?: string }
        Returns: Json
      }
      get_analytics_filter_options: { Args: never; Returns: Json }
      get_analytics_overview: { Args: { p_filters?: Json }; Returns: Json }
      get_available_learner_quizzes: { Args: never; Returns: Json }
      get_bypassed_activities: {
        Args: never
        Returns: {
          activity_title: string
          activity_version_id: string
          bypass_id: string
          class_id: string
          class_title: string
          granted_at: string
          instructions: string
          learner_payload: Json
          mission_code: string
          mission_id: string
          module_version_id: string
        }[]
      }
      get_class_performance: { Args: { p_filters?: Json }; Returns: Json }
      get_criteria_analytics: { Args: { p_filters?: Json }; Returns: Json }
      get_evaluation_queue: {
        Args: { p_filters?: Json; p_stage: string }
        Returns: Json
      }
      get_instructor_analytics: {
        Args: {
          p_class_id?: string
          p_coc_id?: string
          p_from?: string
          p_mission_id?: string
          p_to?: string
        }
        Returns: Json
      }
      get_learner_curriculum: { Args: never; Returns: Json }
      get_learner_learning_path: {
        Args: never
        Returns: {
          assessment_access_state: string
          assessment_assignment_id: string
          bypassed_practice: boolean
          coc_code: string
          coc_description: string
          coc_id: string
          coc_order: number
          coc_title: string
          estimated_time_minutes: number
          latest_attempt_id: string
          latest_attempt_status: string
          mission_code: string
          mission_description: string
          mission_difficulty: string
          mission_id: string
          mission_number: number
          mission_title: string
          released: boolean
          released_outcome: string
        }[]
      }
      get_learner_performance: { Args: { p_filters?: Json }; Returns: Json }
      get_learner_profile_analytics: {
        Args: { p_filters?: Json; p_learner: string }
        Returns: Json
      }
      get_learner_quiz_result: { Args: { p_attempt_id: string }; Returns: Json }
      get_learner_rewards: { Args: never; Returns: Json }
      get_level_from_xp: { Args: { p_xp: number }; Returns: number }
      get_mission_analytics: { Args: { p_filters?: Json }; Returns: Json }
      get_my_performance: { Args: never; Returns: Json }
      get_practice_learning_path: {
        Args: never
        Returns: {
          coc_code: string
          completed: boolean
          completed_missions: Json
          unlocked: boolean
        }[]
      }
      get_quiz_analytics: {
        Args: { p_filters?: Json; p_quiz_id: string }
        Returns: Json
      }
      get_rating: {
        Args: { p_score: number }
        Returns: Database["public"]["Enums"]["rating_type"]
      }
      grant_coc_bypass: {
        Args: {
          p_class_id: string
          p_learner_id: string
          p_module_version_id: string
          p_reason: string
          p_scope?: Json
        }
        Returns: {
          class_id: string
          created_at: string
          granted_at: string
          id: string
          instructor_id: string
          learner_id: string
          module_version_id: string
          reason: string
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          scope: Json
        }
        SetofOptions: {
          from: "*"
          to: "coc_bypasses"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      import_class_roster: {
        Args: {
          p_actor: string
          p_class_id: string
          p_file_name: string
          p_rows: Json
        }
        Returns: Json
      }
      instructor_deactivate_learner_account: {
        Args: { p_learner_id: string; p_reason: string }
        Returns: {
          avatar_url: string | null
          completed_missions: number
          course_section: string | null
          created_at: string
          current_level: number
          current_streak: number
          deactivated_at: string | null
          deactivated_by: string | null
          deactivation_reason: string | null
          email: string
          full_name: string
          id: string
          last_activity_at: string | null
          last_login_at: string | null
          learner_id: string | null
          learner_id_managed: boolean
          role: Database["public"]["Enums"]["user_role"]
          school: string | null
          show_on_leaderboard: boolean
          status: Database["public"]["Enums"]["account_status"]
          total_badges: number
          total_points: number
          total_xp: number
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "profiles"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      instructor_owns_class: { Args: { p_class_id: string }; Returns: boolean }
      is_active_user: { Args: never; Returns: boolean }
      is_admin: { Args: never; Returns: boolean }
      is_instructor: { Args: never; Returns: boolean }
      is_learner: { Args: never; Returns: boolean }
      is_own_user: { Args: { p_user_id: string }; Returns: boolean }
      is_staff: { Args: never; Returns: boolean }
      learner_coc_bypass_active: {
        Args: { p_coc: string; p_learner: string }
        Returns: boolean
      }
      learner_is_enrolled: {
        Args: { p_class_id: string; p_learner_id?: string }
        Returns: boolean
      }
      learner_module_states: {
        Args: { p_coc?: string; p_learner: string }
        Returns: {
          bypass_active: boolean
          coc_chain_unlocked: boolean
          coc_code: string
          coc_unlocked: boolean
          code: string
          completed: boolean
          missions_done: number
          missions_total: number
          module_id: string
          previous_module_id: string
          requirements_met: boolean
          sequence_order: number
          sequence_unlocked: boolean
          stored_completion: boolean
          stored_unlock: boolean
          title: string
          topics_done: number
          topics_total: number
          unlocked: boolean
        }[]
      }
      manage_curriculum_content: {
        Args: { p_action: string; p_actor: string; p_payload: Json }
        Returns: Json
      }
      manage_file_upload: {
        Args: { p_action: string; p_actor: string; p_spec: Json }
        Returns: Json
      }
      manage_homework: {
        Args: { p_action: string; p_actor: string; p_payload: Json }
        Returns: Json
      }
      manage_quiz_evaluation: {
        Args: { p_action: string; p_actor: string; p_payload: Json }
        Returns: Json
      }
      practice_begin_quiz: {
        Args: {
          p_coc: string
          p_id: string
          p_learner: string
          p_questions: Json
        }
        Returns: {
          answers: Json
          coc_code: string
          created_at: string
          id: string
          learner_id: string
          passed: boolean | null
          passing_percent: number
          questions: Json
          score: number | null
          source: string
          status: string
          submitted_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "practice_quiz_attempts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      practice_coc_unlocked: {
        Args: { p_coc: string; p_learner?: string }
        Returns: boolean
      }
      practice_completion_accepted: {
        Args: { p_mission: string; p_version: string }
        Returns: boolean
      }
      practice_conditions_met: {
        Args: { p_conditions: Json; p_state: Json }
        Returns: boolean
      }
      practice_mission_unlocked: {
        Args: { p_learner: string; p_mission: string }
        Returns: boolean
      }
      practice_record_failed_verification: {
        Args: { p_failure: string; p_learner: string; p_mission: string }
        Returns: undefined
      }
      practice_submit_quiz: {
        Args: { p_answers: Json; p_attempt: string; p_learner: string }
        Returns: {
          answers: Json
          coc_code: string
          created_at: string
          id: string
          learner_id: string
          passed: boolean | null
          passing_percent: number
          questions: Json
          score: number | null
          source: string
          status: string
          submitted_at: string | null
        }
        SetofOptions: {
          from: "*"
          to: "practice_quiz_attempts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      practice_verify_mission: {
        Args: { p_learner: string; p_mission: string }
        Returns: undefined
      }
      preview_class_roster: {
        Args: { p_actor: string; p_class_id: string; p_rows: Json }
        Returns: Json
      }
      process_expired_quiz_attempts: {
        Args: { p_actor: string; p_quiz_id?: string }
        Returns: number
      }
      publish_activity_version: {
        Args: { p_activity_version_id: string; p_reason: string }
        Returns: {
          created_at: string
          created_by: string
          delivery_mode: Database["public"]["Enums"]["activity_delivery_mode"]
          evaluator_config: Json
          id: string
          instructions: string | null
          learner_payload: Json
          mission_id: string
          module_version_id: string
          published_at: string | null
          published_by: string | null
          retired_at: string | null
          status: Database["public"]["Enums"]["content_version_status"]
          title: string
          updated_at: string
          version_number: number
        }
        SetofOptions: {
          from: "*"
          to: "activity_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      publish_and_assign_quiz: {
        Args: {
          p_class_ids: string[]
          p_due_at?: string
          p_instructions?: string
          p_quiz_version_id: string
        }
        Returns: Json
      }
      publish_module_version: {
        Args: { p_module_version_id: string; p_reason: string }
        Returns: {
          content_metadata: Json
          created_at: string
          created_by: string
          description: string | null
          id: string
          module_id: string
          published_at: string | null
          published_by: string | null
          retired_at: string | null
          source_trace: Json
          status: Database["public"]["Enums"]["content_version_status"]
          tesda_source_id: string
          title: string
          updated_at: string
          version_number: number
        }
        SetofOptions: {
          from: "*"
          to: "module_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      publish_quiz_version: {
        Args: { p_quiz_version_id: string; p_reason?: string }
        Returns: {
          change_summary: string | null
          created_at: string
          created_by: string
          id: string
          instructions: string | null
          published_at: string | null
          published_by: string | null
          quiz_id: string
          result_release_mode: string
          retired_at: string | null
          status: Database["public"]["Enums"]["content_version_status"]
          time_limit_minutes: number | null
          updated_at: string
          version_number: number
        }
        SetofOptions: {
          from: "*"
          to: "quiz_versions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      quiz_evaluation_queue_items: {
        Args: { p_filters?: Json; p_stage: string }
        Returns: Json
      }
      record_attempt_evaluation: {
        Args: {
          p_actor: string
          p_attempt_id: string
          p_criterion_overrides: Json
          p_note: string
          p_reason: string
        }
        Returns: Json
      }
      record_provisional_evaluation: {
        Args: {
          p_attempt_id: string
          p_criterion_results: Json
          p_evaluation_run_id: string
          p_max_value: number
          p_outcome: Database["public"]["Enums"]["evaluation_outcome"]
          p_percentage: number
          p_remarks?: string
          p_total_value: number
        }
        Returns: {
          actor_id: string | null
          actor_role: Database["public"]["Enums"]["user_role"] | null
          attempt_id: string
          created_at: string
          criterion_values: Json
          evaluation_run_id: string | null
          id: string
          max_value: number | null
          outcome: Database["public"]["Enums"]["evaluation_outcome"]
          percentage: number | null
          reason: string | null
          remarks: string | null
          revision_number: number
          revision_type: Database["public"]["Enums"]["score_revision_type"]
          rubric_version_id: string
          supersedes_revision_id: string | null
          tesda_source_id: string
          total_value: number | null
        }
        SetofOptions: {
          from: "*"
          to: "score_revisions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      refresh_learner_unlocks: {
        Args: { p_learner: string }
        Returns: undefined
      }
      register_tesda_source: {
        Args: {
          p_document_storage_path?: string
          p_edition: string
          p_effective_date: string
          p_publication_date: string
          p_qualification_code: string
          p_source_reference: string
          p_title: string
          p_validation_notes?: string
        }
        Returns: {
          activated_at: string | null
          activated_by: string | null
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          document_storage_path: string | null
          edition: string | null
          effective_date: string | null
          id: string
          publication_date: string | null
          qualification_code: string
          source_reference: string
          status: Database["public"]["Enums"]["tesda_source_status"]
          title: string
          updated_at: string
          validation_notes: string | null
        }
        SetofOptions: {
          from: "*"
          to: "tesda_sources"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      release_attempt: {
        Args: { p_attempt_id: string; p_release_reason?: string }
        Returns: {
          attempt_id: string
          created_at: string
          id: string
          is_current: boolean
          release_number: number
          release_reason: string | null
          released_at: string
          released_by: string
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          score_revision_id: string
        }
        SetofOptions: {
          from: "*"
          to: "result_releases"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      remove_quiz_item: {
        Args: { p_item_id: string; p_reason: string }
        Returns: {
          ai_generation_id: string | null
          correct_answer: Json
          created_at: string
          created_by: string
          explanation: string | null
          id: string
          item_code: string
          item_type: Database["public"]["Enums"]["quiz_item_type"]
          max_words: number | null
          min_words: number | null
          options: Json
          order_index: number
          origin: Database["public"]["Enums"]["quiz_item_origin"]
          points: number
          prompt: string
          quiz_version_id: string
          removal_reason: string | null
          removed_at: string | null
          removed_by: string | null
          review_notes: string | null
          review_status: Database["public"]["Enums"]["quiz_item_review_status"]
          reviewed_at: string | null
          reviewed_by: string | null
          rubric: Json | null
          scenario: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quiz_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      reorder_quiz_items: {
        Args: { p_item_ids: string[]; p_quiz_version_id: string }
        Returns: undefined
      }
      review_quiz_item: {
        Args: {
          p_decision: Database["public"]["Enums"]["quiz_item_review_status"]
          p_item_id: string
          p_notes?: string
        }
        Returns: {
          ai_generation_id: string | null
          correct_answer: Json
          created_at: string
          created_by: string
          explanation: string | null
          id: string
          item_code: string
          item_type: Database["public"]["Enums"]["quiz_item_type"]
          max_words: number | null
          min_words: number | null
          options: Json
          order_index: number
          origin: Database["public"]["Enums"]["quiz_item_origin"]
          points: number
          prompt: string
          quiz_version_id: string
          removal_reason: string | null
          removed_at: string | null
          removed_by: string | null
          review_notes: string | null
          review_status: Database["public"]["Enums"]["quiz_item_review_status"]
          reviewed_at: string | null
          reviewed_by: string | null
          rubric: Json | null
          scenario: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quiz_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      save_learner_quiz_answer: {
        Args: { p_answer: string; p_attempt_id: string; p_item_id: string }
        Returns: Json
      }
      search_learners: {
        Args: {
          p_class_id?: string
          p_limit?: number
          p_offset?: number
          p_query?: string
          p_sort?: string
          p_status?: string
        }
        Returns: Json
      }
      set_learner_student_id: {
        Args: { p_actor: string; p_learner_id: string; p_student_id: string }
        Returns: Json
      }
      set_quiz_assignment_deadline: {
        Args: {
          p_actor: string
          p_assignment_id: string
          p_close_now?: boolean
          p_deadline: string
          p_reopen?: boolean
        }
        Returns: {
          assigned_by: string
          attempts_allowed: number | null
          available_at: string | null
          class_id: string
          close_reason: string | null
          closed_at: string | null
          created_at: string
          due_at: string | null
          id: string
          instructions: string | null
          quiz_version_id: string
          status: Database["public"]["Enums"]["assignment_status"]
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quiz_assignments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start_attempt: {
        Args: { p_assignment_id: string; p_client_start_key: string }
        Returns: {
          activity_version_id: string
          assignment_id: string
          class_id: string
          client_start_key: string
          created_at: string
          elapsed_time_seconds: number | null
          evaluated_at: string | null
          finalized_at: string | null
          id: string
          learner_id: string
          legacy_mission_result_id: string | null
          released_at: string | null
          rubric_version_id: string | null
          started_at: string
          status: Database["public"]["Enums"]["attempt_status"]
          submission_key: string | null
          submitted_at: string | null
          tesda_source_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "attempts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      start_learner_quiz: {
        Args: { p_assignment_id: string; p_client_start_key: string }
        Returns: Json
      }
      submit_attempt: {
        Args: {
          p_attempt_id: string
          p_elapsed_time_seconds: number
          p_submission_key: string
        }
        Returns: {
          activity_version_id: string
          assignment_id: string
          class_id: string
          client_start_key: string
          created_at: string
          elapsed_time_seconds: number | null
          evaluated_at: string | null
          finalized_at: string | null
          id: string
          learner_id: string
          legacy_mission_result_id: string | null
          released_at: string | null
          rubric_version_id: string | null
          started_at: string
          status: Database["public"]["Enums"]["attempt_status"]
          submission_key: string | null
          submitted_at: string | null
          tesda_source_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "attempts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      submit_learner_quiz: {
        Args: { p_attempt_id: string; p_submission_key: string }
        Returns: Json
      }
      update_instructor_quiz: {
        Args: {
          p_coc_module_id?: string
          p_description?: string
          p_difficulty?: string
          p_focus?: string
          p_instructions?: string
          p_module_ids?: string[]
          p_outcome_ids?: string[]
          p_quiz_id: string
          p_quiz_type?: string
          p_result_release_mode?: string
          p_time_limit_minutes?: number
          p_title: string
          p_topic: string
          p_topic_id?: string
        }
        Returns: {
          archive_reason: string | null
          archived_at: string | null
          archived_by: string | null
          coc_module_id: string | null
          created_at: string
          created_by: string
          description: string | null
          difficulty: string | null
          focus: string | null
          id: string
          instructor_id: string
          quiz_type: string | null
          title: string
          topic: string
          topic_id: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quizzes"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_quiz_item: {
        Args: {
          p_correct_answer: Json
          p_explanation?: string
          p_item_id?: string
          p_item_type: Database["public"]["Enums"]["quiz_item_type"]
          p_max_words?: number
          p_min_words?: number
          p_options: Json
          p_order_index?: number
          p_points?: number
          p_prompt: string
          p_quiz_version_id: string
          p_rubric?: Json
          p_scenario?: string
        }
        Returns: {
          ai_generation_id: string | null
          correct_answer: Json
          created_at: string
          created_by: string
          explanation: string | null
          id: string
          item_code: string
          item_type: Database["public"]["Enums"]["quiz_item_type"]
          max_words: number | null
          min_words: number | null
          options: Json
          order_index: number
          origin: Database["public"]["Enums"]["quiz_item_origin"]
          points: number
          prompt: string
          quiz_version_id: string
          removal_reason: string | null
          removed_at: string | null
          removed_by: string | null
          review_notes: string | null
          review_status: Database["public"]["Enums"]["quiz_item_review_status"]
          reviewed_at: string | null
          reviewed_by: string | null
          rubric: Json | null
          scenario: string | null
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "quiz_items"
          isOneToOne: true
          isSetofReturn: false
        }
      }
    }
    Enums: {
      account_status:
        | "active"
        | "inactive"
        | "suspended"
        | "pending"
        | "deactivated"
      activity_delivery_mode: "practice" | "assessment" | "both"
      ai_generation_status: "requested" | "completed" | "failed"
      assignment_status: "active" | "closed"
      assignment_type: "practice" | "assessment"
      attempt_status:
        | "in_progress"
        | "submitted"
        | "evaluated"
        | "under_review"
        | "finalized"
        | "released"
      class_status: "active" | "archived"
      competency_status: "competent" | "not_yet_competent"
      condition_type:
        | "mission_count"
        | "coc_completion"
        | "streak"
        | "score_threshold"
        | "time_based"
        | "perfect_score"
        | "no_mistake"
        | "special"
      content_publication_status:
        | "draft"
        | "submitted"
        | "needs_revision"
        | "evaluated"
        | "finalized"
        | "approved"
        | "published"
        | "unpublished"
        | "archived"
      content_version_status: "draft" | "published" | "retired"
      criterion_observation:
        | "satisfied"
        | "not_satisfied"
        | "not_evaluated"
        | "requires_review"
      difficulty_level: "beginner" | "intermediate" | "advanced"
      evaluation_outcome:
        | "pending_tesda_validation"
        | "competent"
        | "not_yet_competent"
      leaderboard_type: "overall" | "coc" | "mission" | "weekly" | "monthly"
      membership_status: "active" | "deactivated"
      mission_status: "draft" | "published" | "archived"
      mission_type:
        | "identification"
        | "drag_and_drop"
        | "configuration_form"
        | "step_procedure"
        | "troubleshooting"
        | "checklist"
        | "matching"
      notification_type:
        | "mission"
        | "badge"
        | "achievement"
        | "progress"
        | "system"
        | "admin_message"
      progress_status:
        | "locked"
        | "not_started"
        | "in_progress"
        | "completed"
        | "failed"
      quiz_attempt_status: "in_progress" | "submitted" | "completed"
      quiz_item_origin: "instructor_authored" | "ai_generated_draft"
      quiz_item_review_status: "draft" | "approved" | "rejected"
      quiz_item_type:
        | "multiple_choice"
        | "true_false"
        | "identification"
        | "scenario_based"
        | "scenario_essay"
      rating_type:
        | "excellent"
        | "very_good"
        | "good"
        | "needs_improvement"
        | "poor"
      report_type:
        | "individual_learner"
        | "class_summary"
        | "coc_performance"
        | "mission_result"
        | "competency_achievement"
        | "progress_report"
        | "pass_fail_summary"
        | "analytics_dashboard"
      resource_status: "active" | "deleted"
      rubric_status:
        | "pending_tesda_validation"
        | "draft"
        | "approved"
        | "retired"
      score_revision_type:
        | "automated_provisional"
        | "instructor_adjustment"
        | "instructor_final"
      task_type:
        | "select_image"
        | "drag_drop"
        | "arrange_sequence"
        | "form_input"
        | "matching"
        | "checklist"
        | "decision_tree"
      tesda_source_status:
        | "pending_tesda_validation"
        | "approved"
        | "active"
        | "superseded"
        | "archived"
      user_role: "learner" | "instructor" | "admin" | "legacy_instructor_admin"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      account_status: [
        "active",
        "inactive",
        "suspended",
        "pending",
        "deactivated",
      ],
      activity_delivery_mode: ["practice", "assessment", "both"],
      ai_generation_status: ["requested", "completed", "failed"],
      assignment_status: ["active", "closed"],
      assignment_type: ["practice", "assessment"],
      attempt_status: [
        "in_progress",
        "submitted",
        "evaluated",
        "under_review",
        "finalized",
        "released",
      ],
      class_status: ["active", "archived"],
      competency_status: ["competent", "not_yet_competent"],
      condition_type: [
        "mission_count",
        "coc_completion",
        "streak",
        "score_threshold",
        "time_based",
        "perfect_score",
        "no_mistake",
        "special",
      ],
      content_publication_status: [
        "draft",
        "submitted",
        "needs_revision",
        "evaluated",
        "finalized",
        "approved",
        "published",
        "unpublished",
        "archived",
      ],
      content_version_status: ["draft", "published", "retired"],
      criterion_observation: [
        "satisfied",
        "not_satisfied",
        "not_evaluated",
        "requires_review",
      ],
      difficulty_level: ["beginner", "intermediate", "advanced"],
      evaluation_outcome: [
        "pending_tesda_validation",
        "competent",
        "not_yet_competent",
      ],
      leaderboard_type: ["overall", "coc", "mission", "weekly", "monthly"],
      membership_status: ["active", "deactivated"],
      mission_status: ["draft", "published", "archived"],
      mission_type: [
        "identification",
        "drag_and_drop",
        "configuration_form",
        "step_procedure",
        "troubleshooting",
        "checklist",
        "matching",
      ],
      notification_type: [
        "mission",
        "badge",
        "achievement",
        "progress",
        "system",
        "admin_message",
      ],
      progress_status: [
        "locked",
        "not_started",
        "in_progress",
        "completed",
        "failed",
      ],
      quiz_attempt_status: ["in_progress", "submitted", "completed"],
      quiz_item_origin: ["instructor_authored", "ai_generated_draft"],
      quiz_item_review_status: ["draft", "approved", "rejected"],
      quiz_item_type: [
        "multiple_choice",
        "true_false",
        "identification",
        "scenario_based",
        "scenario_essay",
      ],
      rating_type: [
        "excellent",
        "very_good",
        "good",
        "needs_improvement",
        "poor",
      ],
      report_type: [
        "individual_learner",
        "class_summary",
        "coc_performance",
        "mission_result",
        "competency_achievement",
        "progress_report",
        "pass_fail_summary",
        "analytics_dashboard",
      ],
      resource_status: ["active", "deleted"],
      rubric_status: [
        "pending_tesda_validation",
        "draft",
        "approved",
        "retired",
      ],
      score_revision_type: [
        "automated_provisional",
        "instructor_adjustment",
        "instructor_final",
      ],
      task_type: [
        "select_image",
        "drag_drop",
        "arrange_sequence",
        "form_input",
        "matching",
        "checklist",
        "decision_tree",
      ],
      tesda_source_status: [
        "pending_tesda_validation",
        "approved",
        "active",
        "superseded",
        "archived",
      ],
      user_role: ["learner", "instructor", "admin", "legacy_instructor_admin"],
    },
  },
} as const

