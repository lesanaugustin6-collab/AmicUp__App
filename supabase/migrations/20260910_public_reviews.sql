-- Reviews are readable by every signed-in app user, independently of friends privacy.
-- This does not grant permission to write or delete reviews.
alter table public.profile_reviews enable row level security;
grant select on public.profile_reviews to authenticated;
drop policy if exists reviews_public_read on public.profile_reviews;
create policy reviews_public_read on public.profile_reviews
  for select to authenticated using (true);
notify pgrst, 'reload schema';
