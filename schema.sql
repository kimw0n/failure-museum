-- ============================================================
--  실패 박물관 (Failure Museum) · Supabase 스키마 (v3: 전시 슬롯 · 전당 · 2주 뒤 철거)
--  새 프로젝트: Supabase 대시보드 → SQL Editor → New query 에 이 파일 전체를 붙여넣고 [Run].
--  이미 v2 스키마로 운영 중인 DB 라면 이 파일 대신 migration_v3.sql 을 실행하세요 (둘 다 여러 번 실행해도 안전).
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

create index if not exists exhibits_created_at_idx on public.exhibits (created_at desc);
create index if not exists exhibits_empathy_idx    on public.exhibits (empathy desc, created_at);

-- ---------- v3-1. 슬롯 · 전당 · 철거 컬럼 ----------
-- slot_id    : 작품이 걸린 벽 자리 (index.html 의 SLOTS 배열 id, 예: hall-03 / regret-12 / annex-004)
-- in_hall    : 불멸의 흑역사관(공감 상위 5) 여부. DB(refresh_hall)만 바꾼다
-- expires_at : 철거 예정 시각. 일반 전시는 등록 후 14일, 전당에 있는 동안은 null(영구 보존)
alter table public.exhibits add column if not exists slot_id text;
alter table public.exhibits add column if not exists in_hall boolean not null default false;
alter table public.exhibits add column if not exists expires_at timestamptz default (now() + interval '14 days');
alter table public.exhibits alter column expires_at set default (now() + interval '14 days');

alter table public.exhibits drop constraint if exists exhibits_slot_id_format;
alter table public.exhibits add constraint exhibits_slot_id_format
  check (slot_id is null or slot_id ~ '^(lobby|hall|regret|cry|lazy|dead|unfin|annex)-[0-9]{2,3}$');

-- 같은 슬롯에 작품 두 개가 걸리지 않게: 전당에 올라간 작품의 원래 슬롯은 비워 준다(부분 유니크).
-- 동시에 같은 슬롯에 등록하면 늦은 쪽 insert 가 409(23505) → 앱이 "방금 다른 분이 먼저 전시했습니다" 후 옆 빈 액자로 재시도.
-- (만료됐지만 아직 cron 이 지우지 않은 작품은 아래 insert 트리거가 먼저 치운다 — 인덱스 조건에는 now()를 쓸 수 없어서)
drop index if exists public.exhibits_slot_active_uidx;
create unique index if not exists exhibits_slot_live_uidx on public.exhibits (slot_id) where slot_id is not null and not in_hall;
create index if not exists exhibits_expires_at_idx on public.exhibits (expires_at) where expires_at is not null;
create index if not exists exhibits_in_hall_idx on public.exhibits (in_hall) where in_hall;

-- ---------- v3-2. 등록 트리거: 만료 작품이 잡고 있던 슬롯 비우기 + 서버 값 강제 ----------
create or replace function public.exhibits_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.slot_id is not null then
    delete from public.exhibits
     where slot_id = new.slot_id and not in_hall and expires_at is not null and expires_at <= now();
  end if;
  new.in_hall := false;
  new.expires_at := now() + interval '14 days';
  return new;
end;
$$;
drop trigger if exists exhibits_before_insert on public.exhibits;
create trigger exhibits_before_insert before insert on public.exhibits
  for each row execute function public.exhibits_before_insert();

-- ---------- v3-3. 전당 재계산 (공감 상위 5) ----------
-- 들어가면 in_hall = true, expires_at = null (영구 보존). 원래 slot_id 는 남기지만 유니크 대상에서 빠져 빈 액자로 돌아간다.
-- 밀려나면 in_hall = false, expires_at = now() + 14일. 원래 슬롯을 이미 다른 작품이 쓰면 slot_id = null
--   → 앱이 원래 자리에서 가장 가까운 빈 슬롯을 계산해 claim_slot 으로 기록한다.
create or replace function public.refresh_hall()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  top_ids text[];
  r record;
begin
  perform pg_advisory_xact_lock(hashtext('failure_museum_hall'));
  select coalesce(array_agg(t.id), '{}') into top_ids
    from (select id from public.exhibits
           where empathy >= 1 and (in_hall or expires_at is null or expires_at > now())
           order by empathy desc, created_at asc, id
           limit 5) t;
  update public.exhibits set in_hall = true, expires_at = null
   where id = any(top_ids) and not in_hall;
  for r in select id from public.exhibits where in_hall and not (id = any(top_ids)) loop
    begin
      update public.exhibits set in_hall = false, expires_at = now() + interval '14 days' where id = r.id;
    exception when unique_violation then
      update public.exhibits set in_hall = false, expires_at = now() + interval '14 days', slot_id = null where id = r.id;
    end;
  end loop;
end;
$$;
revoke all on function public.refresh_hall() from public, anon, authenticated;

-- ---------- v3-4. 공감 +1 (이 RPC 로만) → 전당 재계산까지 한 트랜잭션에서 ----------
create or replace function public.increment_empathy(exhibit_id text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  update public.exhibits set empathy = empathy + 1
   where id = exhibit_id and (in_hall or expires_at is null or expires_at > now())
  returning empathy into n;
  if n is not null then
    perform public.refresh_hall();
  end if;
  return n;
end;
$$;
revoke all on function public.increment_empathy(text) from public;
grant execute on function public.increment_empathy(text) to anon, authenticated;

-- ---------- v3-5. 슬롯이 비어 있는 작품(예전 작품, 전당에서 밀려난 작품)에 빈 슬롯 기록 — slot_id 가 null 일 때만 ----------
create or replace function public.claim_slot(exhibit_id text, slot text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare result text;
begin
  delete from public.exhibits
   where slot_id = slot and not in_hall and expires_at is not null and expires_at <= now();
  begin
    update public.exhibits set slot_id = slot
     where id = exhibit_id and slot_id is null and not in_hall
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

-- ---------- v3-6. RLS 재확인: 조회는 모두, 등록은 내용 + slot_id 만 (empathy · in_hall · expires_at 은 서버가 정함) ----------
alter table public.exhibits enable row level security;
drop policy if exists exhibits_select on public.exhibits;
create policy exhibits_select on public.exhibits
  for select to anon, authenticated using (true);   -- 만료 필터는 앱 조회 조건(expires_at is null or expires_at > now())으로
drop policy if exists exhibits_insert on public.exhibits;
create policy exhibits_insert on public.exhibits
  for insert to anon, authenticated with check (empathy = 0 and not in_hall);
revoke insert, update, delete on public.exhibits from anon, authenticated;
grant select on public.exhibits to anon, authenticated;
grant insert (id, title, cause, age, relic, epitaph, photo_url, slot_id) on public.exhibits to anon, authenticated;

-- ---------- v3-7. 작품이 삭제되면 Storage 사진도 정리 ----------
-- 1순위: storage.objects 에서 '<id>.jpg' 행 삭제.
--   최근 Supabase 프로젝트는 SQL로 storage.objects 를 직접 지우는 것을 막아 두었으므로(“Direct deletion from storage tables is not allowed”),
--   실패하면 작품 삭제는 그대로 진행하고 파일 이름을 photo_cleanup_queue 에 남긴다 → README 의 수동 정리 방법 참고.
create table if not exists public.photo_cleanup_queue (
  name      text primary key,
  queued_at timestamptz not null default now(),
  reason    text
);
alter table public.photo_cleanup_queue enable row level security;   -- 정책 없음: 대시보드/SQL 에서만 조회
revoke all on public.photo_cleanup_queue from anon, authenticated;

create or replace function public.exhibits_after_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.photo_url is not null then
    begin
      delete from storage.objects where bucket_id = 'exhibit-photos' and name = old.id || '.jpg';
    exception when others then
      insert into public.photo_cleanup_queue (name, reason) values (old.id || '.jpg', left(sqlerrm, 300))
        on conflict (name) do nothing;
    end;
  end if;
  return old;
end;
$$;
drop trigger if exists exhibits_after_delete on public.exhibits;
create trigger exhibits_after_delete after delete on public.exhibits
  for each row execute function public.exhibits_after_delete();

-- ---------- v3-8. 매일 1회 만료 작품 삭제 (pg_cron) ----------
-- pg_cron 이 꺼져 있으면 여기서 켜기를 시도하고, 권한 문제로 안 되면 안내만 남긴다
--   → 대시보드 Database → Extensions 에서 pg_cron 을 켠 뒤 이 파일을 한 번 더 실행하면 작업이 등록된다.
-- 매일 18:00 UTC = 한국 시간 새벽 3시. 같은 이름으로 다시 등록하면 덮어쓴다.
do $$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'pg_cron 확장을 켜지 못했습니다 (%). Database → Extensions 에서 pg_cron 을 켠 뒤 다시 실행하세요.', sqlerrm;
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('failure-museum-expire', '0 18 * * *',
      $cron$delete from public.exhibits where expires_at is not null and expires_at < now()$cron$);
  end if;
end $$;

-- ---------- v3-9. Realtime: INSERT / UPDATE / DELETE 전송 (DELETE 는 id 만 전달됨) ----------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'exhibits'
  ) then
    alter publication supabase_realtime add table public.exhibits;
  end if;
end $$;

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

-- ============================================================
--  v4: 서버 측 남용 제한 (자세한 설명은 migration_v4.sql 머리말)
--  아래 함수들이 위 v3 의 exhibits_before_insert · increment_empathy 를 최종 버전으로 덮어씁니다.
-- ============================================================
-- ---------- v4-1. 제한 기록 테이블 (클라이언트 접근 불가) ----------
create table if not exists public.rate_events (
  id      bigserial primary key,
  ip_hash text not null,
  kind    text not null check (kind in ('insert', 'empathy')),
  target  text,
  at      timestamptz not null default now()
);
create index if not exists rate_events_lookup_idx on public.rate_events (ip_hash, kind, at desc);
create index if not exists rate_events_kind_at_idx on public.rate_events (kind, at desc);
alter table public.rate_events enable row level security;   -- 정책 없음
revoke all on public.rate_events from anon, authenticated;
revoke all on sequence public.rate_events_id_seq from anon, authenticated;

-- ---------- v4-2. 요청 IP 해시 (API 밖이면 null) ----------
create or replace function public.client_ip_hash()
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  h  json;
  ip text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then
    h := null;
  end;
  if h is null then
    return null;
  end if;
  ip := coalesce(nullif(h ->> 'cf-connecting-ip', ''),
                 nullif(trim(split_part(h ->> 'x-forwarded-for', ',', 1)), ''),
                 nullif(h ->> 'x-real-ip', ''),
                 'unknown');
  return encode(sha256(convert_to('failure-museum:' || ip, 'UTF8')), 'hex');
end;
$$;
revoke all on function public.client_ip_hash() from public, anon, authenticated;

-- ---------- v4-3. 등록 트리거: v3 동작 + 등록 속도 제한 ----------
create or replace function public.exhibits_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ip text := public.client_ip_hash();
begin
  if ip is not null then
    perform pg_advisory_xact_lock(hashtext('fm-rate:' || ip));
    if (select count(*) from public.rate_events
         where kind = 'insert' and at > now() - interval '10 minutes') >= 60 then
      raise exception 'rate_limited_global' using errcode = 'P0001',
        hint = '전시 신청이 몰려 잠시 접수를 멈췄습니다. 몇 분 뒤 다시 시도하세요.';
    end if;
    if (select count(*) from public.rate_events
         where ip_hash = ip and kind = 'insert' and at > now() - interval '10 minutes') >= 5 then
      raise exception 'rate_limited_insert' using errcode = 'P0001',
        hint = '같은 곳에서 10분에 5건까지 전시할 수 있습니다.';
    end if;
    insert into public.rate_events (ip_hash, kind, target) values (ip, 'insert', new.id);
  end if;
  -- (v3) 만료 작품이 잡고 있던 슬롯 비우기 + 서버 값 강제
  if new.slot_id is not null then
    delete from public.exhibits
     where slot_id = new.slot_id and not in_hall and expires_at is not null and expires_at <= now();
  end if;
  new.in_hall := false;
  new.expires_at := now() + interval '14 days';
  return new;
end;
$$;
drop trigger if exists exhibits_before_insert on public.exhibits;
create trigger exhibits_before_insert before insert on public.exhibits
  for each row execute function public.exhibits_before_insert();

-- ---------- v4-4. 공감 +1: v3 동작 + 공감 제한 ----------
create or replace function public.increment_empathy(exhibit_id text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n  integer;
  ip text := public.client_ip_hash();
begin
  if ip is not null then
    perform pg_advisory_xact_lock(hashtext('fm-rate:' || ip));
    if (select count(*) from public.rate_events
         where ip_hash = ip and kind = 'empathy' and target = exhibit_id and at > now() - interval '1 day') >= 3 then
      raise exception 'empathy_limited' using errcode = 'P0001',
        hint = '같은 네트워크에서 한 작품에 하루 3번까지 공감할 수 있습니다.';
    end if;
    if (select count(*) from public.rate_events
         where ip_hash = ip and kind = 'empathy' and at > now() - interval '1 minute') >= 20 then
      raise exception 'rate_limited_empathy' using errcode = 'P0001',
        hint = '공감을 너무 빠르게 보내고 있습니다.';
    end if;
  end if;
  update public.exhibits set empathy = empathy + 1
   where id = exhibit_id and (in_hall or expires_at is null or expires_at > now())
  returning empathy into n;
  if n is not null then
    if ip is not null then
      insert into public.rate_events (ip_hash, kind, target) values (ip, 'empathy', exhibit_id);
    end if;
    perform public.refresh_hall();
  end if;
  return n;
end;
$$;
revoke all on function public.increment_empathy(text) from public;
grant execute on function public.increment_empathy(text) to anon, authenticated;

-- ---------- v4-5. 오래된 제한 기록 매일 정리 (pg_cron 이 있을 때) ----------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('failure-museum-rate-cleanup', '30 18 * * *',
      $cron$delete from public.rate_events where at < now() - interval '2 days'$cron$);
  else
    raise notice 'pg_cron 이 꺼져 있어 rate_events 정리 작업을 등록하지 못했습니다. Database → Extensions 에서 켠 뒤 다시 실행하세요.';
  end if;
end $$;

-- ---------- 확인용 쿼리 (실행 결과가 보이면 설정 완료) ----------
select
  (select count(*) from public.exhibits)                                            as exhibits_rows,
  (select public from storage.buckets where id = 'exhibit-photos')                   as bucket_public,
  (select count(*) from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'exhibits')                 as realtime_on,
  (select count(*) from pg_extension where extname = 'pg_cron')                      as pg_cron_on,
  (select count(*) from pg_proc where proname = 'client_ip_hash')                    as rate_limit_on;
