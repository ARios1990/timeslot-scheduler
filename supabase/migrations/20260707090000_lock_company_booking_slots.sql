/*
  # Lock booked company time slots

  Postgres UNIQUE constraints allow multiple NULL values, so the existing
  UNIQUE(company_id, location_id, day, time_slot) constraint does not fully
  prevent duplicate bookings for rows where location_id is null.

  These partial unique indexes lock both booking shapes:
  - company/day/time slots with no location row
  - company/location/day/time slots with a location row
*/

CREATE UNIQUE INDEX IF NOT EXISTS company_bookings_unique_no_location_slot
  ON public.company_bookings (company_id, day, time_slot)
  WHERE location_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS company_bookings_unique_location_slot
  ON public.company_bookings (company_id, location_id, day, time_slot)
  WHERE location_id IS NOT NULL;
