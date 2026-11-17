-- Add indexes for foreign-key columns flagged by Supabase's performance advisor.
-- These are additive and preserve all existing RLS policies and application behavior.

create index if not exists chat_media_sender_id_idx
  on public.chat_media (sender_id);

create index if not exists chat_media_receiver_id_idx
  on public.chat_media (receiver_id);

create index if not exists match_event_poster_assets_organiser_id_idx
  on public.match_event_poster_assets (organiser_id);

create index if not exists message_hidden_for_user_id_idx
  on public.message_hidden_for (user_id);

create index if not exists profile_passes_passed_id_idx
  on public.profile_passes (passed_id);

create index if not exists referrals_referrer_id_idx
  on public.referrals (referrer_id);
