# 실패 박물관 (Failure Museum)

> 이곳의 모든 전시품은 한때 의욕이 있었습니다.

망한 프로젝트·계획·다짐을 **벽에 거는 액자**로 안치하는 3D 웹 박물관입니다. 장례식장처럼 엄숙한 톤에 한심한 내용만 전시합니다. 공감을 받은 실패는 **불멸의 흑역사관**에 금색 대형 액자로 걸립니다. 박물관은 텅 빈 채로 시작하고, 방문자가 등록한 작품만 전시됩니다.

- 공개 URL: https://kimw0n.github.io/failure-museum/
- 단일 `index.html` (CSS/JS 인라인, 빌드 도구 없음) · Three.js 0.170 · supabase-js 2.117.2 (jsdelivr esm)
- 3D 오브젝트는 기본 도형 조합, 사운드는 WebAudio 합성 (외부 에셋 없음)

## 박물관 구조 (순환 동선)

| 구역 | 내용 |
| --- | --- |
| 입구 로비 | 슬픔 안내데스크, 관장 NPC, 방문객 전광판, 방향 표지판. 북쪽 = 중앙홀, 서쪽 = 울음방, 동쪽 = 전당 계단 |
| 중앙홀 | 대리석 바닥, 기둥 6개, 가운데 **거대한 깨진 트로피**("참가상") + 로프 스탠션, 바닥 안내선 |
| 후회의 회랑 | 폭 3m · 약 33m 나무 바닥 복도(코너 1번, 입구 아치). 양쪽 벽에 액자가 마주 보고 걸림 → 울음방으로 이어짐 |
| 울음방 | 옛 신규 안치실. 카펫, 조화·화환, 긴 의자 → 로비로 이어짐 |
| 미완성 갤러리 | ㄷ자 복도, 낮은 천장, 러그, 그리다 만 이젤. 끝은 마감의 방 문 |
| 귀찮음의 방 / 마감의 방 | 침대·이불 + 어두운 조명 / 벽시계 여러 개 + 붉은 조명. 두 방 사이에 문 |
| 불멸의 흑역사관 (계단 위) | 공감 상위 5점. 금색 대형 액자 + 1~5위 받침대 + 금빛 스포트라이트 |
| 별관 | 슬롯이 모두 차면 후회의 회랑 코너에서 서쪽으로 4칸씩 늘어나는 복도 |

순환: 로비 → 중앙홀 → 후회의 회랑 → 울음방 → 로비 / 중앙홀 → 귀찮음 → 마감 → 중앙홀 / 중앙홀 → 미완성 갤러리 → 마감 → 중앙홀. (전당은 계단 하나로만 오가는 2층이라 들어간 길로 나옵니다. 별관도 늘어나는 막다른 복도입니다.)

## 전시 방식

- 벽 곳곳의 **빈 액자**(회색 캔버스 + 금이 간 프레임 + "여기에 전시하세요")가 전시 자리(슬롯)입니다. 슬롯 90개는 `index.html`의 `SLOTS`(구역·위치·방향·크기)로 정의돼 있고, 전당에는 슬롯이 없습니다.
- 빈 액자를 4m 안에서 조준하면 금색 테두리 + **[E] 여기에 전시하기** → 등록 폼 → 그 자리에 떨어지며 걸리고 액자등이 "딸깍" 켜집니다. 상단 **내 실패 전시하기** 버튼은 지금 위치에서 가장 가까운 빈 액자에 겁니다.
- 같은 자리에 두 사람이 동시에 걸면 DB가 한쪽을 거절하고, 앱이 "방금 다른 분이 먼저 전시했습니다" 안내 후 가장 가까운 빈 액자로 자동 재배정합니다. 작성 중에 누가 먼저 차지해도 바로 알려 줍니다.
- 공감 상위 5점은 전당으로 올라가고 원래 자리는 빈 액자로 돌아갑니다. 밀려나면 원래 자리(비어 있으면) 또는 가장 가까운 빈 자리로 돌아옵니다.
- **사진이 있는 작품**: 사진 액자 + 아래 명패 / **사진이 없는 작품**: 사망 원인별 배경색 문구 액자 + 사인 뱃지 + 명패
  - 귀찮음=회색, 마감=빨강, 의욕 증발=베이지, 팀원 잠수=파랑, 알고 보니 이미 있던 서비스=초록, 그냥 잠=보라, 기타=아이보리
- 명패와 상세 패널에 남은 기간(**철거까지 D-9**, 전당은 **영구 보존**). 철거 3일 전부터 명패에 붉은 **철거 예정** 스티커, 액자등이 자주 깜빡입니다.
- 조명: 모든 액자에 액자등 메시 + 가짜 빛(가산 평면, 벽의 원뿔형 광). 실제 SpotLight는 가까운 액자 6개(모바일 4개)에만 붙습니다. 어두우면 ⚙ 설정의 **밝기** 슬라이더.

## 자동 철거 정책 (2주)

- 일반 전시는 등록 후 **14일** 뒤 철거됩니다(`expires_at`). 전당에 있는 동안은 `expires_at = null`(영구 보존), 전당에서 밀려나면 그때부터 다시 14일.
- 전당 계산은 클라이언트가 아니라 DB가 합니다: 공감 RPC `increment_empathy` 안에서 `refresh_hall()`이 상위 5를 다시 계산해 `in_hall`·`expires_at`을 바꿉니다.
- 삭제는 pg_cron이 매일 03:00(KST)에 `delete from exhibits where expires_at is not null and expires_at < now()` 실행. cron이 늦어도 앱은 만료 작품을 조회하지 않고(조회 조건 `expires_at is null or expires_at > now()`), 화면에 떠 있던 것도 15초 안에 내립니다. 삭제는 실시간으로 다른 방문자 화면에서도 사라집니다.
- 삭제되면 트리거가 Storage 사진(`exhibit-photos/<id>.jpg`)도 지우려 시도합니다. **최근 Supabase 프로젝트는 SQL로 Storage 파일을 직접 지우는 것을 막아 두어 실패할 수 있고**, 그때는 작품 삭제는 정상 진행되고 파일 이름만 `photo_cleanup_queue` 테이블에 남습니다 → 아래 "사진 수동 정리".

## 조작

- 데스크톱: 화면 클릭(시점 고정) → WASD 이동, 마우스 둘러보기, Shift 빠르게
  - **E**: 상호작용/전시 — 조준한 액자 자세히 보기, 빈 액자에 전시하기, 관장에게 말 걸기
  - **Q**: 열린 창 닫기(뒤로가기) — 사진 크게 보기 → 상세 패널 → 등록 창(작성 중이면 확인) → 전시 위치 선택 → 도움말·설정·확대 미니맵 순서로 **한 단계씩**. 위치·시야는 움직이지 않고, 닫을 게 없으면 아무 일도 안 함. 입력창에서는 그냥 글자 q
  - **Esc**: Q와 같음 (시점 고정 중 첫 Esc는 브라우저가 커서 해제에 사용)
  - **M**: 미니맵 접기/펴기, 미니맵 클릭 = 크게 보기
- 모바일: 왼쪽 드래그 = 가상 조이스틱, 오른쪽 드래그 = 시야, 액자 탭 = 자세히 보기, 빈 액자 탭 = 전시, 좌측 하단 **✕ 닫기**(닫을 창이 있을 때만), 미니맵 탭 = 크게 보기
- 우측 상단: **연결 상태 점**(초록 = 실시간, 노랑 = 5초 폴링, 빨강 = 오프라인/로컬 모드) · 내 실패 전시하기 · 음소거 · ⚙ 설정(밝기) · 도움말 · 미니맵

## Supabase 설정 순서 (직접 하셔야 하는 부분)

`index.html` 맨 위 `CONFIG`가 비어 있으면 화면 상단에 **"⚠ 로컬 모드: 다른 방문자와 공유되지 않습니다"** 배너가 뜨고, 등록/공감이 내 브라우저에만 저장됩니다. 모두가 같은 박물관을 보려면 아래 순서대로 한 번만 설정하세요. (화면 문구는 Supabase가 가끔 바꿉니다. 비슷한 이름을 찾으면 됩니다.)

1. **프로젝트 만들기**
   1. https://supabase.com 접속 → 오른쪽 위 **Start your project** 또는 **Sign in** → GitHub 계정으로 로그인
   2. **New project** 클릭 → Organization 선택(처음이면 개인 조직을 만들라고 나옵니다)
   3. **Project name**: `failure-museum`, **Database Password**: 아무 강한 비밀번호(**Generate a password** 눌러도 됨, 따로 적어 두세요), **Region**: `Northeast Asia (Seoul)` → **Create new project**
   4. 1~2분 기다리면 프로젝트 대시보드가 열립니다.
2. **SQL Editor에서 `schema.sql` 실행** (새 프로젝트. 이미 운영 중이면 아래 "v3 마이그레이션")
   1. 왼쪽 세로 메뉴에서 **SQL Editor** (`>_` 모양 아이콘) 클릭
   2. **+ New query**(또는 New SQL snippet) 클릭
   3. 이 저장소의 [`schema.sql`](schema.sql) 내용을 **전부** 복사해서 붙여넣기
   4. 오른쪽 아래 **Run** 클릭 (또는 Ctrl/Cmd + Enter). "destructive operation" 경고가 뜨면 **Run this query** 선택 (시드 삭제 문장 때문이며, 새 프로젝트에서는 지울 게 없습니다)
   5. 아래 Results에 `exhibits_rows 0 · bucket_public true · realtime_on 1 · pg_cron_on 1` 한 줄이 보이면 성공 (`pg_cron_on`이 0이면 Database → Extensions에서 pg_cron을 켜고 다시 실행)
3. **Storage 버킷 확인**
   1. 왼쪽 메뉴 **Storage** 클릭
   2. 버킷 목록에 **exhibit-photos**가 있고 옆에 **Public** 표시가 있는지 확인
   3. (선택) 버킷 이름 → 오른쪽 위 설정(⋯ → Edit bucket)에서 파일 크기 제한 1MB, 허용 형식 `image/jpeg, image/png, image/webp`인지 확인. 앱은 사진을 500KB 이하 JPEG로 줄여서 올립니다.
4. **Realtime이 켜졌는지 확인**
   1. 왼쪽 메뉴 **Database** → 안쪽 메뉴 **Publications** 클릭
   2. **supabase_realtime** 행의 테이블 목록(또는 "1 table" 링크)을 열어 **exhibits** 스위치가 켜져 있는지 확인. 꺼져 있으면 켜기
   3. (다른 확인 방법) **Table Editor → exhibits** 화면 위쪽에 "Realtime on" 같은 표시가 있으면 켜진 것
5. **URL / 키를 `CONFIG`에 넣기**
   1. 왼쪽 아래 **Project Settings**(톱니바퀴) → **Data API** 또는 **API**에서 **Project URL** 복사 (`https://xxxx.supabase.co`)
   2. 같은 설정의 **API Keys**에서 **Publishable key**(`sb_publishable_...`) 또는 Legacy 탭의 **anon public** 키(`eyJ...`) 복사 — 둘 중 하나면 됩니다
   3. **절대 `service_role` / `secret` 키는 넣지 마세요.** (publishable/anon 키는 공개용이라 웹페이지에 노출돼도 괜찮고, 권한은 위 RLS가 막습니다)
   4. `index.html` 7번째 줄 근처를 이렇게 바꿉니다:
      ```js
      const CONFIG = { SUPABASE_URL: "https://xxxx.supabase.co", SUPABASE_ANON_KEY: "sb_publishable_..." };
      ```
6. **재배포**
   - GitHub 웹에서: https://github.com/kimw0n/failure-museum/edit/main/index.html 열기 → 위 줄 수정 → **Commit changes** → 1~2분 뒤 GitHub Pages가 자동 재배포
   - 또는 로컬에서 수정 후 `git commit` · `git push`
   - 확인: 사이트를 열었을 때 노란 배너가 없고 우측 상단 점이 **초록**이면 성공. 시크릿 창 두 개로 열어 한쪽에서 등록하면 다른 쪽 벽에 액자가 떨어지며 걸립니다.

### v3 마이그레이션 (이미 운영 중인 DB — 직접 하셔야 하는 부분)

v2(이전 버전) 스키마로 운영 중이라면 `schema.sql` 대신 [`migration_v3.sql`](migration_v3.sql)을 실행합니다. 실행 전에도 사이트는 예전 방식(슬롯 기록·자동 철거 없이)으로 동작하고, 실행하면 새로고침 후 자동으로 새 방식이 켜집니다.

1. **pg_cron 켜기**: 왼쪽 메뉴 **Database** → 안쪽 메뉴 **Extensions** → 검색창에 `pg_cron` → 스위치 켜기 → 스키마를 물으면 기본값 그대로 **Enable extension**
2. **마이그레이션 실행**: 왼쪽 메뉴 **SQL Editor** → **+ New query** → `migration_v3.sql` 내용 전부 붙여넣기 → **Run**. "destructive operation" 경고가 나오면 **Run this query** (만료 작품 정리용 delete 문 때문)
3. **결과 확인**: Results에 `exhibits_rows · with_slot · in_hall · permanent · next_expiry · pg_cron_on` 한 줄. `pg_cron_on`이 1이면 정상. 0이면 1번을 하고 2번을 한 번 더 실행
4. **cron 작업 확인**(선택): 새 쿼리에서 `select jobname, schedule, command from cron.job;` → `failure-museum-expire | 0 18 * * *` 가 보이면 됨 (18:00 UTC = 한국 새벽 3시)
5. 사이트 새로고침 → 벽에 빈 액자가 보이고 명패에 "철거까지 D-14"가 나오면 완료

기존 작품은 마이그레이션 시각 + 14일 뒤 철거 예정이 되고(바로 지워지지 않게), 지금 공감 상위 5는 전당(영구 보존), 나머지는 중앙홀부터 가까운 빈 슬롯에 배정됩니다.

### 사진 수동 정리 (삭제 트리거가 Storage 파일을 못 지운 경우)

1. SQL Editor에서 `select name, queued_at from photo_cleanup_queue order by queued_at;` → 지워야 할 파일 이름 목록
2. **Storage** → **exhibit-photos** 버킷 → 목록에서 해당 `<id>.jpg` 체크 → **Delete** (여러 개 선택 가능)
3. 다 지웠으면 `delete from photo_cleanup_queue;`

(주인 없는 사진 찾기: `select o.name from storage.objects o where o.bucket_id = 'exhibit-photos' and not exists (select 1 from exhibits e where e.id || '.jpg' = o.name);`)

### 운영 메모

- 부적절한 전시품 삭제: **Table Editor → exhibits**에서 행 삭제 → 방문자 화면에서 실시간으로 사라지고 빈 액자로 돌아감. 사진은 삭제 트리거가 시도하며, 안 지워졌으면 위 "사진 수동 정리". (클라이언트는 수정·삭제 권한이 없어 대시보드에서만 가능)
- 철거 테스트: `update exhibits set expires_at = now() - interval '1 minute' where id = '...';` → 열린 화면에서 바로 사라짐 (cron 전이라도)
- 영구 보존으로 돌리기(관리자): `update exhibits set expires_at = null where id = '...';`
- 공감 수 보정: SQL Editor에서 `update exhibits set empathy = 0 where id = '...';`
- 방문객 수 초기화: `update visit_counter set count = 0;`
- `schema.sql`은 다시 실행해도 안전합니다(정책·제약을 덮어씀).

## 데이터 흐름

- **등록**: 브라우저가 UUID와 슬롯을 정하고 즉시(낙관적으로) 그 자리에 액자를 건 뒤 → 사진이 있으면 Storage에 `<id>.jpg` 업로드 → `exhibits`에 insert(`slot_id` 포함, 슬롯 충돌 409면 옆 빈 액자로 최대 4번 재시도). 실시간 이벤트와 서버 응답은 같은 id로 합쳐지므로 중복 액자가 생기지 않습니다. 실패하면 액자를 내리고, 입력값을 그대로 둔 채 폼을 다시 엽니다.
- **사진**: `image/*`만, 원본 5MB 초과 거절 → Canvas로 긴 변 1000px · JPEG 0.8 → 500KB를 넘으면 품질을 낮추고 그래도 크면 크기를 줄여 재압축. 액자에는 `THREE.TextureLoader`로 로드(sRGB, 로딩 전 회색, 비율 유지). 가까이 있거나 화면 안에 있는 액자만 텍스처를 만들고, 멀어지면 dispose합니다.
- **공감**: 누르는 즉시 +1 표시 → `increment_empathy` RPC → 서버 값으로 확정, 실패하면 되돌림. 브라우저당 작품 1회(localStorage).
- **실시간**: supabase-js Realtime으로 `exhibits`의 INSERT/UPDATE/DELETE 구독 (전당 진입·철거·슬롯 변경 포함) → 새 액자는 떨어지며 걸리고, 공감 수·순위가 즉시 갱신되며 순위가 오르면 "속보" 토스트. 연결이 끊기면 5초 폴링으로 전환하고, 탭이 다시 보이면(visibilitychange) 즉시 한 번 동기화, 연결이 돌아오면 다시 실시간으로 복귀합니다.

### 어뷰징 방지의 한계

과제 수준으로 **브라우저 localStorage 기준 작품당 공감 1회**만 막습니다. 시크릿 창·다른 브라우저·사이트 데이터 삭제로 다시 누를 수 있고, anon 키로 RPC를 직접 호출해 올릴 수도 있습니다. 사진 업로드도 익명이라 부적절한 사진을 자동으로 거르지 못합니다(파일 이름·크기·형식만 제한). 실서비스라면 익명/소셜 로그인 + `(user_id, exhibit_id)` 유니크 테이블, 서버 측 rate limit, 이미지 검수가 필요합니다. 욕설/광고 필터도 클라이언트의 간단한 금칙어 배열이라 우회가 가능합니다.

## 로컬에서 실행

```bash
python3 -m http.server 8000
```

그다음 http://localhost:8000 을 엽니다. (`CONFIG`가 비어 있으면 로컬 모드 배너가 뜹니다.)

## 확인 체크리스트

### 데스크톱 (Chrome / Safari / Edge)

- [ ] 우측 상단 점이 초록, 상단 노란 배너 없음 (Supabase 설정 후)
- [ ] 상세 패널 → Q → 패널만 닫힘(위치 그대로) / 작성 중 등록 창 → Q → 확인 후 닫힘 / 입력창에서 q 입력 가능 / 열린 창 없을 때 Q는 아무 일 없음
- [ ] 빈 액자 조준 → 금색 테두리 + [E] → 등록 → 그 자리에 떨어지며 걸리고 액자등이 딸깍 켜짐
- [ ] 시크릿 창 두 개: A가 건 작품이 B에 새로고침 없이 나타남 / 같은 빈 액자에 동시에 안치하면 늦은 쪽이 "방금 다른 분이 먼저 전시했습니다" 후 옆 자리로
- [ ] `expires_at`을 과거로 바꾸면 열린 화면에서 액자가 사라지고 빈 액자로 돌아감
- [ ] 공감으로 상위 5에 들면 전당 금액자 + "속보" + 원래 자리는 빈 액자, 상세 패널 "영구 보존"
- [ ] 로비 → 중앙홀 → 후회의 회랑 → 울음방 → 로비, 중앙홀 → 미완성 갤러리 → 마감의 방 → 귀찮음의 방 → 중앙홀 을 막힘없이 걸을 수 있고 벽은 통과 안 됨
- [ ] M으로 미니맵 접기/펴기, 미니맵 클릭 확대 → Q로 닫기, ⚙ 밝기 슬라이더

### 모바일 (iOS Safari / Android Chrome)

- [ ] 빈 액자 탭 → 등록, 창이 열리면 좌측 하단 ✕ 닫기 버튼
- [ ] 사진 첨부 시 카메라/앨범 선택, 세로 사진 방향 정상, 5MB 초과·이미지 아닌 파일 거절
- [ ] 액자가 50점 넘게 걸린 상태에서 걸어 다녀도 끊김이 심하지 않음
- [ ] 노치 영역에 버튼이 가려지지 않음

## 파일

- `index.html` — 앱 전체 (설정 · 씬 · 액자 · 동기화 · NPC · 사운드)
- `schema.sql` — 새 프로젝트용 전체 스키마 (테이블/RLS/RPC/전당 재계산/트리거/pg_cron/Realtime/Storage)
- `migration_v3.sql` — 운영 중인 v2 DB를 v3로 올리는 마이그레이션 (여러 번 실행 안전)
- 디버그: 브라우저 콘솔에서 `FM.stats`(draw call·텍스처·fps), `FM.status`(연결 상태), `FM.tp(25, 7, -Math.PI / 2)`(전당 앞으로 이동), `FM.slotState`(슬롯 사용 현황), `FM.lights`(켜진 광원 수)
