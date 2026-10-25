-- 0004: one private storage bucket, "files", with folder-based access.
--   chat/<conversation_id>/…   message attachments (student or staff in that conversation)
--   submissions/<student_id>/… diary submissions
--   worksheets/…  reports/…  photos/…  albums/…  announcements/…   written by staff, read by signed-in users
-- Everything is served through short-lived signed URLs; nothing is public.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('files', 'files', false, 10485760, array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "files read signed-in" on storage.objects for select
  using (bucket_id = 'files' and auth.role() = 'authenticated');

create policy "files chat upload" on storage.objects for insert
  with check (bucket_id = 'files' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = 'chat'
    and exists (select 1 from public.conversation c where c.id::text = (storage.foldername(name))[2]
                and (c.student_id = any(public.jwt_student_ids()) or c.staff_id = public.jwt_staff_id())));

create policy "files submission upload" on storage.objects for insert
  with check (bucket_id = 'files' and (storage.foldername(name))[1] = 'submissions'
    and (storage.foldername(name))[2] = any(select id::text from unnest(public.jwt_student_ids()) as id));

create policy "files staff upload" on storage.objects for insert
  with check (bucket_id = 'files' and public.is_staff() and (storage.foldername(name))[1] in ('worksheets','reports','photos','albums','announcements','diary'));

create policy "files staff manage" on storage.objects for update using (bucket_id = 'files' and public.is_staff());
create policy "files staff delete" on storage.objects for delete using (bucket_id = 'files' and (public.is_office() or public.has_role('it_admin')));
