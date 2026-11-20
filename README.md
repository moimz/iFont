# iFont

SVG 아이콘을 모아 **아이콘 웹폰트**(woff2 · css)를 만드는 macOS 앱입니다.
Fontello · IcoMoon 처럼 쓰되, 아이콘 세트와 폰트를 내 맥(그리고 iCloud)에 두고 관리합니다.

## 기능

**아이콘그룹** — 원본 아이콘을 모아 두는 곳
- 기본 아이콘그룹: **Lucide**(ISC, 2,052개)·**Tabler Icons**(MIT, 5,491개)가 앱에 들어 있다. 고칠 수 없고(자물쇠) iCloud 로 동기화하지 않으며, 복사·폰트에 추가·다른 그룹으로 복사해 쓴다
- SVG 파일·폴더, SVG 폰트, 폰트 파일(+ CSS)에서 아이콘 넣기
- 선(stroke) 그룹은 중심선과 선 굵기를 그대로 보관해, 폰트로 내보낼 때 굵기를 바꿀 수 있음
- 분류 · 키워드 · 검색, 24px 격자 여백 보기, 넘친 아이콘 "여백 맞추기"
- 선 굵기를 적용한 SVG 복사(⌘C) · 다운로드(여러 개면 zip)

**폰트** — 그룹에서 골라 담은 아이콘으로 만드는 웹폰트
- 아이콘그룹에서 사이드바의 폰트로 끌어다 놓아 추가
- 폰트 안 그룹(섹션), 순서, 유니코드 코드(`\e600` …) 정리, 그룹별 코드 다시 매기기
- 선 굵기, 크기 배율(선 굵기는 그대로 두고 em 가운데 기준으로 키움), em 크기, Ascent / Descent, CSS 접두어 · 주석 머리말(@file · @author · @license)
- 버전 = `큰 버전.아이콘 수.내려받은 횟수` (예: `5.339.2`)
- 내보내기: **woff2 · svg · css · 미리보기 html**
- 아이콘 원본이 바뀌면 원본과 연결된 폰트 글리프도 따라 바뀜

**그 밖**
- 모든 폰트·그룹 전체 검색 (이름, 키워드, `\e600` 코드)
- Fontello `config.json` 으로 폰트 가져오기
- 파일 › 내보내기… / 불러오기… — 모든 폰트·그룹을 JSON 하나로 백업, 불러올 때는 병합
- iCloud Drive 동기화 (로그인돼 있지 않으면 이 맥에만 저장)
- 자동 업데이트 (Sparkle): 하루 한 번 GitHub 릴리즈에서 새 버전을 확인하고 설치할지 묻는다. 메뉴 iFont › 업데이트 확인…, 설정(⌘,)에서 끄기

## 요구 사항

- macOS 26 이상, Apple silicon(arm64)
- 빌드: Xcode 26 이상

외부 패키지는 자동 업데이트용 [Sparkle](https://sparkle-project.org)(MIT) 하나뿐이고, 나머지는 Apple 기본 프레임워크(SwiftUI, CoreGraphics, CoreText, Compression)입니다.
woff2 의 Brotli 압축은 Apple `Compression` 을 씁니다.

## 빌드

```bash
git clone https://github.com/moimz/iFont.git
open iFont/iFont.xcodeproj
```

프로젝트는 moimz 팀(Developer ID, iCloud 컨테이너 `iCloud.com.moimz.iFont`)으로 서명하도록 설정돼 있습니다.
직접 빌드하려면 타깃의 **Signing & Capabilities** 에서 팀과 번들 ID를 내 것으로 바꾸고,
iCloud 컨테이너도 내 것으로 바꾸거나 iCloud 기능을 빼세요. iCloud 를 쓸 수 없으면 앱은
`~/Library/Application Support/iFont` 에 저장합니다.

## 데이터 위치

| 저장소 | 경로 |
|---|---|
| iCloud | `~/Library/Mobile Documents/iCloud~com~moimz~iFont/Data/{Fonts,IconGroups}/<UUID>.json` |
| 이 맥만 | `~/Library/Application Support/iFont/{Fonts,IconGroups}/<UUID>.json` |

폰트·그룹 하나가 JSON 파일 하나입니다. 앱 밖에서 고쳤다면 파일 › 모두 다시 읽기(⌘R).

## 아이콘 라이선스

기본 아이콘그룹(`iFont/BuiltIn/`)은 Lucide(ISC)·Tabler Icons(MIT) 그대로이며 라이선스 원문은 `iFont/BuiltIn/Licenses.txt`
(앱의 iFont에 관하여 › 라이선스 전문 보기)에 있습니다. 이 아이콘이나 직접 들여온 아이콘으로 만든 폰트를 배포할 때는
각 아이콘 세트의 라이선스를 따르고 그 문구를 함께 넣으세요.
예를 들어 Apple SF Symbols 는 Apple 플랫폼 앱 안에서만 쓸 수 있어 웹폰트로 만들면 안 됩니다.

## 라이선스

[MIT](LICENSE) © 2026 moimz
