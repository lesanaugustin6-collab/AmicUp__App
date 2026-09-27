begin;

-- Group sends use the same album field as direct messages.
alter table public.channel_messages add column if not exists image_urls text[];

create index if not exists messages_inbox_latest_idx
  on public.messages(match_id, created_at desc, id desc);
create index if not exists messages_inbox_unread_idx
  on public.messages(match_id, sender_id) where is_read is not true;
create index if not exists channel_members_count_idx on public.channel_members(channel_id, user_id);
create index if not exists likes_activity_recipient_idx on public.likes(liked_id, created_at desc);

-- Counts expose no membership identities and include all members, even when
-- membership RLS only allows a user to read their own membership rows.
create or replace function public.get_channel_member_counts(channel_ids uuid[])
returns table(channel_id uuid, member_count bigint)
language sql stable security definer set search_path = '' as $$
  select c.id, count(distinct cm.user_id)
  from public.channels c
  left join public.channel_members cm on cm.channel_id = c.id
  where auth.uid() is not null and c.id = any(channel_ids)
  group by c.id;
$$;

-- One summary per conversation: no client-side message row limit can truncate
-- the unread count. The caller can only obtain their own inbox.
create or replace function public.get_direct_inbox()
returns table(
  match_id uuid, partner_id uuid, first_name text, username text, avatar_url text,
  created_at timestamptz, last_message text, last_message_at timestamptz,
  last_message_sender_id uuid, unread_count bigint
)
language sql stable security definer set search_path = '' as $$
  select m.id, p.id, p.first_name, p.username, p.avatar_url, m.created_at,
    latest.content, latest.created_at, latest.sender_id,
    (select count(*) from public.messages u
     where u.match_id = m.id and u.sender_id <> auth.uid() and u.is_read is not true)
  from public.matches m
  join public.profiles p on p.id = case when m.user_1 = auth.uid() then m.user_2 else m.user_1 end
  left join lateral (
    select msg.content, msg.created_at, msg.sender_id
    from public.messages msg where msg.match_id = m.id
    order by msg.created_at desc, msg.id desc limit 1
  ) latest on true
  where auth.uid() in (m.user_1, m.user_2)
    and not exists(select 1 from public.blocks b where
      (b.blocker_id = auth.uid() and b.blocked_user_id = p.id) or
      (b.blocker_id = p.id and b.blocked_user_id = auth.uid()))
    and not exists(select 1 from public.blocked_users b where
      (b.blocker_id = auth.uid() and b.blocked_id = p.id) or
      (b.blocker_id = p.id and b.blocked_id = auth.uid()))
  order by coalesce(latest.created_at, m.created_at) desc, m.id;
$$;

-- Record when an existing pass is changed into an incoming like, so Activity
-- shows the time of the like, rather than the date of the old pass.
alter table public.likes add column if not exists liked_at timestamptz;
create or replace function public.stamp_like_activity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if coalesce(new.action in ('like', 'superlike'), false)
      or (coalesce(new.action, '') = '' and new.is_like is true) then
    if tg_op = 'INSERT' then
      new.liked_at := now();
    elsif not (coalesce(old.action in ('like', 'superlike'), false)
        or (coalesce(old.action, '') = '' and old.is_like is true)) then
      new.liked_at := now();
    else
      new.liked_at := old.liked_at;
    end if;
  else new.liked_at := null;
  end if;
  return new;
end;
$$;
drop trigger if exists stamp_like_activity on public.likes;
create trigger stamp_like_activity before insert or update of action, is_like on public.likes
  for each row execute function public.stamp_like_activity();

create or replace function public.get_profile_activity(page_offset integer default 0, page_size integer default 40)
returns table(id text, kind text, actor_id uuid, first_name text, username text, avatar_url text, occurred_at timestamptz)
language sql stable security definer set search_path = '' as $$
  with incoming_likes as (
    select distinct on (l.liker_id) l.id, l.liker_id, l.action, l.is_like,
      coalesce(l.liked_at, l.created_at) as occurred_at
    from public.likes l where l.liked_id = auth.uid() and l.liker_id <> auth.uid()
    order by l.liker_id, l.created_at desc, l.id desc
  ), activity as (
    select 'like:' || l.id::text as id, 'like'::text as kind,
      l.liker_id as actor_id, l.occurred_at
    from incoming_likes l where l.action in ('like', 'superlike')
      or (coalesce(l.action, '') = '' and l.is_like is true)
    union all
    select 'match:' || m.id::text, 'match',
      case when m.user_1 = auth.uid() then m.user_2 else m.user_1 end, m.created_at
    from public.matches m where auth.uid() in (m.user_1, m.user_2)
  )
  select a.id, a.kind, p.id, p.first_name, p.username, p.avatar_url, a.occurred_at
  from activity a join public.profiles p on p.id = a.actor_id
  where not exists(select 1 from public.blocks b where
    (b.blocker_id = auth.uid() and b.blocked_user_id = p.id) or
    (b.blocker_id = p.id and b.blocked_user_id = auth.uid()))
  and not exists(select 1 from public.blocked_users b where
    (b.blocker_id = auth.uid() and b.blocked_id = p.id) or
    (b.blocker_id = p.id and b.blocked_id = auth.uid()))
  order by a.occurred_at desc, a.id desc
  limit greatest(1, least(page_size, 100)) offset greatest(0, page_offset);
$$;

-- Only messages actually loaded by the recipient are marked read. Messages
-- arriving during this request retain their unread state until displayed.
create or replace function public.mark_direct_messages_read(conversation_id uuid, message_ids uuid[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.matches m where m.id = conversation_id and auth.uid() in (m.user_1, m.user_2)
  ) then raise exception 'Conversation unavailable'; end if;
  update public.messages set is_read = true, read_at = now()
  where match_id = conversation_id and id = any(message_ids)
    and sender_id <> auth.uid() and is_read is not true;
end;
$$;

revoke all on function public.get_channel_member_counts(uuid[]) from public, anon;
revoke all on function public.get_direct_inbox() from public, anon;
revoke all on function public.get_profile_activity(integer, integer) from public, anon;
revoke all on function public.mark_direct_messages_read(uuid, uuid[]) from public, anon;
revoke all on function public.stamp_like_activity() from public, anon, authenticated;
grant execute on function public.get_channel_member_counts(uuid[]) to authenticated;
grant execute on function public.get_direct_inbox() to authenticated;
grant execute on function public.get_profile_activity(integer, integer) to authenticated;
grant execute on function public.mark_direct_messages_read(uuid, uuid[]) to authenticated;

-- The recipient can receive live notifications for positive likes, never passes.
drop policy if exists likes_recipient_activity_read on public.likes;
create policy likes_recipient_activity_read on public.likes for select to authenticated
  using (liked_id = auth.uid() and (action in ('like', 'superlike') or
    (coalesce(action, '') = '' and is_like is true)));
grant select on public.likes to authenticated;

do $$
declare t text;
begin
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime' and not puballtables) then
    foreach t in array array['messages', 'channel_messages', 'matches', 'likes', 'channel_members'] loop
      if not exists(select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end;
$$;
notify pgrst, 'reload schema';
commit;
