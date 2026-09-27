-- Run in Supabase SQL Editor before sending replies from the updated app.
-- No existing messages or access policies are removed.
begin;
alter table public.messages add column if not exists reply_to_id uuid
  references public.messages(id) on delete set null;
alter table public.channel_messages add column if not exists reply_to_id uuid
  references public.channel_messages(id) on delete set null;
create index if not exists messages_reply_to_id_idx on public.messages(reply_to_id);
create index if not exists channel_messages_reply_to_id_idx on public.channel_messages(reply_to_id);
commit;
