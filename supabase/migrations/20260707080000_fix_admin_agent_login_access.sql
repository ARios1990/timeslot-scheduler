/*
  Migration: 20260707080000_fix_admin_agent_login_access.sql

  Purpose:
  Fix admin/agent login access for the TimeSlot Scheduler app.

  Main rules:
  - Admin users use profiles.role = 'admin'
  - Admin users do NOT need profiles.agent_id
  - Agent users use profiles.role = 'agent'
  - Agent users MUST have profiles.agent_id linked to public.agents.id
  - New Auth users automatically get a public.profiles row
  - New users default to role = 'agent' and agent_id = null
*/

BEGIN;

-- =========================================================
-- 1. Safety check
-- =========================================================

DO $$
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'Missing table: public.profiles. Run the earlier scheduling schema migrations first.';
  END IF;

  IF to_regclass('public.agents') IS NULL THEN
    RAISE EXCEPTION 'Missing table: public.agents. Run the earlier scheduling schema migrations first.';
  END IF;

  IF to_regclass('public.teams') IS NULL THEN
    RAISE EXCEPTION 'Missing table: public.teams. Run the earlier scheduling schema migrations first.';
  END IF;
END $$;

-- =========================================================
-- 2. Make sure profiles has the required columns
-- =========================================================

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS email text;

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS display_name text;

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS role text DEFAULT 'agent';

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS agent_id uuid;

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Add agent_id foreign key if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'profiles_agent_id_fkey'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_agent_id_fkey
    FOREIGN KEY (agent_id)
    REFERENCES public.agents(id)
    ON DELETE SET NULL;
  END IF;
END $$;

-- Add role check constraint if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'profiles_role_check'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_role_check
    CHECK (role IN ('admin', 'agent'));
  END IF;
END $$;

-- Normalize bad/null roles
UPDATE public.profiles
SET role = 'agent'
WHERE role IS NULL
   OR role NOT IN ('admin', 'agent');

-- =========================================================
-- 3. Updated_at trigger helper
-- =========================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;

CREATE TRIGGER set_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================================================
-- 4. Auto-create profile when a Supabase Auth user is created
-- =========================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    email,
    display_name,
    role,
    agent_id,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(
      NEW.raw_user_meta_data ->> 'display_name',
      split_part(NEW.email, '@', 1)
    ),
    COALESCE(
      NULLIF(NEW.raw_user_meta_data ->> 'role', ''),
      'agent'
    ),
    NULL,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET
    email = EXCLUDED.email,
    display_name = COALESCE(public.profiles.display_name, EXCLUDED.display_name),
    updated_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- =========================================================
-- 5. Backfill missing profiles for existing Auth users
-- =========================================================

INSERT INTO public.profiles (
  id,
  email,
  display_name,
  role,
  agent_id,
  created_at,
  updated_at
)
SELECT
  u.id,
  u.email,
  COALESCE(
    u.raw_user_meta_data ->> 'display_name',
    split_part(u.email, '@', 1)
  ) AS display_name,
  'agent' AS role,
  NULL AS agent_id,
  now(),
  now()
FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1
  FROM public.profiles p
  WHERE p.id = u.id
);

-- =========================================================
-- 6. Make Masters Ready admin account admin if it exists
-- =========================================================

UPDATE public.profiles
SET
  role = 'admin',
  agent_id = NULL,
  display_name = COALESCE(display_name, 'Antonio Admin'),
  updated_at = now()
WHERE email = 'mastersreadyservices2025@gmail.com';

-- =========================================================
-- 7. Helper functions for RLS and app access checks
-- =========================================================

CREATE OR REPLACE FUNCTION public.current_profile_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT p.role
      FROM public.profiles p
      WHERE p.id = auth.uid()
      LIMIT 1
    ),
    'agent'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.current_profile_role() = 'admin', false);
$$;

CREATE OR REPLACE FUNCTION public.current_agent_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.agent_id
  FROM public.profiles p
  WHERE p.id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_team_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.team_id
  FROM public.profiles p
  JOIN public.agents a ON a.id = p.agent_id
  WHERE p.id = auth.uid()
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.current_profile_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_agent_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_team_id() TO authenticated;

-- =========================================================
-- 8. Enable RLS
-- =========================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF to_regclass('public.companies') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY';
  END IF;

  IF to_regclass('public.company_teams') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.company_teams ENABLE ROW LEVEL SECURITY';
  END IF;

  IF to_regclass('public.company_locations') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.company_locations ENABLE ROW LEVEL SECURITY';
  END IF;

  IF to_regclass('public.time_slots') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.time_slots ENABLE ROW LEVEL SECURITY';
  END IF;
END $$;

-- =========================================================
-- 9. Profiles policies
-- =========================================================

DROP POLICY IF EXISTS "profiles_select_self_or_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_all" ON public.profiles;

CREATE POLICY "profiles_select_self_or_admin"
ON public.profiles
FOR SELECT
TO authenticated
USING (
  id = auth.uid()
  OR public.is_admin()
);

CREATE POLICY "profiles_admin_all"
ON public.profiles
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- =========================================================
-- 10. Teams policies
-- =========================================================

DROP POLICY IF EXISTS "teams_select_admin_or_own_team" ON public.teams;
DROP POLICY IF EXISTS "teams_admin_all" ON public.teams;

CREATE POLICY "teams_select_admin_or_own_team"
ON public.teams
FOR SELECT
TO authenticated
USING (
  public.is_admin()
  OR id = public.current_team_id()
);

CREATE POLICY "teams_admin_all"
ON public.teams
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- =========================================================
-- 11. Agents policies
-- =========================================================

DROP POLICY IF EXISTS "agents_select_admin_or_own_team" ON public.agents;
DROP POLICY IF EXISTS "agents_admin_all" ON public.agents;

CREATE POLICY "agents_select_admin_or_own_team"
ON public.agents
FOR SELECT
TO authenticated
USING (
  public.is_admin()
  OR id = public.current_agent_id()
  OR team_id = public.current_team_id()
);

CREATE POLICY "agents_admin_all"
ON public.agents
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- =========================================================
-- 12. Company/team/time slot policies
-- =========================================================

DO $$
BEGIN
  IF to_regclass('public.company_teams') IS NOT NULL THEN
    DROP POLICY IF EXISTS "company_teams_select_admin_or_own_team" ON public.company_teams;
    DROP POLICY IF EXISTS "company_teams_admin_all" ON public.company_teams;

    CREATE POLICY "company_teams_select_admin_or_own_team"
    ON public.company_teams
    FOR SELECT
    TO authenticated
    USING (
      public.is_admin()
      OR team_id = public.current_team_id()
    );

    CREATE POLICY "company_teams_admin_all"
    ON public.company_teams
    FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.companies') IS NOT NULL
     AND to_regclass('public.company_teams') IS NOT NULL THEN

    DROP POLICY IF EXISTS "companies_select_admin_or_assigned_team" ON public.companies;
    DROP POLICY IF EXISTS "companies_admin_all" ON public.companies;

    CREATE POLICY "companies_select_admin_or_assigned_team"
    ON public.companies
    FOR SELECT
    TO authenticated
    USING (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.company_teams ct
        WHERE ct.company_id = companies.id
          AND ct.team_id = public.current_team_id()
      )
    );

    CREATE POLICY "companies_admin_all"
    ON public.companies
    FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.company_locations') IS NOT NULL
     AND to_regclass('public.company_teams') IS NOT NULL THEN

    DROP POLICY IF EXISTS "company_locations_select_admin_or_assigned_team" ON public.company_locations;
    DROP POLICY IF EXISTS "company_locations_admin_all" ON public.company_locations;

    CREATE POLICY "company_locations_select_admin_or_assigned_team"
    ON public.company_locations
    FOR SELECT
    TO authenticated
    USING (
      public.is_admin()
      OR EXISTS (
        SELECT 1
        FROM public.company_teams ct
        WHERE ct.company_id = company_locations.company_id
          AND ct.team_id = public.current_team_id()
      )
    );

    CREATE POLICY "company_locations_admin_all"
    ON public.company_locations
    FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.time_slots') IS NOT NULL THEN

    DROP POLICY IF EXISTS "time_slots_select_admin_or_own_team" ON public.time_slots;
    DROP POLICY IF EXISTS "time_slots_insert_admin_only" ON public.time_slots;
    DROP POLICY IF EXISTS "time_slots_update_admin_or_own_team" ON public.time_slots;
    DROP POLICY IF EXISTS "time_slots_delete_admin_only" ON public.time_slots;

    CREATE POLICY "time_slots_select_admin_or_own_team"
    ON public.time_slots
    FOR SELECT
    TO authenticated
    USING (
      public.is_admin()
      OR team_id = public.current_team_id()
    );

    CREATE POLICY "time_slots_insert_admin_only"
    ON public.time_slots
    FOR INSERT
    TO authenticated
    WITH CHECK (public.is_admin());

    CREATE POLICY "time_slots_update_admin_or_own_team"
    ON public.time_slots
    FOR UPDATE
    TO authenticated
    USING (
      public.is_admin()
      OR team_id = public.current_team_id()
    )
    WITH CHECK (
      public.is_admin()
      OR team_id = public.current_team_id()
    );

    CREATE POLICY "time_slots_delete_admin_only"
    ON public.time_slots
    FOR DELETE
    TO authenticated
    USING (public.is_admin());

  END IF;
END $$;

-- =========================================================
-- 13. Grants
-- =========================================================

GRANT USAGE ON SCHEMA public TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.teams TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.agents TO authenticated;

DO $$
BEGIN
  IF to_regclass('public.companies') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON public.companies TO authenticated';
  END IF;

  IF to_regclass('public.company_teams') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_teams TO authenticated';
  END IF;

  IF to_regclass('public.company_locations') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON public.company_locations TO authenticated';
  END IF;

  IF to_regclass('public.time_slots') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON public.time_slots TO authenticated';
  END IF;
END $$;

COMMIT;

-- =========================================================
-- Verification checks
-- =========================================================

SELECT
  u.id AS auth_user_id,
  u.email,
  p.display_name,
  p.role,
  p.agent_id,
  CASE
    WHEN p.id IS NULL THEN 'Missing profile row'
    WHEN p.role = 'admin' THEN 'Admin OK'
    WHEN p.role = 'agent' AND p.agent_id IS NULL THEN 'Agent not linked'
    WHEN p.role = 'agent' AND p.agent_id IS NOT NULL THEN 'Agent linked OK'
    ELSE 'Needs review'
  END AS login_status
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
ORDER BY u.created_at DESC;