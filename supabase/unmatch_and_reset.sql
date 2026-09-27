-- Run once in Supabase SQL Editor before using the updated Unmatch action.
-- All deletions happen in one transaction; failure rolls everything back.
begin;
create function public.unmatch_and_reset(target_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pair_match_ids uuid[];
begin
  if caller is null or target_id is null or caller = target_id then
    raise exception 'Invalid unmatch request' using errcode = '42501';
  end if;

  -- Lock only matches involving the signed-in caller and selected person.
  select array_agg(m.id) into pair_match_ids
  from (
    select id from public.matches
    where (user_1 = caller and user_2 = target_id)
       or (user_1 = target_id and user_2 = caller)
    for update
  ) m;

  if pair_match_ids is null then
    raise exception 'This match no longer exists' using errcode = 'P0001';
  end if;

  delete from public.messages where match_id = any(pair_match_ids);
  delete from public.likes
    where (liker_id = caller and liked_id = target_id)
       or (liker_id = target_id and liked_id = caller);
  delete from public.interactions
    where (user_id = caller and target_user_id = target_id)
       or (user_id = target_id and target_user_id = caller);
  delete from public.matches where id = any(pair_match_ids);
  -- Intentionally preserve reviews, saved profiles, reports, and blocks.
end;
$$;
revoke all on function public.unmatch_and_reset(uuid) from public, anon;
grant execute on function public.unmatch_and_reset(uuid) to authenticated;
commit;
