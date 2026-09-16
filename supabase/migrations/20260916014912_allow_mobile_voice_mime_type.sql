begin;

update storage.buckets
set allowed_mime_types = case
  when allowed_mime_types @> array['audio/mp4']::text[] then allowed_mime_types
  else array_append(allowed_mime_types, 'audio/mp4')
end
where id = 'repair-evidence';

commit;
