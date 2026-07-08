/*
  # Add company notes

  requirements_note is the small company-specific note shown on the time-slot
  board. notes is for general internal company notes.
*/

ALTER TABLE public.roster_companies
  ADD COLUMN IF NOT EXISTS requirements_note text;

ALTER TABLE public.roster_companies
  ADD COLUMN IF NOT EXISTS notes text;

COMMENT ON COLUMN public.roster_companies.requirements_note IS
  'Small company-specific requirements note shown on the time-slot board.';

COMMENT ON COLUMN public.roster_companies.notes IS
  'General internal company notes.';
