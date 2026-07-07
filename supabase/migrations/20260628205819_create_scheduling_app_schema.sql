/*
# Scheduling App - Full Schema with Role-Based Access

1. New Tables
  - `profiles` - User profiles linked to auth, with role and optional agent link
  - `teams` - Team groups (MRS, BRL, TJ, PHL, OCTO, WOO, SSL, NIC)
  - `roster_companies` - All roofing/construction companies
  - `agents` - Individual agents with team assignments
  - `company_agent_links` - Which agents are assigned to which companies
  - `slot_bookings` - The actual schedule bookings

2. Helper Functions
  - `get_user_role()` - returns the role of the current authenticated user
  - `get_user_agent_id()` - returns the agent_id of the current authenticated user

3. Security
  - RLS enabled on ALL tables
  - Role-based: admin full access, agents limited to own bookings
*/

-- Profiles table FIRST (referenced by helper functions)
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'agent' CHECK (role IN ('admin', 'agent')),
  agent_id uuid,
  display_name text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now()
);

-- Teams table
CREATE TABLE IF NOT EXISTS teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  abbreviation text UNIQUE NOT NULL
);

-- Companies table
CREATE TABLE IF NOT EXISTS roster_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL
);

-- Agents table
CREATE TABLE IF NOT EXISTS agents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE
);

-- Add FK on profiles.agent_id now that agents exists
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'profiles_agent_id_fkey'
  ) THEN
    ALTER TABLE profiles ADD CONSTRAINT profiles_agent_id_fkey
      FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Company-Agent assignments
CREATE TABLE IF NOT EXISTS company_agent_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES roster_companies(id) ON DELETE CASCADE,
  agent_id uuid NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  UNIQUE(company_id, agent_id)
);

-- Slot bookings
CREATE TABLE IF NOT EXISTS slot_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id uuid NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  day text NOT NULL CHECK (day IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')),
  time_slot text NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(agent_id, day, time_slot)
);

-- Helper functions for RLS
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.get_user_agent_id()
RETURNS uuid AS $$
  SELECT agent_id FROM public.profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE roster_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_agent_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE slot_bookings ENABLE ROW LEVEL SECURITY;

-- PROFILES policies
DROP POLICY IF EXISTS "authenticated_select_profiles" ON profiles;
CREATE POLICY "authenticated_select_profiles" ON profiles FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "users_insert_own_profile" ON profiles;
CREATE POLICY "users_insert_own_profile" ON profiles FOR INSERT
  TO authenticated WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "users_update_own_profile" ON profiles;
CREATE POLICY "users_update_own_profile" ON profiles FOR UPDATE
  TO authenticated USING (auth.uid() = id OR public.get_user_role() = 'admin')
  WITH CHECK (auth.uid() = id OR public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_delete_profiles" ON profiles;
CREATE POLICY "admin_delete_profiles" ON profiles FOR DELETE
  TO authenticated USING (public.get_user_role() = 'admin');

-- TEAMS policies
DROP POLICY IF EXISTS "authenticated_select_teams" ON teams;
CREATE POLICY "authenticated_select_teams" ON teams FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "admin_insert_teams" ON teams;
CREATE POLICY "admin_insert_teams" ON teams FOR INSERT
  TO authenticated WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_update_teams" ON teams;
CREATE POLICY "admin_update_teams" ON teams FOR UPDATE
  TO authenticated USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_delete_teams" ON teams;
CREATE POLICY "admin_delete_teams" ON teams FOR DELETE
  TO authenticated USING (public.get_user_role() = 'admin');

-- ROSTER_COMPANIES policies
DROP POLICY IF EXISTS "authenticated_select_companies" ON roster_companies;
CREATE POLICY "authenticated_select_companies" ON roster_companies FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "admin_insert_companies" ON roster_companies;
CREATE POLICY "admin_insert_companies" ON roster_companies FOR INSERT
  TO authenticated WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_update_companies" ON roster_companies;
CREATE POLICY "admin_update_companies" ON roster_companies FOR UPDATE
  TO authenticated USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_delete_companies" ON roster_companies;
CREATE POLICY "admin_delete_companies" ON roster_companies FOR DELETE
  TO authenticated USING (public.get_user_role() = 'admin');

-- AGENTS policies
DROP POLICY IF EXISTS "authenticated_select_agents" ON agents;
CREATE POLICY "authenticated_select_agents" ON agents FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "admin_insert_agents" ON agents;
CREATE POLICY "admin_insert_agents" ON agents FOR INSERT
  TO authenticated WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_update_agents" ON agents;
CREATE POLICY "admin_update_agents" ON agents FOR UPDATE
  TO authenticated USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_delete_agents" ON agents;
CREATE POLICY "admin_delete_agents" ON agents FOR DELETE
  TO authenticated USING (public.get_user_role() = 'admin');

-- COMPANY_AGENT_LINKS policies
DROP POLICY IF EXISTS "authenticated_select_links" ON company_agent_links;
CREATE POLICY "authenticated_select_links" ON company_agent_links FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "admin_insert_links" ON company_agent_links;
CREATE POLICY "admin_insert_links" ON company_agent_links FOR INSERT
  TO authenticated WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_update_links" ON company_agent_links;
CREATE POLICY "admin_update_links" ON company_agent_links FOR UPDATE
  TO authenticated USING (public.get_user_role() = 'admin') WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "admin_delete_links" ON company_agent_links;
CREATE POLICY "admin_delete_links" ON company_agent_links FOR DELETE
  TO authenticated USING (public.get_user_role() = 'admin');

-- SLOT_BOOKINGS policies
DROP POLICY IF EXISTS "authenticated_select_bookings" ON slot_bookings;
CREATE POLICY "authenticated_select_bookings" ON slot_bookings FOR SELECT
  TO authenticated USING (true);

DROP POLICY IF EXISTS "agent_insert_own_bookings" ON slot_bookings;
CREATE POLICY "agent_insert_own_bookings" ON slot_bookings FOR INSERT
  TO authenticated WITH CHECK (
    public.get_user_role() = 'admin'
    OR agent_id = public.get_user_agent_id()
  );

DROP POLICY IF EXISTS "agent_update_own_bookings" ON slot_bookings;
CREATE POLICY "agent_update_own_bookings" ON slot_bookings FOR UPDATE
  TO authenticated
  USING (public.get_user_role() = 'admin' OR agent_id = public.get_user_agent_id())
  WITH CHECK (public.get_user_role() = 'admin' OR agent_id = public.get_user_agent_id());

DROP POLICY IF EXISTS "agent_delete_own_bookings" ON slot_bookings;
CREATE POLICY "agent_delete_own_bookings" ON slot_bookings FOR DELETE
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR agent_id = public.get_user_agent_id()
  );

-- Trigger to auto-create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, role, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'role', 'agent'),
    COALESCE(NEW.raw_user_meta_data->>'display_name', NEW.email)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
