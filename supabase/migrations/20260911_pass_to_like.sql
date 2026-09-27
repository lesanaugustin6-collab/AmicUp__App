begin;

-- Allow people to change their own earlier pass into a like.
grant update (action, is_like) on public.likes to authenticated;
grant update (action) on public.interactions to authenticated;
drop policy if exists likes_update_own_action on public.likes;
create policy likes_update_own_action on public.likes for update to authenticated
  using (liker_id = auth.uid()) with check (liker_id = auth.uid());
drop policy if exists interactions_update_own_action on public.interactions;
create policy interactions_update_own_action on public.interactions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Existing INSERT triggers may not run when a pass is changed via UPDATE.
create or replace function public.match_after_like_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  first_id uuid := least(new.liker_id, new.liked_id);
  second_id uuid := greatest(new.liker_id, new.liked_id);
begin
  if new.liker_id = new.liked_id or not (
    coalesce(new.action in ('like', 'superlike'), false) or
    (coalesce(new.action, '') = '' and new.is_like is true)
  ) then return new; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(first_id::text || ':' || second_id::text, 0));
  if exists (
    select 1 from public.likes l
    where l.liker_id = new.liked_id and l.liked_id = new.liker_id
      and (l.action in ('like', 'superlike') or
        (coalesce(l.action, '') = '' and l.is_like is true))
  ) and not exists (
    select 1 from public.matches m
    where (m.user_1 = first_id and m.user_2 = second_id)
       or (m.user_1 = second_id and m.user_2 = first_id)
  ) then
    insert into public.matches(user_1, user_2) values (first_id, second_id)
      on conflict do nothing;
  end if;
  return new;
end;
$$;
revoke all on function public.match_after_like_change() from public, anon, authenticated;
drop trigger if exists match_after_like_change on public.likes;
create trigger match_after_like_change after update of action, is_like on public.likes
  for each row execute function public.match_after_like_change();
notify pgrst, 'reload schema';
commit;
