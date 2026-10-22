"""규칙 기반 초록 문장 분할 (batch_worker_notes.md 2장, 연구 레포 분할기 d691502와 같은 동작).

원문 문자열은 바꾸지 않고 [start, end) 오프셋만 쓴다. 분할 규칙을 바꾸면 SPLITTER_VERSION을 올린다.
"""
import re

SPLITTER_VERSION = "d691502"

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


def to_sentences(abstract: str):
    """앱·모델 입력용 [{sentence_id, kind, text, start, end}]. 왕복 검사 실패면 ValueError."""
    sents = split(abstract)
    if not roundtrip_ok(abstract, sents):
        raise ValueError("sentence split roundtrip failed")
    return [
        {"sentence_id": f"A{i:02d}", "kind": kind_of(abstract[s:e]), "text": abstract[s:e], "start": s, "end": e}
        for i, (s, e, _) in enumerate(sents, start=1)
    ]
