/*
# Add company-based scheduling with CSV fields

1. Modified Tables
  - `roster_companies` - Adding new columns:
    - `state` (text, nullable) - State abbreviation (TX, FL, GA, etc.)
    - `contact_name` (text, nullable) - Primary contact name
    - `phone` (text, nullable) - Contact phone
    - `email` (text, nullable) - Primary email
    - `account_status` (text, default 'Active') - Active, Pause, Prospect, etc.
    - `team_id` (uuid, nullable, FK to teams) - Which team handles this company
    - `metro_tag` (text, nullable) - Metro area tag
    - `website` (text, nullable) - Company website

2. New Tables
  - `company_bookings` - Company-based time slot schedule
    - `id` (uuid, PK)
    - `company_id` (uuid, FK to roster_companies) - Which company is booked
    - `day` (text) - Day of week
    - `time_slot` (text) - Hour value
    - `booked_by` (uuid, nullable, FK to profiles) - Who booked it
    - `created_at` (timestamptz)
    - UNIQUE on (company_id, day, time_slot)

3. Security
  - RLS on `company_bookings`
  - Admin: full CRUD on all bookings
  - Agents: can only see/manage bookings for companies assigned to their team
  - Updated `roster_companies` SELECT policy: agents only see companies assigned to their team (or unassigned)

4. Notes
  - The old `slot_bookings` table is kept but no longer used by the new UI
  - Companies are now the primary entities being scheduled
  - When a slot is booked, it displays "Company Name – State"
*/

-- Add columns to roster_companies
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'state') THEN
    ALTER TABLE roster_companies ADD COLUMN state text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'contact_name') THEN
    ALTER TABLE roster_companies ADD COLUMN contact_name text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'phone') THEN
    ALTER TABLE roster_companies ADD COLUMN phone text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'email') THEN
    ALTER TABLE roster_companies ADD COLUMN email text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'account_status') THEN
    ALTER TABLE roster_companies ADD COLUMN account_status text NOT NULL DEFAULT 'Active';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'team_id') THEN
    ALTER TABLE roster_companies ADD COLUMN team_id uuid REFERENCES teams(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'metro_tag') THEN
    ALTER TABLE roster_companies ADD COLUMN metro_tag text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'website') THEN
    ALTER TABLE roster_companies ADD COLUMN website text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'roster_companies' AND column_name = 'client_id') THEN
    ALTER TABLE roster_companies ADD COLUMN client_id text;
  END IF;
END $$;

-- Company bookings table
CREATE TABLE IF NOT EXISTS company_bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES roster_companies(id) ON DELETE CASCADE,
  day text NOT NULL CHECK (day IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')),
  time_slot text NOT NULL,
  booked_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, day, time_slot)
);

ALTER TABLE company_bookings ENABLE ROW LEVEL SECURITY;

-- Update roster_companies SELECT: admin sees all, agents see their team's companies + unassigned
DROP POLICY IF EXISTS "authenticated_select_companies" ON roster_companies;
CREATE POLICY "authenticated_select_companies" ON roster_companies FOR SELECT
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR team_id = public.get_user_team_id()
    OR team_id IS NULL
  );

-- company_bookings policies
DROP POLICY IF EXISTS "select_company_bookings" ON company_bookings;
CREATE POLICY "select_company_bookings" ON company_bookings FOR SELECT
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR company_id IN (
      SELECT id FROM roster_companies
      WHERE team_id = public.get_user_team_id()
    )
  );

DROP POLICY IF EXISTS "insert_company_bookings" ON company_bookings;
CREATE POLICY "insert_company_bookings" ON company_bookings FOR INSERT
  TO authenticated WITH CHECK (
    public.get_user_role() = 'admin'
    OR company_id IN (
      SELECT id FROM roster_companies
      WHERE team_id = public.get_user_team_id()
    )
  );

DROP POLICY IF EXISTS "update_company_bookings" ON company_bookings;
CREATE POLICY "update_company_bookings" ON company_bookings FOR UPDATE
  TO authenticated
  USING (
    public.get_user_role() = 'admin'
    OR company_id IN (
      SELECT id FROM roster_companies
      WHERE team_id = public.get_user_team_id()
    )
  )
  WITH CHECK (
    public.get_user_role() = 'admin'
    OR company_id IN (
      SELECT id FROM roster_companies
      WHERE team_id = public.get_user_team_id()
    )
  );

DROP POLICY IF EXISTS "delete_company_bookings" ON company_bookings;
CREATE POLICY "delete_company_bookings" ON company_bookings FOR DELETE
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR company_id IN (
      SELECT id FROM roster_companies
      WHERE team_id = public.get_user_team_id()
    )
  );

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_company_bookings_day ON company_bookings(day);
CREATE INDEX IF NOT EXISTS idx_company_bookings_company ON company_bookings(company_id);
CREATE INDEX IF NOT EXISTS idx_roster_companies_team ON roster_companies(team_id);
CREATE INDEX IF NOT EXISTS idx_roster_companies_status ON roster_companies(account_status);
