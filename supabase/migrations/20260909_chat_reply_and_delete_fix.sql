-- Run this entire file in Supabase SQL Editor.
begin;
alter table public.messages add column if not exists reply_to_id uuid
  references public.messages(id) on delete set null;
alter table public.channel_messages add column if not exists reply_to_id uuid
  references public.channel_messages(id) on delete set null;
create index if not exists messages_reply_to_id_idx on public.messages(reply_to_id);
create index if not exists channel_messages_reply_to_id_idx on public.channel_messages(reply_to_id);

-- Allow an authenticated sender to delete their own messages.
-- Existing SELECT policies still govern visibility and DELETE ... RETURNING.
grant delete on public.messages, public.channel_messages to authenticated;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
    and tablename = 'messages' and policyname = 'amicup_delete_own_message') then
    create policy amicup_delete_own_message on public.messages for delete
      to authenticated using ((select auth.uid()) = sender_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
    and tablename = 'channel_messages' and policyname = 'amicup_delete_own_channel_message') then
    create policy amicup_delete_own_channel_message on public.channel_messages for delete
      to authenticated using ((select auth.uid()) = sender_id);
  end if;
end $$;
notify pgrst, 'reload schema';
commit;
