/*
# Add multi-location support for companies

1. New Tables
  - `company_locations` - Allows companies to have multiple schedule rows for different service areas
    - `id` (uuid, PK)
    - `company_id` (uuid, FK to roster_companies) - Parent company
    - `location_label` (text, not null) - Display label (e.g. "Amarillo TX", "Lubbock TX")
    - `state` (text, nullable) - State for this specific location
    - `metro_tag` (text, nullable) - Metro area tag
    - `sort_order` (int, default 0) - Ordering within the company
    - `created_at` (timestamptz)
    - UNIQUE(company_id, location_label) - No duplicate locations per company

2. Modified Tables
  - `company_bookings` - Add `location_id` column (nullable, FK to company_locations)
    - When location_id is set, the booking is for that specific location row
    - When null, it's a company-level booking (single-row companies)

3. Security
  - RLS on `company_locations` with same team-based policies as companies
  - Admin sees all locations, agents see only their team's company locations

4. Notes
  - Companies without any locations in this table will still appear as single rows
  - Companies WITH locations will show one row per location
  - Each location row has independent time slot bookings
*/

-- Company locations table
CREATE TABLE IF NOT EXISTS company_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES roster_companies(id) ON DELETE CASCADE,
  location_label text NOT NULL,
  state text,
  metro_tag text,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  UNIQUE(company_id, location_label)
);

ALTER TABLE company_locations ENABLE ROW LEVEL SECURITY;

-- Add location_id to company_bookings
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'company_bookings' AND column_name = 'location_id') THEN
    ALTER TABLE company_bookings ADD COLUMN location_id uuid REFERENCES company_locations(id) ON DELETE CASCADE;
  END IF;
END $$;

-- Drop the old unique constraint and add a new one that includes location_id
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_bookings_company_id_day_time_slot_key') THEN
    ALTER TABLE company_bookings DROP CONSTRAINT company_bookings_company_id_day_time_slot_key;
  END IF;
END $$;

-- New unique constraint: company + location + day + time_slot
ALTER TABLE company_bookings ADD CONSTRAINT company_bookings_unique_slot
  UNIQUE(company_id, location_id, day, time_slot);

-- RLS policies for company_locations
DROP POLICY IF EXISTS "select_company_locations" ON company_locations;
CREATE POLICY "select_company_locations" ON company_locations FOR SELECT
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR company_id IN (
      SELECT id FROM roster_companies WHERE team_id = public.get_user_team_id()
    )
  );

DROP POLICY IF EXISTS "insert_company_locations" ON company_locations;
CREATE POLICY "insert_company_locations" ON company_locations FOR INSERT
  TO authenticated WITH CHECK (
    public.get_user_role() = 'admin'
  );

DROP POLICY IF EXISTS "update_company_locations" ON company_locations;
CREATE POLICY "update_company_locations" ON company_locations FOR UPDATE
  TO authenticated
  USING (public.get_user_role() = 'admin')
  WITH CHECK (public.get_user_role() = 'admin');

DROP POLICY IF EXISTS "delete_company_locations" ON company_locations;
CREATE POLICY "delete_company_locations" ON company_locations FOR DELETE
  TO authenticated USING (public.get_user_role() = 'admin');

-- Indexes
CREATE INDEX IF NOT EXISTS idx_company_locations_company ON company_locations(company_id);
CREATE INDEX IF NOT EXISTS idx_company_bookings_location ON company_bookings(location_id);
