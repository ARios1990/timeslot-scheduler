/*
  # Create schedule tables for multi-agent time slot dashboard

  1. New Tables
    - `companies`
      - `id` (uuid, primary key)
      - `name` (text) - company name
      - `day` (text) - day of the week
      - `created_at` (timestamptz)
    - `bookings`
      - `id` (uuid, primary key)
      - `company_id` (uuid, foreign key to companies)
      - `time_slot` (text) - hour value like '9', '10', '1', etc.
      - `is_booked` (boolean) - whether the slot is booked
      - `booked_by` (text) - name of agent who booked it
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS on both tables
    - Allow anonymous read/write access for personal/team use (no auth required for this internal tool)

  3. Notes
    - This is an internal scheduling tool used by agents
    - Unique constraint on company_id + time_slot prevents duplicate bookings
*/

CREATE TABLE IF NOT EXISTS companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  day text NOT NULL CHECK (day IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bookings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  time_slot text NOT NULL,
  is_booked boolean DEFAULT false,
  booked_by text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(company_id, time_slot)
);

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read access to companies"
  ON companies FOR SELECT
  TO anon
  USING (created_at IS NOT NULL);

CREATE POLICY "Allow insert to companies"
  ON companies FOR INSERT
  TO anon
  WITH CHECK (name <> '' AND day <> '');

CREATE POLICY "Allow delete companies"
  ON companies FOR DELETE
  TO anon
  USING (created_at IS NOT NULL);

CREATE POLICY "Allow read access to bookings"
  ON bookings FOR SELECT
  TO anon
  USING (created_at IS NOT NULL);

CREATE POLICY "Allow insert bookings"
  ON bookings FOR INSERT
  TO anon
  WITH CHECK (company_id IS NOT NULL AND time_slot <> '');

CREATE POLICY "Allow update bookings"
  ON bookings FOR UPDATE
  TO anon
  USING (created_at IS NOT NULL)
  WITH CHECK (company_id IS NOT NULL AND time_slot <> '');

CREATE POLICY "Allow delete bookings"
  ON bookings FOR DELETE
  TO anon
  USING (created_at IS NOT NULL);
