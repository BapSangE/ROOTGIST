import { AdminError } from "@/lib/server/errors";

export type TermEntity = "sense" | "candidate" | "paper";
export type TermTarget = {
  entity_type: TermEntity;
  entity_key: string;
  expected_revision: number;
  base_sha256: string;
  patch: Record<string, unknown>;
};
export type TermCommand = {
  operation_id: string;
  action: "apply_patch" | "approve" | "reject" | "needs_changes";
  targets: TermTarget[];
  reason: string;
};
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
export const isUuid = (value: unknown): value is string =>
  typeof value === "string" && uuid.test(value);
function invalid(): never {
  throw new AdminError(
    422,
    "VALIDATION_FAILED",
    "용어 저장 요청의 형식과 허용 필드를 확인해 주세요.",
  );
}
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}
function only(value: Record<string, unknown>, keys: string[]) {
  if (Object.keys(value).some((key) => !keys.includes(key))) invalid();
}
function text(value: unknown, max: number, nullable = false): void {
  if (nullable && value === null) return;
  if (typeof value !== "string" || value.length > max) invalid();
}
function nonempty(value: unknown, max = 300): asserts value is string {
  text(value, max);
  if (!(value as string).trim()) invalid();
}
export function termIdentity(
  kind: unknown,
  key: unknown,
): { entity_type: TermEntity; entity_key: string } {
  if (!["sense", "candidate", "paper"].includes(String(kind))) invalid();
  nonempty(key);
  return { entity_type: kind as TermEntity, entity_key: key };
}
function revision(value: unknown): asserts value is number {
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < 0 ||
    value > 999999999999999
  )
    invalid();
}
function hash(value: unknown): asserts value is string {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) invalid();
}
function bounded(input: unknown) {
  try {
    if (new TextEncoder().encode(JSON.stringify(input)).length > 65536)
      invalid();
  } catch {
    invalid();
  }
}
export function validateTermPatch(
  kind: TermEntity,
  input: unknown,
): Record<string, unknown> {
  const patch = object(input);
  const fields =
    kind === "sense"
      ? [
          "canonical_ko",
          "definition_ko",
          "definition_kind",
          "scope",
          "domain",
          "full_form_en",
          "review_note_ko",
          "aliases",
          "source_media_review_required",
        ]
      : kind === "candidate"
        ? ["canonical_ko", "definition_ko", "full_form_en"]
        : ["glossary"];
  only(patch, fields);
  for (const [key, value] of Object.entries(patch)) {
    if (["aliases", "glossary"].includes(key)) continue;
    if (key === "source_media_review_required") {
      if (typeof value !== "boolean") invalid();
    } else
      text(
        value,
        20000,
        key !== "definition_kind" &&
          !(kind === "candidate" && key === "definition_ko"),
      );
    if (
      key === "definition_kind" &&
      !["ai_rewritten", "paper_glossary"].includes(String(value))
    )
      invalid();
  }
  if ("aliases" in patch) {
    if (!Array.isArray(patch.aliases) || patch.aliases.length > 50) invalid();
    const ids = new Set<string>();
    for (const raw of patch.aliases) {
      const alias = object(raw);
      only(alias, [
        "alias_id",
        "surface_form",
        "normalized_form",
        "relation_type",
        "review_status",
        "auto_match_allowed",
      ]);
      for (const key of ["alias_id", "surface_form", "relation_type"])
        nonempty(alias[key], 1000);
      if (ids.has(alias.alias_id as string)) invalid();
      ids.add(alias.alias_id as string);
      if ("normalized_form" in alias) text(alias.normalized_form, 1000, true);
      if (
        !["pending", "approved", "rejected", "deferred"].includes(
          String(alias.review_status),
        ) ||
        typeof alias.auto_match_allowed !== "boolean" ||
        (alias.auto_match_allowed && alias.review_status !== "approved")
      )
        invalid();
    }
  }
  if ("glossary" in patch) {
    if (
      !Array.isArray(patch.glossary) ||
      patch.glossary.length < 1 ||
      patch.glossary.length > 50
    )
      invalid();
    const indices = new Set<number>();
    for (const raw of patch.glossary) {
      const entry = object(raw);
      only(entry, [
        "idx",
        "expected_term",
        "ko_span",
        "sense_id",
        "sentence_ids",
        "highlight",
        "definition_ko",
        "full_form_en",
      ]);
      if (
        typeof entry.idx !== "number" ||
        !Number.isInteger(entry.idx) ||
        entry.idx < 0 ||
        entry.idx > 99999999 ||
        indices.has(entry.idx)
      )
        invalid();
      indices.add(entry.idx);
      nonempty(entry.expected_term, 1000);
      for (const field of [
        "ko_span",
        "sense_id",
        "definition_ko",
        "full_form_en",
      ])
        if (field in entry)
          text(entry[field], 20000, field !== "definition_ko");
      if ("highlight" in entry && typeof entry.highlight !== "boolean")
        invalid();
      if ("sentence_ids" in entry) {
        if (
          !Array.isArray(entry.sentence_ids) ||
          !entry.sentence_ids.length ||
          entry.sentence_ids.length > 100 ||
          new Set(entry.sentence_ids).size !== entry.sentence_ids.length
        )
          invalid();
        entry.sentence_ids.forEach((id) => nonempty(id, 100));
      }
    }
  }
  bounded(patch);
  return patch;
}
function parseTarget(input: unknown): TermTarget {
  const target = object(input);
  only(target, [
    "entity_type",
    "entity_key",
    "expected_revision",
    "base_sha256",
    "patch",
  ]);
  const identity = termIdentity(target.entity_type, target.entity_key);
  revision(target.expected_revision);
  hash(target.base_sha256);
  return {
    ...identity,
    expected_revision: target.expected_revision,
    base_sha256: target.base_sha256,
    patch: validateTermPatch(identity.entity_type, target.patch),
  };
}
export function parseTermCommand(input: unknown): TermCommand {
  bounded(input);
  const command = object(input);
  only(command, ["operation_id", "action", "targets", "reason"]);
  if (
    !isUuid(command.operation_id) ||
    !["apply_patch", "approve", "reject", "needs_changes"].includes(
      String(command.action),
    ) ||
    !Array.isArray(command.targets) ||
    command.targets.length < 1 ||
    command.targets.length > 10
  )
    invalid();
  const targets = command.targets.map(parseTarget);
  if (
    new Set(targets.map((t) => JSON.stringify([t.entity_type, t.entity_key])))
      .size !== targets.length ||
    targets.some(
      (t) => t.entity_type === "paper" && command.action !== "apply_patch",
    )
  )
    invalid();
  const reason = command.reason ?? "";
  text(reason, 2000);
  return {
    operation_id: command.operation_id,
    action: command.action as TermCommand["action"],
    targets,
    reason: reason as string,
  };
}
export function parseTermDraft(input: unknown) {
  bounded(input);
  const draft = object(input);
  only(draft, [
    "entity_type",
    "entity_key",
    "expected_revision",
    "base_sha256",
    "expected_draft_revision",
    "payload",
  ]);
  const target = parseTarget({
    entity_type: draft.entity_type,
    entity_key: draft.entity_key,
    expected_revision: draft.expected_revision,
    base_sha256: draft.base_sha256,
    patch: draft.payload,
  });
  revision(draft.expected_draft_revision);
  return {
    entity_type: target.entity_type,
    entity_key: target.entity_key,
    expected_revision: target.expected_revision,
    base_sha256: target.base_sha256,
    expected_draft_revision: draft.expected_draft_revision,
    payload: target.patch,
  };
}
