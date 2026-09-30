-- ============================================================
--  실패 박물관 · migration_v3.sql  (v2 → v3: 전시 슬롯 · 전당 in_hall · 2주 뒤 철거)
--  이미 운영 중인 DB 에 적용합니다. Supabase 대시보드 → SQL Editor → New query 에 이 파일 전체를 붙여넣고 [Run].
--  여러 번 실행해도 안전합니다 (if not exists / create or replace / drop ... if exists).
--  권장 순서: (1) Database → Extensions 에서 pg_cron 켜기 → (2) 이 파일 실행 → (3) 맨 아래 확인 결과 보기
--
--  기존 작품 처리:
--   - expires_at: 이 마이그레이션을 실행한 시각 + 14일 (옛 작품이 바로 지워지지 않게 등록일이 아니라 적용일 기준)
--   - in_hall   : 지금 공감 상위 5(공감 1 이상)는 전당으로 → expires_at = null (영구 보존)
--   - slot_id   : 전당이 아닌 작품을 오래된 순서로 중앙홀부터 가까운 빈 슬롯에 배정
--                 (index.html 이 slot_id 없는 작품을 화면에 놓는 순서와 같은 기준)
-- ============================================================

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

-- ---------- 기존 작품: 전당 계산 → 빈 슬롯 배정 ----------
select public.refresh_hall();

with free as (
  select s.slot, row_number() over (order by s.ord) as rn
    from unnest(array[
    'hall-05', 'hall-12', 'hall-04', 'hall-11', 'hall-06', 'hall-13', 'hall-03', 'hall-10', 'hall-16', 'hall-17',
    'hall-07', 'hall-14', 'hall-02', 'hall-09', 'hall-20', 'hall-21', 'hall-01', 'hall-08', 'hall-15', 'hall-18',
    'hall-19', 'hall-22', 'lazy-08', 'dead-07', 'lazy-06', 'dead-06', 'unfin-03', 'dead-08', 'lazy-07', 'regret-05',
    'unfin-01', 'regret-01', 'dead-04', 'unfin-04', 'regret-06', 'lazy-05', 'unfin-02', 'regret-02', 'regret-07', 'dead-05',
    'cry-08', 'lazy-04', 'lazy-03', 'dead-01', 'regret-18', 'regret-03', 'unfin-15', 'regret-17', 'regret-19', 'lazy-02',
    'dead-02', 'regret-16', 'regret-20', 'unfin-08', 'lazy-01', 'dead-03', 'regret-21', 'unfin-16', 'cry-07', 'unfin-09',
    'regret-22', 'unfin-11', 'regret-10', 'regret-09', 'regret-11', 'unfin-17', 'regret-08', 'regret-12', 'unfin-05', 'regret-23',
    'regret-04', 'unfin-10', 'unfin-12', 'regret-13', 'unfin-06', 'regret-14', 'unfin-13', 'regret-15', 'unfin-07', 'lobby-02',
    'lobby-03', 'lobby-01', 'lobby-04', 'unfin-14', 'cry-06', 'cry-01', 'cry-05', 'cry-02', 'cry-04', 'cry-03'
  ]) with ordinality as s(slot, ord)
   where not exists (select 1 from public.exhibits e where e.slot_id = s.slot and not e.in_hall)
), need as (
  select id, row_number() over (order by created_at, id) as rn
    from public.exhibits
   where slot_id is null and not in_hall
)
update public.exhibits e
   set slot_id = f.slot
  from need n join free f on f.rn = n.rn
 where e.id = n.id;
-- (정적 슬롯 90개보다 작품이 많으면 남은 작품은 slot_id 가 비어 있고, 앱이 별관 슬롯을 계산해 claim_slot 으로 기록합니다)

-- ---------- 확인 (한 줄이 나오면 성공) ----------
select
  (select count(*) from public.exhibits)                                   as exhibits_rows,
  (select count(*) from public.exhibits where slot_id is not null)         as with_slot,
  (select count(*) from public.exhibits where in_hall)                     as in_hall,
  (select count(*) from public.exhibits where expires_at is null)          as permanent,
  (select min(expires_at) from public.exhibits)                            as next_expiry,
  (select count(*) from pg_extension where extname = 'pg_cron')            as pg_cron_on;
-- pg_cron 작업이 등록됐는지 (pg_cron 을 켠 경우에만 실행):
--   select jobname, schedule, command from cron.job where jobname = 'failure-museum-expire';
