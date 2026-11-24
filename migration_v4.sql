-- ============================================================
--  실패 박물관 v4 마이그레이션 · 서버 측 남용 제한
--  운영 중인 DB(schema.sql 또는 migration_v3.sql 적용 후)에 SQL Editor 로 한 번 실행하세요.
--  여러 번 실행해도 안전합니다. 새 프로젝트는 schema.sql 에 이미 들어 있습니다.
--
--  publishable/anon 키는 웹페이지에 공개되므로, 브라우저(localStorage)만으로는 스크립트로 등록·공감을
--  무한히 보내는 것을 막을 수 없습니다. 그래서 요청한 IP 기준으로 서버에서 한 번 더 제한합니다.
--    · 등록: 같은 IP 10분에 5건 / 사이트 전체 10분에 60건 (넘으면 rate_limited_insert / rate_limited_global)
--    · 공감: 같은 IP·같은 작품 하루 3번 (empathy_limited), 같은 IP 1분에 20번 (rate_limited_empathy)
--      (학교·회사 와이파이처럼 여러 사람이 IP 하나를 함께 쓰는 경우를 생각해 작품당 1번이 아니라 3번)
--  IP 원문은 저장하지 않고 SHA-256 해시만 남기며, 2일 지난 기록은 매일 지웁니다.
--  SQL Editor·cron 처럼 API 밖에서 실행하면(request.headers 없음) 제한하지 않습니다.
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

-- ---------- 확인용 ----------
select
  (select count(*) from public.rate_events)                                          as rate_events_rows,
  (select count(*) from pg_proc where proname = 'client_ip_hash')                    as has_ip_hash,
  (select count(*) from pg_extension where extname = 'pg_cron')                      as pg_cron_on;
