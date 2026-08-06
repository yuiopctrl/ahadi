export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      audit_logs: {
        Row: {
          action: string
          actor_platform_user_id: string | null
          actor_user_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string
          event_id: string | null
          id: number
          ip_address: unknown | null
          new_values: Json | null
          old_values: Json | null
          reason: string | null
          request_id: string | null
          tenant_id: string | null
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_platform_user_id?: string | null
          actor_user_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          event_id?: string | null
          id?: never
          ip_address?: unknown | null
          new_values?: Json | null
          old_values?: Json | null
          reason?: string | null
          request_id?: string | null
          tenant_id?: string | null
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_platform_user_id?: string | null
          actor_user_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          event_id?: string | null
          id?: never
          ip_address?: unknown | null
          new_values?: Json | null
          old_values?: Json | null
          reason?: string | null
          request_id?: string | null
          tenant_id?: string | null
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_actor_platform_user_id_fkey"
            columns: ["actor_platform_user_id"]
            isOneToOne: false
            referencedRelation: "platform_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      event_user_assignments: {
        Row: {
          access_level: string
          assigned_by: string
          created_at: string
          event_id: string
          id: string
          tenant_id: string
          tenant_user_id: string
        }
        Insert: {
          access_level: string
          assigned_by: string
          created_at?: string
          event_id: string
          id?: string
          tenant_id: string
          tenant_user_id: string
        }
        Update: {
          access_level?: string
          assigned_by?: string
          created_at?: string
          event_id?: string
          id?: string
          tenant_id?: string
          tenant_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_user_assignments_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_user_assignments_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_user_assignments_tenant_user_id_fkey"
            columns: ["tenant_user_id"]
            isOneToOne: false
            referencedRelation: "tenant_users"
            referencedColumns: ["id"]
          },
        ]
      }
      events: {
        Row: {
          closed_at: string | null
          code: string
          created_at: string
          created_by: string
          custom_event_type: string | null
          description: string | null
          event_date: string | null
          event_type: string
          id: string
          name: string
          payment_instructions: string | null
          pledge_deadline: string | null
          status: string
          target_amount: number | null
          tenant_id: string
          updated_at: string
          venue: string | null
        }
        Insert: {
          closed_at?: string | null
          code: string
          created_at?: string
          created_by: string
          custom_event_type?: string | null
          description?: string | null
          event_date?: string | null
          event_type: string
          id?: string
          name: string
          payment_instructions?: string | null
          pledge_deadline?: string | null
          status?: string
          target_amount?: number | null
          tenant_id: string
          updated_at?: string
          venue?: string | null
        }
        Update: {
          closed_at?: string | null
          code?: string
          created_at?: string
          created_by?: string
          custom_event_type?: string | null
          description?: string | null
          event_date?: string | null
          event_type?: string
          id?: string
          name?: string
          payment_instructions?: string | null
          pledge_deadline?: string | null
          status?: string
          target_amount?: number | null
          tenant_id?: string
          updated_at?: string
          venue?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "events_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      onboarding_requests: {
        Row: {
          created_at: string
          id: string
          idempotency_key: string
          request_hash: string
          result: Json | null
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          idempotency_key: string
          request_hash: string
          result?: Json | null
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          idempotency_key?: string
          request_hash?: string
          result?: Json | null
          user_id?: string
        }
        Relationships: []
      }
      permissions: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          name: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          name: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          name?: string
        }
        Relationships: []
      }
      platform_users: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          role: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          role: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          role?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string | null
          full_name: string
          id: string
          last_seen_at: string | null
          onboarding_completed_at: string | null
          phone_e164: string
          preferred_language: string
          status: string
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string
          id: string
          last_seen_at?: string | null
          onboarding_completed_at?: string | null
          phone_e164: string
          preferred_language?: string
          status?: string
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          full_name?: string
          id?: string
          last_seen_at?: string | null
          onboarding_completed_at?: string | null
          phone_e164?: string
          preferred_language?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      role_permissions: {
        Row: {
          created_at: string
          permission_id: string
          role_id: string
        }
        Insert: {
          created_at?: string
          permission_id: string
          role_id: string
        }
        Update: {
          created_at?: string
          permission_id?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          code: string
          created_at: string
          description: string | null
          id: string
          is_system: boolean
          name: string
          scope: string
          tenant_id: string | null
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          name: string
          scope: string
          tenant_id?: string | null
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_system?: boolean
          name?: string
          scope?: string
          tenant_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "roles_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_plans: {
        Row: {
          billing_interval: string
          code: string
          created_at: string
          currency: string
          description: string
          display_order: number
          features: Json
          id: string
          included_sms: number
          is_active: boolean
          is_public: boolean
          max_active_events: number
          max_members: number
          max_users: number
          name: string
          price_amount: number
          trial_days: number
          updated_at: string
        }
        Insert: {
          billing_interval: string
          code: string
          created_at?: string
          currency?: string
          description: string
          display_order?: number
          features?: Json
          id?: string
          included_sms?: number
          is_active?: boolean
          is_public?: boolean
          max_active_events: number
          max_members: number
          max_users: number
          name: string
          price_amount?: number
          trial_days?: number
          updated_at?: string
        }
        Update: {
          billing_interval?: string
          code?: string
          created_at?: string
          currency?: string
          description?: string
          display_order?: number
          features?: Json
          id?: string
          included_sms?: number
          is_active?: boolean
          is_public?: boolean
          max_active_events?: number
          max_members?: number
          max_users?: number
          name?: string
          price_amount?: number
          trial_days?: number
          updated_at?: string
        }
        Relationships: []
      }
      tenant_settings: {
        Row: {
          bank_payment_instructions: string | null
          created_at: string
          default_event_type: string | null
          default_pledge_deadline_days: number | null
          logo_url: string | null
          mobile_money_instructions: string | null
          primary_color: string | null
          receipt_prefix: string
          settings: Json
          sms_sender_name: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          bank_payment_instructions?: string | null
          created_at?: string
          default_event_type?: string | null
          default_pledge_deadline_days?: number | null
          logo_url?: string | null
          mobile_money_instructions?: string | null
          primary_color?: string | null
          receipt_prefix?: string
          settings?: Json
          sms_sender_name?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          bank_payment_instructions?: string | null
          created_at?: string
          default_event_type?: string | null
          default_pledge_deadline_days?: number | null
          logo_url?: string | null
          mobile_money_instructions?: string | null
          primary_color?: string | null
          receipt_prefix?: string
          settings?: Json
          sms_sender_name?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_settings_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: true
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_subscriptions: {
        Row: {
          cancellation_reason: string | null
          cancelled_at: string | null
          created_at: string
          current_period_end: string | null
          current_period_start: string
          id: string
          plan_id: string
          plan_snapshot: Json
          starts_at: string
          status: string
          tenant_id: string
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string
          id?: string
          plan_id: string
          plan_snapshot: Json
          starts_at?: string
          status: string
          tenant_id: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          cancellation_reason?: string | null
          cancelled_at?: string | null
          created_at?: string
          current_period_end?: string | null
          current_period_start?: string
          id?: string
          plan_id?: string
          plan_snapshot?: Json
          starts_at?: string
          status?: string
          tenant_id?: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "subscription_plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_subscriptions_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_user_roles: {
        Row: {
          assigned_by: string | null
          created_at: string
          role_id: string
          tenant_user_id: string
        }
        Insert: {
          assigned_by?: string | null
          created_at?: string
          role_id: string
          tenant_user_id: string
        }
        Update: {
          assigned_by?: string | null
          created_at?: string
          role_id?: string
          tenant_user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_user_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_user_roles_tenant_user_id_fkey"
            columns: ["tenant_user_id"]
            isOneToOne: false
            referencedRelation: "tenant_users"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_users: {
        Row: {
          created_at: string
          id: string
          invited_by: string | null
          is_owner: boolean
          joined_at: string | null
          status: string
          tenant_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          invited_by?: string | null
          is_owner?: boolean
          joined_at?: string | null
          status?: string
          tenant_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          invited_by?: string | null
          is_owner?: boolean
          joined_at?: string | null
          status?: string
          tenant_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_users_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenants: {
        Row: {
          code: string
          country_code: string
          created_at: string
          created_by: string
          currency: string
          email: string | null
          id: string
          legal_name: string | null
          name: string
          phone_e164: string
          slug: string
          status: string
          suspended_at: string | null
          suspension_reason: string | null
          timezone: string
          updated_at: string
        }
        Insert: {
          code?: string
          country_code?: string
          created_at?: string
          created_by: string
          currency?: string
          email?: string | null
          id?: string
          legal_name?: string | null
          name: string
          phone_e164: string
          slug: string
          status?: string
          suspended_at?: string | null
          suspension_reason?: string | null
          timezone?: string
          updated_at?: string
        }
        Update: {
          code?: string
          country_code?: string
          created_at?: string
          created_by?: string
          currency?: string
          email?: string | null
          id?: string
          legal_name?: string | null
          name?: string
          phone_e164?: string
          slug?: string
          status?: string
          suspended_at?: string | null
          suspension_reason?: string | null
          timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      active_event_count: {
        Args: { p_tenant_id: string }
        Returns: number
      }
      active_user_count: {
        Args: { p_tenant_id: string }
        Returns: number
      }
      can_access_event: {
        Args: { event_uuid: string }
        Returns: boolean
      }
      can_manage_event: {
        Args: { event_uuid: string }
        Returns: boolean
      }
      generate_tenant_code: {
        Args: Record<PropertyKey, never>
        Returns: string
      }
      generate_unique_tenant_slug: {
        Args: { tenant_name: string }
        Returns: string
      }
      has_platform_permission: {
        Args: { permission_code: string }
        Returns: boolean
      }
      has_tenant_permission: {
        Args: { permission_code: string; tenant_uuid: string }
        Returns: boolean
      }
      included_sms_allowance: {
        Args: { p_tenant_id: string }
        Returns: number
      }
      is_active_tenant_member: {
        Args: { tenant_uuid: string }
        Returns: boolean
      }
      is_platform_user: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      is_tenant_member: {
        Args: { tenant_uuid: string }
        Returns: boolean
      }
      is_weak_pin: {
        Args: { p_pin: string }
        Returns: boolean
      }
      member_count: {
        Args: { p_tenant_id: string }
        Returns: number
      }
      next_event_code: {
        Args: { p_tenant_id: string }
        Returns: string
      }
      normalize_tz_phone: {
        Args: { raw_phone: string }
        Returns: string
      }
      rpc_complete_tenant_onboarding: {
        Args: {
          p_event_date?: string
          p_event_type?: string
          p_first_event_name?: string
          p_idempotency_key?: string
          p_plan_code: string
          p_pledge_deadline?: string
          p_target_amount?: number
          p_tenant_email?: string
          p_tenant_name: string
          p_tenant_phone: string
          p_venue?: string
        }
        Returns: Json
      }
      rpc_create_event: {
        Args: {
          p_event_date?: string
          p_event_type: string
          p_name: string
          p_pledge_deadline?: string
          p_target_amount?: number
          p_tenant_id: string
          p_venue?: string
        }
        Returns: Json
      }
      rpc_get_my_context: {
        Args: Record<PropertyKey, never>
        Returns: Json
      }
      rpc_get_tenant_context: {
        Args: { p_tenant_id: string }
        Returns: Json
      }
      rpc_has_my_pin: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      rpc_set_my_pin: {
        Args: { p_pin: string }
        Returns: Json
      }
      rpc_verify_my_pin: {
        Args: { p_pin: string }
        Returns: Json
      }
      slugify: {
        Args: { value: string }
        Returns: string
      }
      write_audit_log: {
        Args: {
          p_action: string
          p_entity_id?: string
          p_entity_type: string
          p_event_id?: string
          p_new_values?: Json
          p_old_values?: Json
          p_reason?: string
          p_tenant_id: string
        }
        Returns: number
      }
    }
    Enums: {
      [_ in never]: never
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
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
} as const

