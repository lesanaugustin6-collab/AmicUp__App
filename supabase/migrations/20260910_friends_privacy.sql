begin;

alter table public.user_settings
  add column if not exists show_friends_list boolean not null default true;
alter table public.user_settings alter column show_friends_list set default true;

-- New settings default to visible. Preserve existing explicit privacy choices.
-- Keep chat/match reads limited to participants, even if a permissive policy exists.
alter table public.matches enable row level security;
drop policy if exists matches_participant_privacy on public.matches;
create policy matches_participant_privacy on public.matches
  as restrictive for select to authenticated
  using (auth.uid() = user_1 or auth.uid() = user_2);
revoke select on public.matches from anon;

create or replace function public.set_friends_visibility(visible boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  insert into public.user_settings(user_id, show_friends_list)
  values (auth.uid(), visible)
  on conflict (user_id) do update set show_friends_list = excluded.show_friends_list;
end;
$$;

create or replace function public.get_profile_friends(target_id uuid, page_offset integer default 0, page_size integer default 40)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  allowed boolean;
  total integer;
  people jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if not exists(select 1 from public.profiles where id = target_id) then
    raise exception 'Profile unavailable';
  end if;
  if exists(select 1 from public.blocks where
      (blocker_id = auth.uid() and blocked_user_id = target_id) or
      (blocker_id = target_id and blocked_user_id = auth.uid()))
    or exists(select 1 from public.blocked_users where
      (blocker_id = auth.uid() and blocked_id = target_id) or
      (blocker_id = target_id and blocked_id = auth.uid())) then
    raise exception 'Profile unavailable';
  end if;
  allowed := target_id = auth.uid() or coalesce((select show_friends_list from public.user_settings where user_id = target_id), true);
  select count(distinct case when user_1 = target_id then user_2 else user_1 end)
    into total from public.matches where user_1 = target_id or user_2 = target_id;
  if not allowed then
    return jsonb_build_object('private', true, 'count', total, 'friends', '[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) into people from (
    select id, first_name, last_name, username, avatar_url
    from public.profiles where id in (
      select case when user_1 = target_id then user_2 else user_1 end
      from public.matches where user_1 = target_id or user_2 = target_id
    )
    and not exists(select 1 from public.blocks b where
      (b.blocker_id = auth.uid() and b.blocked_user_id = profiles.id) or
      (b.blocker_id = profiles.id and b.blocked_user_id = auth.uid()))
    and not exists(select 1 from public.blocked_users b where
      (b.blocker_id = auth.uid() and b.blocked_id = profiles.id) or
      (b.blocker_id = profiles.id and b.blocked_id = auth.uid()))
    order by lower(coalesce(first_name, username, '')), id
    limit greatest(0, least(page_size, 100)) offset greatest(0, page_offset)
  ) p;
  return jsonb_build_object('private', false, 'count', total, 'friends', people);
end;
$$;
revoke all on function public.get_profile_friends(uuid, integer, integer) from public, anon;
revoke all on function public.set_friends_visibility(boolean) from public, anon;
grant execute on function public.get_profile_friends(uuid, integer, integer) to authenticated;
grant execute on function public.set_friends_visibility(boolean) to authenticated;
notify pgrst, 'reload schema';
commit;
