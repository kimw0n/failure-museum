-- ============================================================
--  실패 박물관 (Failure Museum) · Supabase 스키마
--  Supabase 대시보드 → SQL Editor 에 전체를 붙여넣고 실행하세요.
--  여러 번 실행해도 안전합니다 (if not exists / on conflict).
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- 전시품 ----------
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
create index if not exists exhibits_created_at_idx on public.exhibits (created_at desc);
create index if not exists exhibits_empathy_idx    on public.exhibits (empathy desc, created_at);

-- ---------- RLS: 조회/등록만 허용, 수정·삭제는 불가 ----------
alter table public.exhibits enable row level security;

drop policy if exists exhibits_select on public.exhibits;
create policy exhibits_select on public.exhibits
  for select to anon, authenticated using (true);

drop policy if exists exhibits_insert on public.exhibits;
create policy exhibits_insert on public.exhibits
  for insert to anon, authenticated with check (empathy = 0);

-- update / delete 정책은 만들지 않는다 → 클라이언트가 직접 고칠 수 없음.
-- 컬럼 권한: 클라이언트는 내용 필드만 넣을 수 있고 id·empathy·created_at 은 기본값이 강제된다.
revoke insert, update, delete on public.exhibits from anon, authenticated;
grant select on public.exhibits to anon, authenticated;
grant insert (title, cause, age, relic, epitaph) on public.exhibits to anon, authenticated;

-- ---------- 공감 +1 은 이 RPC 로만 ----------
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

-- ---------- 방문객 카운터 ("당신은 N번째 방문객입니다") ----------
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

-- ---------- 시드 전시품 15점 (index.html 의 SEEDS 와 같은 id) ----------
insert into public.exhibits (id, title, cause, age, relic, epitaph, empathy, created_at) values
  ('seed-01', '3일 만에 끝난 새벽 5시 기상 프로젝트', '그냥 잠', '3일', '결제한 알람 앱 프리미엄 (연간)', '알람은 끝까지 울렸다', 140, '2026-08-02T05:00:00Z'),
  ('seed-02', '올해의 다이어트', '의욕 증발', '11시간', '치킨 영수증', '내일의 나에게 모든 것을 맡긴다', 127, '2026-08-04T12:00:00Z'),
  ('seed-03', '헬스장 1년 회원권', '귀찮음', '출석 3회', '샤워만 하고 찍은 출석 도장', '기부 천사로 기억되리', 109, '2026-08-06T19:30:00Z'),
  ('seed-04', '팀플 자료조사', '팀원 잠수', '2주', '아무도 안 연 공유 폴더', '읽씹은 죽음의 첫 단계', 96, '2026-08-09T23:10:00Z'),
  ('seed-05', '하루 영어 단어 30개 외우기', '귀찮음', '4일', '첫 장만 새까만 단어장', 'abandon까지는 외웠다', 88, '2026-08-11T08:00:00Z'),
  ('seed-06', '나만의 투두 앱 만들기', '알고 보니 이미 있던 서비스', '6주', '로고만 완성된 디자인 파일', '세상엔 이미 투두 앱이 4만 개 있었다', 74, '2026-08-14T02:40:00Z'),
  ('seed-07', '반려식물 SNS 창업', '알고 보니 이미 있던 서비스', '2일', '1년치 결제한 도메인', '검색 한 번이면 됐는데', 67, '2026-08-17T15:00:00Z'),
  ('seed-08', '배달앱 없이 한 달 살기', '의욕 증발', '1일', '지웠다가 3초 만에 재설치한 앱', '재설치는 생각보다 빨랐다', 61, '2026-08-20T21:00:00Z'),
  ('seed-09', '기타 독학', 'F코드', '5일', 'C코드만 칠 줄 아는 손가락', 'F코드 앞에서 조용히 눈을 감다', 58, '2026-08-23T17:20:00Z'),
  ('seed-10', '블로그 1일 1포스팅', '마감', '9일', '"첫 글입니다" 임시저장 17개', '첫 글만 17번 썼다', 52, '2026-08-26T10:00:00Z'),
  ('seed-11', '졸업작품 기획서', '마감', '한 학기', '최종_진짜최종_이거진짜.pptx', '마감은 언제나 어제였다', 45, '2026-08-29T03:30:00Z'),
  ('seed-12', '주말 알고리즘 스터디', '팀원 잠수', '2회차', '공지만 남은 단톡방', '"다음 주에 봬요"가 유언이 되었다', 33, '2026-09-02T20:00:00Z'),
  ('seed-13', '매일 일기 쓰기', '그냥 잠', '3쪽', '1월 1일부터 3일까지만 쓴 다이어리', '오늘은 피곤하니 내일 쓴다', 20, '2026-09-08T23:50:00Z'),
  ('seed-14', '경제 뉴스 매일 읽기', '의욕 증발', '1주', '구독만 한 채널 12개', '알림 설정만큼은 완벽했다', 12, '2026-09-15T07:00:00Z'),
  ('seed-15', '미라클 모닝 명상', '그냥 잠', '7분', '"잠들기 좋은 빗소리" 재생 기록', '명상하다 진짜로 명을 달리함', 3, '2026-09-21T06:07:00Z')
on conflict (id) do nothing;
