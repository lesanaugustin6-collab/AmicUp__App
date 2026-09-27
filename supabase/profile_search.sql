-- Run once in Supabase SQL Editor. Returns only public search-card fields.
begin;
-- Only this private predicate bypasses RLS, to read hidden settings and
-- blocks in both directions. Profile rows still obey their existing RLS.
create schema if not exists profile_search_private;
revoke all on schema profile_search_private from public, anon;
grant usage on schema profile_search_private to authenticated;
create function profile_search_private.is_searchable(target uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select auth.uid() is not null and target <> auth.uid()
    and not exists (
      select 1 from public.user_settings s where s.user_id = target
        and (s.pause_profile is true or s.incognito_mode is true)
    )
    and not exists (
      select 1 from public.blocked_users b
      where (b.blocker_id = auth.uid() and b.blocked_id = target)
         or (b.blocker_id = target and b.blocked_id = auth.uid())
    )
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = auth.uid() and b.blocked_user_id = target)
         or (b.blocker_id = target and b.blocked_user_id = auth.uid())
    );
$$;
revoke all on function profile_search_private.is_searchable(uuid) from public, anon;
grant execute on function profile_search_private.is_searchable(uuid) to authenticated;

create function public.search_profiles(search_text text)
returns table(id uuid, first_name text, last_name text, username text, avatar_url text)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.id, p.first_name, p.last_name, p.username, p.avatar_url
  from public.profiles p
  where auth.uid() is not null
    and char_length(btrim(search_text)) between 2 and 80
    and p.id <> auth.uid()
    and (
      strpos(lower(coalesce(p.username, '')), lower(btrim(search_text))) > 0
      or strpos(lower(btrim(concat_ws(' ', p.first_name, p.last_name))), lower(btrim(search_text))) > 0
    )
    and profile_search_private.is_searchable(p.id)
  order by (lower(p.username) = lower(btrim(search_text))) desc nulls last,
    lower(coalesce(p.username, '')), p.id
  limit 30;
$$;
revoke all on function public.search_profiles(text) from public, anon;
grant execute on function public.search_profiles(text) to authenticated;
commit;
