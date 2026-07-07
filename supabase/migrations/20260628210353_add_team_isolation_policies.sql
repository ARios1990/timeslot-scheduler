/*
# Add team-based isolation to RLS policies

1. New Helper Function
  - `get_user_team_id()` - returns the team_id of the current authenticated user's linked agent

2. Policy Changes
  - `agents` SELECT policy: agents can only see agents in their own team (admin sees all)
  - `slot_bookings` SELECT policy: agents can only see bookings for agents in their team (admin sees all)
  - `company_agent_links` SELECT policy: agents can only see links for agents in their team (admin sees all)
  - `roster_companies` and `teams` remain fully visible (needed for dropdowns)

3. Security Notes
  - This enforces team isolation at the database level
  - Even if frontend is manipulated, agents cannot query other teams' data
  - Admin role bypasses all team filters
*/

-- Helper: get the team_id of the current user's linked agent
CREATE OR REPLACE FUNCTION public.get_user_team_id()
RETURNS uuid AS $$
  SELECT a.team_id FROM public.agents a
  INNER JOIN public.profiles p ON p.agent_id = a.id
  WHERE p.id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Update agents SELECT policy: team-scoped for agents, full for admin
DROP POLICY IF EXISTS "authenticated_select_agents" ON agents;
CREATE POLICY "authenticated_select_agents" ON agents FOR SELECT
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR team_id = public.get_user_team_id()
  );

-- Update slot_bookings SELECT policy: team-scoped for agents
DROP POLICY IF EXISTS "authenticated_select_bookings" ON slot_bookings;
CREATE POLICY "authenticated_select_bookings" ON slot_bookings FOR SELECT
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR agent_id IN (SELECT id FROM agents WHERE team_id = public.get_user_team_id())
  );

-- Update company_agent_links SELECT policy: team-scoped for agents
DROP POLICY IF EXISTS "authenticated_select_links" ON company_agent_links;
CREATE POLICY "authenticated_select_links" ON company_agent_links FOR SELECT
  TO authenticated USING (
    public.get_user_role() = 'admin'
    OR agent_id IN (SELECT id FROM agents WHERE team_id = public.get_user_team_id())
  );
