"""약어의 영문 정식 명칭 (C02 한 줄). 초록이 직접 풀어 쓴 경우는 규칙으로 뽑고(원문 그대로),
없으면 용어 후보 초안 단계에서 LLM 초안을 받아 사람이 승인한다(glossary.draft_full_forms)."""
import re

STOP = {"of", "and", "for", "the", "in", "with", "to", "on", "a", "an", "via", "by", "from"}


def is_acronym(term: str) -> bool:
    """SLAM, LoRA, MLLMs, GPT-4 같은 표기. 대문자 둘 이상, 짧음, 공백 없음."""
    return bool(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9\-]{0,11}", term)) and sum(c.isupper() for c in term) >= 2


def letters(term: str) -> str:
    """정식 명칭과 맞춰 볼 글자: 대문자만(LoRA → LRA, MLLMs → MLLM)."""
    return "".join(c for c in term if c.isupper())


def matches(term: str, full: str) -> bool:
    """정식 명칭 단어(하이픈도 나눔)의 첫 글자가 약어 대문자와 순서대로 같은지. 불용어는 넣어도 빼도 된다."""
    words = [w for w in re.split(r"[\s\-]+", full.strip()) if w]
    want = letters(term).lower()
    if not words or not want:
        return False
    with_stop = "".join(w[0].lower() for w in words)
    without = "".join(w[0].lower() for w in words if w.lower() not in STOP)
    return want in (with_stop, without)


def from_abstract(term: str, abstract: str) -> str | None:
    """「Long Form (TERM)」 또는 「TERM (Long Form)」을 초록에서 찾는다. 글자가 맞을 때만, 원문 표기 그대로."""
    t = re.escape(term)
    # 「… Long Form (TERM)」: 괄호 앞 단어를 뒤에서부터 늘려 가며 가장 짧게 맞는 구간
    for m in re.finditer(rf"\(\s*{t}\s*\)", abstract):
        words = re.findall(r"[A-Za-z][\w\-]*", abstract[max(0, m.start() - 200):m.start()])
        for n in range(1, min(len(words), len(letters(term)) + 4) + 1):
            cand = " ".join(words[-n:])  # 단어 안의 하이픈(Low-Rank)은 그대로 남는다
            if matches(term, cand):
                return cand
    # 「TERM (Long Form)」
    for m in re.finditer(rf"(?<![\w-]){t}\s*\(([^()]{{3,80}})\)", abstract):
        if matches(term, m.group(1)):
            return m.group(1).strip()
    return None
