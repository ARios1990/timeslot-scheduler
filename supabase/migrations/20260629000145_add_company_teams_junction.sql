/*
# Add multi-team support for companies

1. New Tables
  - `company_teams` - Junction table allowing many-to-many relationship between companies and teams
    - `id` (uuid, PK)
    - `company_id` (uuid, FK to roster_companies) - The company
    - `team_id` (uuid, FK to teams) - The assigned team
    - `created_at` (timestamptz)
    - UNIQUE(company_id, team_id) - No duplicate assignments

2. Security
  - RLS enabled on `company_teams`
  - All authenticated users can read (needed for schedule display)
  - Only admins can insert/update/delete team assignments

3. Notes
  - The existing `team_id` column on `roster_companies` is kept as-is for backwards compatibility
  - The new `company_teams` table is the source of truth for multi-team assignments
  - When `company_teams` has rows for a company, those are used; otherwise falls back to roster_companies.team_id
*/

CREATE TABLE IF NOT EXISTS company_teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES roster_companies(id) ON DELETE CASCADE,
  team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, team_id)
);

ALTER TABLE company_teams ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read team assignments (needed for schedule filtering)
DROP POLICY IF EXISTS "select_company_teams" ON company_teams;
CREATE POLICY "select_company_teams" ON company_teams FOR SELECT
  TO authenticated USING (true);

-- Only admins can manage team assignments
DROP POLICY IF EXISTS "insert_company_teams" ON company_teams;
CREATE POLICY "insert_company_teams" ON company_teams FOR INSERT
  TO authenticated WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "update_company_teams" ON company_teams;
CREATE POLICY "update_company_teams" ON company_teams FOR UPDATE
  TO authenticated
  USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "delete_company_teams" ON company_teams;
CREATE POLICY "delete_company_teams" ON company_teams FOR DELETE
  TO authenticated USING (public.get_user_role() = 'admin');

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_company_teams_company ON company_teams(company_id);
CREATE INDEX IF NOT EXISTS idx_company_teams_team ON company_teams(team_id);
