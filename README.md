# AsciiPaint Runtime Studio

LLM-사람 협업용 ASCII UI 편집기 (Flutter Windows/Desktop).

## 주요 기능

- ASCII 캔버스 직접 편집: 선택, 이동(`Q`), 리사이즈(`W`), 핸들 조작
- 컴포넌트 팔레트: `box`, `label`, `line`, `stack`, `grid`, `button`, `input`, `toggle`, `tab`, `combo`, `list`, `popup`
- Kind별 프로퍼티 편집기 + 타입 힌트 (`string`, `int`, `bool`, `list<string>`)
- 노드별 `llmComment` 편집
- 우측 고정 YAML Hierarchy + 선택 노드 YAML 확인
- 멀티 페이지 프로젝트
  - 페이지 탭 전환
  - 페이지 추가/삭제/이름변경
  - 페이지별 LLM 코멘트
- 프로젝트 저장/로드
  - 상단 컨트롤에서 `Save`, `Save As`, `Load`
  - 최근 프로젝트(Recent) 목록
  - 저장 성공/실패 팝업
- 로컬 HTTP Control API (`127.0.0.1`) 제공

## 실행

```bash
flutter pub get
flutter run -d windows
```

## 빌드

```bash
flutter build windows --debug
```

## 단축키

- `Ctrl + Z`: Undo
- `Ctrl + Y` 또는 `Ctrl + Shift + Z`: Redo
- `Q`: Move 모드
- `W`: Resize 모드

## 프로젝트 저장 형식

- UI 본문: `<project-root>/ui/main.yaml`
- 메타: `<project-root>/project.yaml`
- 스냅샷: `<project-root>/.asciipaint/history/*.snapshot.yaml`
- 에디터 config(최근 프로젝트): `%USERPROFILE%/.asciipaint/config.json`

## HTTP API

서버는 실행 시 토큰을 발급합니다. (`/health` 제외 토큰 필요)

- `GET /health` (token 불필요)
- `POST /yaml/validate`
- `POST /render/preview`
- `POST /canvas/patch`
- `POST /project/load`
- `POST /project/save`
- `POST /session/reset`

요청 헤더:

- `x-asciipaint-token: <token>`

### patch 예시

```json
{
  "op": "set_bounds",
  "id": "demo_button",
  "x": 8,
  "y": 5,
  "width": 28,
  "height": 3
}
```

## 개발 검증

```bash
flutter analyze
flutter test
```
