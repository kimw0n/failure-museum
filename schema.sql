-- ============================================================
--  실패 박물관 (Failure Museum) · Supabase 스키마
--  Supabase 대시보드 → SQL Editor → New query 에 이 파일 전체를 붙여넣고 [Run].
--  여러 번 실행해도 안전합니다 (if not exists / on conflict / drop policy if exists).
--  시드 데이터는 없습니다. 박물관은 빈 상태로 시작합니다.
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- 1. 전시품 테이블 ----------
create table if not exists public.exhibits (
  id          text primary key default gen_random_uuid()::text,
  title       text not null check (char_length(title) between 1 and 40),
  cause       text not null check (char_length(cause) between 1 and 60),
  age         text not null check (char_length(age) between 1 and 60),
  relic       text not null default '없음 (빈손으로 감)' check (char_length(relic) <= 60),
  epitaph     text not null default '고인은 말이 없다' check (char_length(epitaph) <= 60),
  empathy     integer not null default 0 check (empathy >= 0),
  created_at  timestamptz not null default now()
);
-- 사진 URL (nullable): 우리 Storage 버킷의 공개 URL만 허용
alter table public.exhibits add column if not exists photo_url text;
alter table public.exhibits drop constraint if exists exhibits_photo_url_check;
alter table public.exhibits add constraint exhibits_photo_url_check
  check (photo_url is null or (char_length(photo_url) <= 500 and photo_url like '%/storage/v1/object/public/exhibit-photos/%'));

-- 예전 버전(시드 15개)을 실행했던 DB라면 시드를 지운다
delete from public.exhibits where id like 'seed-%';

-- id는 브라우저가 만든 UUID (낙관적 반영과 실시간 이벤트를 id로 합치기 위해)
alter table public.exhibits drop constraint if exists exhibits_id_format;
alter table public.exhibits add constraint exhibits_id_format
  check (id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

-- 전시 슬롯 (벽의 빈 액자 자리). index.html 의 SLOTS 배열 id 와 같은 형식 (예: hall-03, regret-12, annex-004)
alter table public.exhibits add column if not exists slot_id text;
alter table public.exhibits drop constraint if exists exhibits_slot_id_format;
alter table public.exhibits add constraint exhibits_slot_id_format
  check (slot_id is null or slot_id ~ '^(lobby|hall|regret|cry|lazy|dead|unfin|annex)-[0-9]{2,3}$');
-- 같은 슬롯에 두 작품이 동시에 걸리지 않게 (동시 등록 시 늦은 쪽은 409 → 앱이 옆 빈 액자로 재시도)
create unique index if not exists exhibits_slot_active_uidx on public.exhibits (slot_id) where slot_id is not null;

create index if not exists exhibits_created_at_idx on public.exhibits (created_at desc);
create index if not exists exhibits_empathy_idx    on public.exhibits (empathy desc, created_at);

-- ---------- 2. RLS: 조회/등록만 허용, 수정·삭제 불가 ----------
alter table public.exhibits enable row level security;

drop policy if exists exhibits_select on public.exhibits;
create policy exhibits_select on public.exhibits
  for select to anon, authenticated using (true);

drop policy if exists exhibits_insert on public.exhibits;
create policy exhibits_insert on public.exhibits
  for insert to anon, authenticated with check (empathy = 0);

-- update / delete 정책은 만들지 않는다 → 클라이언트가 직접 고칠 수 없음 (공감은 아래 RPC로만).
-- 컬럼 권한: 클라이언트는 내용 필드만 넣을 수 있고 empathy · created_at 은 기본값이 강제된다.
revoke insert, update, delete on public.exhibits from anon, authenticated;
grant select on public.exhibits to anon, authenticated;
grant insert (id, title, cause, age, relic, epitaph, photo_url, slot_id) on public.exhibits to anon, authenticated;

-- ---------- 3. 공감 +1 은 이 RPC 로만 ----------
create or replace function public.increment_empathy(exhibit_id text)
returns integer
language sql
security definer
set search_path = public
as $$
  update public.exhibits
     set empathy = empathy + 1
   where id = exhibit_id
  returning empathy;
$$;
revoke all on function public.increment_empathy(text) from public;
grant execute on function public.increment_empathy(text) to anon, authenticated;

-- ---------- 3-1. 슬롯이 없는 작품(예전 작품 등)에 빈 슬롯 기록: slot_id 가 비어 있을 때만 한 번 ----------
create or replace function public.claim_slot(exhibit_id text, slot text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare result text;
begin
  begin
    update public.exhibits set slot_id = slot
     where id = exhibit_id and slot_id is null
    returning slot_id into result;
  exception when unique_violation then
    result := null;   -- 그사이 다른 작품이 그 자리를 차지함
  end;
  if result is null then
    select e.slot_id into result from public.exhibits e where e.id = exhibit_id;
  end if;
  return result;
end;
$$;
revoke all on function public.claim_slot(text, text) from public;
grant execute on function public.claim_slot(text, text) to anon, authenticated;

-- ---------- 4. 방문객 카운터 ("당신은 N번째 방문객입니다") ----------
create table if not exists public.visit_counter (
  id    int primary key default 1 check (id = 1),
  count bigint not null default 0
);
insert into public.visit_counter (id, count) values (1, 0) on conflict (id) do nothing;
alter table public.visit_counter enable row level security;   -- 정책 없음: RPC 외 접근 불가

create or replace function public.register_visit()
returns bigint
language sql
security definer
set search_path = public
as $$
  update public.visit_counter set count = count + 1 where id = 1 returning count;
$$;
revoke all on function public.register_visit() from public;
grant execute on function public.register_visit() to anon, authenticated;

-- ---------- 5. Realtime: exhibits 의 INSERT / UPDATE 를 브라우저로 전송 ----------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'exhibits'
  ) then
    alter publication supabase_realtime add table public.exhibits;
  end if;
end $$;

-- ---------- 6. Storage: 사진 버킷 "exhibit-photos" ----------
-- 공개 읽기(public = true). 파일 크기 제한 1MB(앱이 500KB 이하로 압축해 올림), 이미지 형식만 허용.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('exhibit-photos', 'exhibit-photos', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- 누구나 읽기
drop policy if exists exhibit_photos_read on storage.objects;
create policy exhibit_photos_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'exhibit-photos');

-- 익명 업로드 허용: 이 버킷, "<uuid>.jpg" 이름만. 덮어쓰기(update)·삭제 정책은 없음.
drop policy if exists exhibit_photos_upload on storage.objects;
create policy exhibit_photos_upload on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'exhibit-photos'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
  );

-- ---------- 확인용 쿼리 (실행 결과가 보이면 설정 완료) ----------
select
  (select count(*) from public.exhibits)                                            as exhibits_rows,
  (select public from storage.buckets where id = 'exhibit-photos')                   as bucket_public,
  (select count(*) from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'exhibits')                 as realtime_on;
