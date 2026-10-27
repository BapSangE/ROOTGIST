"""p2-prompt-v0.5.2 모드 B(auto_select) 호출 (batch_worker_notes.md 3장, ops config 1·2장).

제공처(OpenAI 호환 chat/completions)는 키로 고른다. DEEPSEEK_API_KEY가 있으면 DeepSeek 공식 API(운영, HANDOFF 2장),
없으면 NVIDIA 무료 등급(개발·내부 테스트 전용. 약관상 생성 결과를 다른 사람에게 보여 주면 안 된다, ops config 1장).
"""
import hashlib
import json
import re
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# 버전 → 문서. v0.6은 내부 테스트용 기본값(2026-10-23, 3편 확인 2회). 운영 제공처 전환 때 v0.5.2와 다시 비교한다.
PROMPTS = {"v0.5.2": ROOT / "docs" / "contract" / "p2_prompt_v0.5.2.md",
           "v0.6": ROOT / "docs" / "contract" / "p2_prompt_v0.6.md"}
DEFAULT_PROMPT = "v0.6"
SCHEMA_VERSION = "p2-output-v0.2"
NVIDIA_ENDPOINT = "https://integrate.api.nvidia.com/v1/chat/completions"
DEEPSEEK_ENDPOINT = "https://api.deepseek.com/chat/completions"

# (모델, JSON 강제, 읽기 대기 초, 엔드포인트, 최대 출력 토큰). 기본 → 예비 순.
# DeepSeek: deepseek-flash = DeepSeek-V4.1-Flash-1017(기본이 생각 모드, 생각 토큰도 출력 상한에 든다 → 64K).
# deepseek-v4-pro(약 3.3배 비쌈)는 쓰지 않는다(2026-10-27 결정). 예비도 flash로 한 번 더(모두 세 번).
# ponytail: HANDOFF의 예비 제공처 Z.ai는 키가 생기면 예비 자리에 넣는다(지금은 DeepSeek 장애 때 같이 막힌다).
DEEPSEEK_FLASH = ("deepseek-flash", False, 600, DEEPSEEK_ENDPOINT, 64000)
DEEPSEEK_MODELS = (DEEPSEEK_FLASH, DEEPSEEK_FLASH)
# NVIDIA: deepseek는 json_object를 켜면 본문이 빈 채로 끝난다.
NVIDIA_MODELS = (("deepseek-ai/deepseek-v4.1-flash", False, 600, NVIDIA_ENDPOINT, 32000),
                 ("z-ai/glm-5.3-flash", True, 900, NVIDIA_ENDPOINT, 32000))


def _setting(name: str) -> str | None:
    from .run import setting  # run이 llm을 불러오므로 여기서
    return setting(name)


def provider() -> str:
    """deepseek | nvidia. 캐시가 어느 제공처로 만든 것인지 가르는 데도 쓴다."""
    return "deepseek" if _setting("DEEPSEEK_API_KEY") else "nvidia"


def api_key() -> str | None:
    return _setting("DEEPSEEK_API_KEY") or _setting("NVIDIA_API_KEY")


def active_models() -> tuple[tuple, tuple]:
    return DEEPSEEK_MODELS if provider() == "deepseek" else NVIDIA_MODELS


def _section(doc: str, start: str, end: str) -> str:
    i, j = doc.index(start) + len(start), doc.index(end)
    return doc[i:j].strip()


def prompt_version(version: str) -> str:
    return f"p2-prompt-{version}"


def load_prompt(version: str = DEFAULT_PROMPT) -> tuple[str, str]:
    """프롬프트 문서에서 SYSTEM과 모드 B 규칙을 그대로 꺼낸다(문서를 고치면 호출도 바뀐다)."""
    doc = PROMPTS[version].read_text(encoding="utf-8")
    system = _section(doc, "## SYSTEM (공통)", "## USER TEMPLATE")
    mode_b = _section(doc, "## 모드 B — AUTO SELECT (용어 선정 평가)", "## 도구측 필수 검증")
    mode_b = re.sub(r"```\n.*?```\n", "", mode_b, flags=re.S).strip()  # 코드 블록(값)은 USER에 직접 쓴다
    return system, mode_b


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


SCHEMA_DOC = ROOT / "docs" / "contract" / "p2_output_schema_v0.2.json"


def build_messages(title_en: str, abstract: str, sentences: list[dict],
                   version: str = DEFAULT_PROMPT, preferred_terms: list[dict] | None = None) -> list[dict]:
    system, mode_b = load_prompt(version)
    # SYSTEM은 "p2-output-v0.2 스키마에 맞춘다"고만 하므로 스키마 원문을 붙인다. 빼면 모델이 필드 이름을 지어낸다
    # (2026-10-22 확인 실행: claim_ko→text, translation_ko→text_ko 등으로 3회 모두 스키마 실패).
    # ponytail: 연구 레포에서 스키마를 어디에 넣었는지는 확인하지 못했다. 운영 제공처 확인 실행 때 함께 맞춰 본다.
    system += f"\n\n## 출력 스키마 ({SCHEMA_VERSION})\n```json\n{SCHEMA_DOC.read_text(encoding='utf-8').strip()}\n```"
    src = [{"sentence_id": s["sentence_id"], "kind": s["kind"], "text": s["text"]} for s in sentences]
    user = "\n".join([
        f"original_title: {title_en}",
        f"abstract_sha256: {sha256(abstract)}",
        f"source_sentences: {json.dumps(src, ensure_ascii=False)}",
        'allowed_topics: ["llm","agent","multimodal","optimization","other"]',
        'explanation_level: "standard"',
        # v0.6부터: 승인된 사전 표기(없으면 빈 목록). v0.5.2 템플릿에는 없는 줄이다.
        *([f"preferred_terms: {json.dumps(preferred_terms or [], ensure_ascii=False)}"] if version != "v0.5.2" else []),
        'glossary_mode: "auto_select"',
        "fixed_terms: []",
        "",
        mode_b,
    ])
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


class Transient(Exception):
    """HTTP 429·5xx, 시간 초과, 연결 끊김."""


def stream_chat(api_key: str, model: tuple, messages: list[dict]) -> dict:
    model_id, json_mode, read_timeout, endpoint, max_tokens = model
    payload = {
        "model": model_id,
        "messages": messages,
        "temperature": 0,  # DeepSeek 생각 모드에서는 무시된다
        "max_tokens": max_tokens,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    if json_mode:
        payload["response_format"] = {"type": "json_object"}
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json", "Accept": "text/event-stream"},
    )
    t0 = time.monotonic()
    parts, finish, usage, request_id = [], None, None, None
    try:
        with urllib.request.urlopen(req, timeout=read_timeout) as r:
            request_id = r.headers.get("x-request-id") or r.headers.get("nvcf-reqid")
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                chunk = json.loads(data)
                request_id = request_id or chunk.get("id")
                usage = chunk.get("usage") or usage
                for c in chunk.get("choices") or []:
                    parts.append((c.get("delta") or {}).get("content") or "")
                    finish = c.get("finish_reason") or finish
    except urllib.error.HTTPError as e:
        if e.code == 429 or e.code >= 500:
            raise Transient(f"HTTP {e.code}") from e
        raise  # 401·400 등은 설정 문제라 재시도하지 않는다
    except OSError as e:  # URLError, socket.timeout(Python 3.9에서 TimeoutError가 아님) 포함
        raise Transient(repr(e)) from e
    return {
        "model_id": model_id,
        "content": "".join(parts),
        "finish_reason": finish,
        "usage": usage,
        "request_id": request_id,
        "latency_ms": int((time.monotonic() - t0) * 1000),
    }


def parse_json(content: str):
    """본문 JSON. 코드 펜스로 감싸졌으면 펜스 안을 꺼낸다. 실패하면 None."""
    text = content.strip()
    m = re.search(r"```(?:json)?\s*(.*?)```", text, flags=re.S)
    if m:
        text = m.group(1).strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def generate(api_key: str, messages: list[dict], check, log, sleep=time.sleep, models=None):
    """ops config 2장. 기본 모델: 내용 실패(길이·빈 본문·파싱·검증) 1회 재시도, 일시 오류는 10초·20초 두 번 더.
    그래도 안 되면 예비 모델 1회. 성공하면 (출력, 모델 ID), 끝내 실패하면 (None, None).
    check(output) -> 오류 목록(빈 목록이면 통과)."""
    primary, fallback = models or active_models()
    for model, content_tries in ((primary, 2), (fallback, 1)):
        for _ in range(content_tries):
            result = None
            for wait in (0, 10, 20):
                if wait:
                    sleep(wait)
                log({"model_id": model[0], "event": "call_start"})  # 긴 호출 중에도 진행이 보이게
                try:
                    result = stream_chat(api_key, model, messages)
                    break
                except Transient as e:
                    log({"model_id": model[0], "error": f"transient: {e}"})
            if result is None:
                break  # 일시 오류가 계속되면 이 모델은 포기하고 예비로
            out = parse_json(result["content"]) if result["finish_reason"] != "length" else None
            errors = ["no_json" if result["finish_reason"] != "length" else "finish_reason_length"] if out is None else check(out)
            log({**result, "validation_errors": errors})
            if not errors:
                return out, model[0]
    return None, None
