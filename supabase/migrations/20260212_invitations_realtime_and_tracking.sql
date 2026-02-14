-- Add tourism_invitations and tourism_check_ins to Realtime publication
-- This enables real-time updates when passengers accept/decline invitations
-- and when check-in status changes
ALTER PUBLICATION supabase_realtime ADD TABLE tourism_invitations;
ALTER PUBLICATION supabase_realtime ADD TABLE tourism_check_ins;
