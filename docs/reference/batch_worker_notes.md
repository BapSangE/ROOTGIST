# 배치 워커 구현 노트 v1

> 비공개 연구 레포(ROOTGIST-research)의 검증된 스크립트에서 **규칙만** 옮겼다(2026-10-21). 연구 스크립트는 실험 데이터 경로와 실제 초록 인용을 포함하므로 이 레포에 복사하지 않는다. 배치 워커는 이 노트와 `docs/contract/`를 기준으로 새로 작성한다.

| 원본(연구 레포) | 이 노트의 절 |
|---|---|
| `scripts/collect.py` | 1. 수집 |
| `scripts/split_sentences.py` (커밋 `d691502` 기준) | 2. 문장 분할 |
| `scripts/p2_inputs.py`, `scripts/p2_run.py` | 3. 모델 입력과 호출 |
| `scripts/p2_validate.py` | 4. 출력 검증 |

## 1. 수집

- 엔드포인트: `GET https://huggingface.co/api/daily_papers?date=YYYY-MM-DD&sort=publishedAt&limit=10&p=<page>` (익명 접근)
- 페이지는 `p=0`부터 올린다. **받은 건수가 `limit`보다 적거나 0이면 멈춘다.** HTTP 200이 아니거나 JSON 파싱에 실패하면 그 날짜는 실패로 기록하고 멈춘다.
- 요청 사이 0.5초 쉬고, 요청마다 시간 제한 30초, 최대 4회 재시도(지수 대기, 기준 2초).
- 실패 응답 본문도 원본으로 보관한다. 요청마다 URL, 상태, 지연, 건수, 저장 위치를 기록한다.
- 필드 경로와 제외 규칙은 `docs/HANDOFF.md` 4.1절. 철회 논문(`withdrawnAt` 있음)은 제외한다.
- 선별·동점 규칙, 다음 날 보충 규칙은 `docs/contract/p2_ops_config_v1.md` 1.1절.

## 2. 문장 분할

생성형 AI가 아니라 **규칙 기반**으로 나눈다. 원문 문자열은 바꾸지 않고 `[start, end)` 오프셋만 기록한다. 각 문장은 `abstract_en[start:end]`이며, 문장 사이 틈에는 공백 문자만 허용한다(왕복 검사).

- 문장 ID: 순서대로 `A01`, `A02`, … (논문 안에서만 유일)
- `kind`: `text`(번역·요약 대상), `link`(라벨과 URL만 있는 줄), `meta`(LaTeX 서식 명령이나 `Keywords:`로 시작하는 조각). `link`·`meta`는 원문에 그대로 두고 번역·요약에서 건너뛴다.
- 분할기를 바꾸면 버전을 올리고 해당 논문의 번역·요약·근거를 모두 다시 만든다. 앱과 서버가 같은 문장 ID를 쓰므로 분할기 버전을 `paper_sentences`에 저장한다.

아래는 연구 레포 분할기의 핵심 로직이다(검토표 생성 부분과 예시 주석은 뺌). 다른 언어로 옮길 때도 이 동작과 같아야 한다.

```python
import re

# 마침표가 붙어도 문장 끝이 아닌 약어(소문자 비교)
ABBREVIATIONS = {
    "e.g", "i.e", "et al", "etc", "vs", "cf", "fig", "figs", "eq", "eqs", "sec", "secs",
    "tab", "approx", "resp", "w.r.t", "no", "nos", "dr", "prof", "al", "ref", "refs",
    "ch", "vol", "est", "incl", "a.k.a", "i.i.d",
    # "pp"는 퍼센트포인트 단위로 문장 끝에 자주 오므로 넣지 않는다
    "gen",   # "Gen. PPL"(generative perplexity)
    "prob",  # "(prob. ...)"(probability)
}
CANDIDATE = re.compile(r"[.!?](?:[\"')\]]*)(?=\s+|$)")
# 마침표 뒤 공백 없이 다음 문장이 붙은 경우("...word.Next ...")
NO_SPACE = re.compile(r"(?<=[a-z]{2})[.!?](?=[A-Z][a-z])")
MATH = re.compile(r"\$[^$]*\$")
LINK_ONLY = re.compile(r"(?:[\w ]{0,40}:\s*)?(?:at\s+)?https?://\S+?[.]?")
# 서식 명령만 meta로 본다. "\method improves ..."처럼 이름 매크로로 시작하는 실제 문장은 text.
META = re.compile(r"(?:\\(?:par|medskip|smallskip|bigskip|noindent|vspace|hspace|newline|linebreak)"
                  r"(?![a-z]))+|Keywords?\s*:")


def kind_of(sentence: str) -> str:
    if LINK_ONLY.fullmatch(sentence):
        return "link"
    if META.match(sentence):
        return "meta"
    return "text"


def protected_spans(text: str):
    """경계를 만들지 않을 구간: 인라인 수식, URL."""
    spans = [m.span() for m in MATH.finditer(text)]
    spans += [m.span() for m in re.finditer(r"https?://\S+", text)]
    return spans


def inside(pos, spans):
    return any(a <= pos < b for a, b in spans)


def token_before(text: str, end: int) -> str:
    """마침표 바로 앞의 토큰(공백 이후부터 마침표 전까지)."""
    start = end
    while start > 0 and not text[start - 1].isspace():
        start -= 1
    return text[start:end]


def split(text: str):
    """(start, end, flags) 목록. end는 문장 끝 문자 다음 위치. flags는 검토용 표시."""
    spans = protected_spans(text)
    sentences, boundaries, nonsplits = [], [], []
    start = 0
    for m in CANDIDATE.finditer(text):
        end, punct = m.end(), m.start()
        if inside(punct, spans):
            continue
        tok = token_before(text, punct).lstrip("([\"'")
        nxt = re.match(r"\s+(\S)", text[end:])
        next_char = nxt.group(1) if nxt else ""
        flags = []
        low = tok.lower()
        if text[punct] == "." and (low in ABBREVIATIONS or low.rstrip(".") in ABBREVIATIONS):
            # 약어 뒤라도 다음이 대문자면 경계일 수 있어 검토 대상으로만 남김
            if next_char.isupper():
                nonsplits.append((punct, f"nosplit_abbrev:{tok}"))
            continue
        if text[punct] == "." and re.fullmatch(r"[A-Z]|pp", tok):
            # 저자 이니셜보다 "Run B." 같은 문장 끝이 많아 나누되 표시
            flags.append(f"split_after_short_token:{tok}")
        if next_char and not (next_char.isupper() or next_char.isdigit() or next_char in "\"'([“$\\"):
            # 다음 글자가 소문자 등이면 문장 끝이 아닐 가능성이 높아 나누지 않음
            continue
        if next_char.isdigit():
            flags.append("next_starts_with_digit")
        if re.search(r"\d$", tok):
            flags.append("number_before_period")
        boundaries.append((end, flags))
    for m in NO_SPACE.finditer(text):
        tok = token_before(text, m.start())
        # 도메인·파일명·약어 안의 마침표는 경계가 아님
        if inside(m.start(), spans) or any(c in tok for c in "./:@"):
            continue
        boundaries.append((m.end(), ["no_space_after_punct"]))
    for m in re.finditer(r"\n+", text):  # 문단 줄바꿈은 항상 경계
        boundaries.append((m.start(), ["newline"]))
    boundaries.sort()

    for end, flags in boundaries + [(len(text), [])]:
        s, e = start, end
        while s < e and text[s].isspace():
            s += 1
        while e > s and text[e - 1].isspace():
            e -= 1
        if e > s:
            inner = [why for pos, why in nonsplits if s <= pos < e]
            sentences.append((s, e, flags + inner))
        start = end
    return sentences


def roundtrip_ok(text: str, sents) -> bool:
    """문장들과 그 사이 공백만으로 원문을 정확히 재구성할 수 있는지."""
    pos = 0
    for s, e, _ in sents:
        if text[pos:s].strip():
            return False
        pos = e
    return not text[pos:].strip()
```

`roundtrip_ok`가 거짓이면 그 논문은 해설을 만들지 않고 오류로 기록한다.

## 3. 모델 입력과 호출

- 프롬프트: `docs/contract/p2_prompt_v0.5.2.md`의 SYSTEM + USER TEMPLATE. 운영은 **모드 B(`auto_select`)** 만 쓴다(`docs/HANDOFF.md` 4.2절).
- `source_sentences`에는 문장마다 `{"sentence_id", "kind", "text"}`를 넣는다(`kind=link|meta`도 포함해 모델이 건너뛰게 한다).
- `abstract_sha256`은 원문 초록 UTF-8 바이트의 SHA-256.
- 호출 설정과 실패 처리(재시도, 예비 모델 전환)는 `docs/contract/p2_ops_config_v1.md` 1~2장. OpenAI 호환 `chat/completions`, 스트리밍 켬.
- deepseek는 `response_format: json_object`를 **끈다**(켜면 본문이 빈 채로 끝남). 응답이 코드 펜스로 감싸져 있으면 펜스 안의 JSON을 꺼내 파싱한다.
- 호출마다 기록: `paper_id`, `abstract_sha256`, 분할기 버전, 모드, 모델 ID, `prompt_version`, `schema_version`, temperature, 요청 ID, 지연, 입력·출력 토큰, 원본 응답, 검증 오류.
- Python 3.9: 응답을 읽다 나는 시간 초과(`socket.timeout`)는 `TimeoutError`가 아니라 `OSError` 하위다. 잡지 않으면 작업 스레드가 조용히 죽는다.
- API 키는 환경 변수나 CI 비밀값으로만 넣는다. 공개 레포에 `.env`를 커밋하지 않는다.

## 4. 출력 검증

모델의 자기 판정을 믿지 않고 입력과 대조한다. 하나라도 실패하면 재시도 대상이다.

| # | 검사 | 통과 조건 |
|---|---|---|
| 1 | 스키마 | `p2-output-v0.2` 적합, `glossary_mode`가 요청 모드와 같음 |
| 2 | 문장 정렬 | `sentence_translations`의 ID 집합·순서 = 입력의 `kind=text` 문장 ID 집합·순서 |
| 3 | 근거 | `key_points[].evidence_sentence_ids`와 `glossary[].sentence_ids`가 모두 `kind=text` 문장에 실재 |
| 4 | 용어 | `auto_select`: `term_id`가 전부 null이고, `term` 표기가 원문 `kind=text` 문장에 **대소문자까지 그대로** 등장 |
| 5 | 난이도 | `term_difficulty`는 검사하지 않고 잠정값으로만 저장 |

검증 통과 후 후처리(LaTeX 표시 변환, 분류 코드 정리, 외국 문자 경고)와 하이라이트 판정(`docs/HANDOFF.md` 8.4절)을 거쳐 저장한다. 원본 응답은 따로 보관한다.
