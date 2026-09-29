# 실패 박물관 (Failure Museum)

> 이곳의 모든 전시품은 한때 의욕이 있었습니다.

망한 프로젝트·계획·다짐을 **벽에 거는 액자**로 안치하는 3D 웹 박물관입니다. 장례식장처럼 엄숙한 톤에 한심한 내용만 전시합니다. 공감을 받은 실패는 **불멸의 흑역사관**에 금색 대형 액자로 걸립니다. 박물관은 텅 빈 채로 시작하고, 방문자가 등록한 작품만 전시됩니다.

- 공개 URL: https://kimw0n.github.io/failure-museum/
- 단일 `index.html` (CSS/JS 인라인, 빌드 도구 없음) · Three.js 0.170 · supabase-js 2.117.2 (jsdelivr esm)
- 3D 오브젝트는 기본 도형 조합, 사운드는 WebAudio 합성 (외부 에셋 없음)

## 전시 방식

| 구역 | 내용 |
| --- | --- |
| 입구 로비 | 슬픔 안내데스크, 관장 NPC, 방문객 전광판, 방향 표지판 |
| 신규 안치실 (왼쪽) | 최근 등록 3점. 액자 아래 "방금 도착" 리본과 조화 |
| 메인홀 (정면) | 나머지 작품을 벽을 따라 최신순으로 배치. 9점부터 가운데 칸막이 벽이 생기고, 작품이 늘면 복도가 길어짐 (최대 90점, 나머지는 "지하 수장고") |
| 불멸의 흑역사관 (오른쪽 계단 위) | 공감 1개 이상인 작품 중 상위 5점. 금색 대형 액자 + "명예 실패자" 리본 + 1~5위 받침대 + 스포트라이트 + 붉은 카펫. 빈 자리는 "공석" 액자 |

- **사진이 있는 작품**: 사진 액자(비율 유지) + 아래 명패(제목·사망 원인·향년·유품·묘비명·공감 수)
- **사진이 없는 작품**: 사망 원인별 배경색의 "문구 액자"(제목 + 묘비명) + 모서리 사인 뱃지 + 아래 명패
  - 귀찮음=회색, 마감=빨강, 의욕 증발=베이지, 팀원 잠수=파랑, 알고 보니 이미 있던 서비스=초록, 그냥 잠=보라, 기타=아이보리
- 모든 액자는 id로 고정된 ±3° 기울기로 살짝 삐뚤게 걸림. 일반관은 어두운 나무 액자, 전당은 금색 대형 액자
- 액자를 클릭/탭하거나 E키 → 상세 패널(사진 크게 보기, 공감, 명패 이미지 저장 — 사진 포함)

## 조작

- 데스크톱: 화면 클릭(시점 고정) → WASD 이동, 마우스 둘러보기, Shift 빠르게, 액자 조준 후 클릭/E, Esc 커서 해제
- 모바일: 화면 왼쪽 드래그 = 가상 조이스틱, 오른쪽 드래그 = 시야, 액자 탭 또는 [자세히 보기] 버튼
- 우측 상단: **연결 상태 점**(초록 = 실시간, 노랑 = 5초 폴링, 빨강 = 오프라인/로컬 모드) · 내 실패 전시하기 · 음소거 · 도움말

## Supabase 설정 순서 (직접 하셔야 하는 부분)

`index.html` 맨 위 `CONFIG`가 비어 있으면 화면 상단에 **"⚠ 로컬 모드: 다른 방문자와 공유되지 않습니다"** 배너가 뜨고, 등록/공감이 내 브라우저에만 저장됩니다. 모두가 같은 박물관을 보려면 아래 순서대로 한 번만 설정하세요. (화면 문구는 Supabase가 가끔 바꿉니다. 비슷한 이름을 찾으면 됩니다.)

1. **프로젝트 만들기**
   1. https://supabase.com 접속 → 오른쪽 위 **Start your project** 또는 **Sign in** → GitHub 계정으로 로그인
   2. **New project** 클릭 → Organization 선택(처음이면 개인 조직을 만들라고 나옵니다)
   3. **Project name**: `failure-museum`, **Database Password**: 아무 강한 비밀번호(**Generate a password** 눌러도 됨, 따로 적어 두세요), **Region**: `Northeast Asia (Seoul)` → **Create new project**
   4. 1~2분 기다리면 프로젝트 대시보드가 열립니다.
2. **SQL Editor에서 `schema.sql` 실행**
   1. 왼쪽 세로 메뉴에서 **SQL Editor** (`>_` 모양 아이콘) 클릭
   2. **+ New query**(또는 New SQL snippet) 클릭
   3. 이 저장소의 [`schema.sql`](schema.sql) 내용을 **전부** 복사해서 붙여넣기
   4. 오른쪽 아래 **Run** 클릭 (또는 Ctrl/Cmd + Enter). "destructive operation" 경고가 뜨면 **Run this query** 선택 (시드 삭제 문장 때문이며, 새 프로젝트에서는 지울 게 없습니다)
   5. 아래 Results에 `exhibits_rows 0 · bucket_public true · realtime_on 1` 한 줄이 보이면 성공
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

### 운영 메모

- 부적절한 전시품 삭제: **Table Editor → exhibits**에서 행 삭제, 사진은 **Storage → exhibit-photos**에서 `<id>.jpg` 삭제. (클라이언트는 수정·삭제 권한이 없어 대시보드에서만 가능. 삭제는 실시간으로 전파되지 않으므로 다른 방문자 화면에서는 새로고침 후 사라집니다.)
- 공감 수 보정: SQL Editor에서 `update exhibits set empathy = 0 where id = '...';`
- 방문객 수 초기화: `update visit_counter set count = 0;`
- `schema.sql`은 다시 실행해도 안전합니다(정책·제약을 덮어씀).

## 데이터 흐름

- **등록**: 브라우저가 UUID를 만들고 즉시(낙관적으로) 신규 안치실에 액자를 건 뒤 → 사진이 있으면 Storage에 `<id>.jpg` 업로드 → `exhibits`에 insert. 실시간 이벤트와 서버 응답은 같은 id로 합쳐지므로 중복 액자가 생기지 않습니다. 실패하면 액자를 내리고, 입력값을 그대로 둔 채 폼을 다시 엽니다.
- **사진**: `image/*`만, 원본 5MB 초과 거절 → Canvas로 긴 변 1000px · JPEG 0.8 → 500KB를 넘으면 품질을 낮추고 그래도 크면 크기를 줄여 재압축. 액자에는 `THREE.TextureLoader`로 로드(sRGB, 로딩 전 회색, 비율 유지). 가까이 있거나 화면 안에 있는 액자만 텍스처를 만들고, 멀어지면 dispose합니다.
- **공감**: 누르는 즉시 +1 표시 → `increment_empathy` RPC → 서버 값으로 확정, 실패하면 되돌림. 브라우저당 작품 1회(localStorage).
- **실시간**: supabase-js Realtime으로 `exhibits`의 INSERT/UPDATE 구독 → 새 액자는 떨어지며 걸리고, 공감 수·순위가 즉시 갱신되며 순위가 오르면 "속보" 토스트. 연결이 끊기면 5초 폴링으로 전환하고, 탭이 다시 보이면(visibilitychange) 즉시 한 번 동기화, 연결이 돌아오면 다시 실시간으로 복귀합니다.

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
- [ ] 빈 박물관: 메인홀 벽에 "아직 아무도 실패하지 않았습니다. 첫 번째 고인이 되어주세요"와 빈 액자, 관장 멘트 "전시품이 없습니다…"
- [ ] 사진 없이 등록 → 사망 원인 색 문구 액자 + 뱃지가 신규 안치실에 떨어지며 걸림 + 트롬본 + "삼가 명복을 빕니다"
- [ ] 사진 첨부 등록 → 미리보기/사진 지우기 동작, 액자에 사진 표시
- [ ] 시크릿 창 두 개: A에서 등록하면 B에 새로고침 없이 액자가 나타남, A에서 공감하면 B의 명패 숫자가 바뀜
- [ ] 공감이 모여 상위 5위 안에 들면 전당 금액자로 이동 + "속보" 토스트
- [ ] 상세 패널에서 사진 크게 보기, "명패 이미지로 저장" PNG에 사진 포함
- [ ] Wi-Fi를 끄면 점이 빨강 → 켜면 다시 초록 (중간에 노랑일 수 있음)

### 모바일 (iOS Safari / Android Chrome)

- [ ] 사진 첨부 시 카메라/앨범 선택이 뜨고, 세로 사진도 방향이 맞게 들어감
- [ ] 5MB 넘는 사진·이미지가 아닌 파일은 안내 문구와 함께 거절
- [ ] 왼쪽 드래그 이동, 오른쪽 드래그 시야, 액자 탭 → 하단 시트
- [ ] 사진 액자가 20장 넘게 걸린 메인홀을 걸어도 끊김이 심하지 않음
- [ ] 노치 영역에 배너/버튼이 가려지지 않음

## 파일

- `index.html` — 앱 전체 (설정 · 씬 · 액자 · 동기화 · NPC · 사운드)
- `schema.sql` — Supabase 테이블/RLS/RPC/Realtime/Storage
- 디버그: 브라우저 콘솔에서 `FM.stats`(draw call·텍스처·fps), `FM.status`(연결 상태), `FM.tp(25, 7, -Math.PI / 2)`(전당 앞으로 이동)
