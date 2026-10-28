import { describe, expect, it, vi } from "vitest";
import { parseTermCommand } from "@/lib/domain/term-commands";
import { createTermStorage, type TermRpc } from "@/lib/server/term-storage";
import { AdminError } from "@/lib/server/errors";

const actor = {
  user_id: "11111111-1111-4111-8111-111111111111",
  fixture: false,
};
const ready = {
  adminUserId: actor.user_id,
  schemaVersion: 1,
  workerContractVersion: 1,
  writesEnabled: true,
};
const input = () => ({
  operation_id: "22222222-2222-4222-8222-222222222222",
  action: "apply_patch",
  targets: [
    {
      entity_type: "sense",
      entity_key: "S1",
      expected_revision: 0,
      base_sha256: "a".repeat(64),
      patch: { canonical_ko: "가상 용어" },
    },
  ],
  reason: "가상 예시",
});

describe("term storage command boundary", () => {
  it("accepts only the term contract, never caller-supplied actor or content writes", () => {
    expect(parseTermCommand(input()).targets).toHaveLength(1);
    for (const change of [
      { actor_id: actor.user_id },
      { action: "publish" },
      { origin: "worker" },
      { targets: [{ ...input().targets[0], entity_type: "news" }] },
    ])
      expect(() => parseTermCommand({ ...input(), ...change })).toThrow();
  });
  it("validates aliases, occurrence references, absent versus null and byte limits", () => {
    const row = input().targets[0];
    for (const patch of [
      { canonical_ko: 123 },
      { title_ko: "forbidden" },
      {
        aliases: [
          {
            alias_id: "A",
            surface_form: "x",
            relation_type: "alias",
            review_status: "pending",
            auto_match_allowed: true,
          },
        ],
      },
      { glossary: [] },
    ])
      expect(() =>
        parseTermCommand({ ...input(), targets: [{ ...row, patch }] }),
      ).toThrow();
    const command = parseTermCommand({
      ...input(),
      targets: [
        {
          ...row,
          entity_type: "paper",
          entity_key: "P1",
          patch: {
            glossary: [{ idx: 0, expected_term: "alpha", ko_span: null }],
          },
        },
      ],
    });
    expect(command.targets[0].patch).toEqual({
      glossary: [{ idx: 0, expected_term: "alpha", ko_span: null }],
    });
    expect(() =>
      parseTermCommand({ ...input(), reason: "한".repeat(66000) }),
    ).toThrow();
    expect(() =>
      parseTermCommand({ ...input(), targets: [row, row] }),
    ).toThrow();
  });
  it("requires a real allowed admin and DB/worker readiness before any RPC", async () => {
    const rpc = vi.fn();
    expect(() =>
      createTermStorage({ ...actor, fixture: true }, ready, rpc),
    ).toThrow();
    expect(() =>
      createTermStorage(
        { ...actor, user_id: "33333333-3333-4333-8333-333333333333" },
        ready,
        rpc,
      ),
    ).toThrow();
    for (const readiness of [
      { ...ready, writesEnabled: false },
      { ...ready, workerContractVersion: 0 },
      { ...ready, schemaVersion: 0 },
    ]) {
      await expect(
        createTermStorage(actor, readiness, rpc).execute(input()),
      ).rejects.toMatchObject({ status: 423 });
    }
    expect(rpc).not.toHaveBeenCalled();
  });
  it("uses the verified actor, keeps operation ID on retry, and never changes route capabilities", async () => {
    const rpc = vi.fn<TermRpc>(async () => ({
      data: { revision: 1 },
      error: null,
    }));
    const storage = createTermStorage(actor, ready, rpc);
    await storage.execute(input());
    await storage.execute(input());
    expect(rpc.mock.calls[0]).toEqual([
      "admin_execute_term_command",
      {
        actor: actor.user_id,
        operation_id: input().operation_id,
        request: {
          action: "apply_patch",
          targets: input().targets,
          reason: "가상 예시",
        },
      },
    ]);
    expect(rpc.mock.calls[0]).toEqual(rpc.mock.calls[1]);
  });
  it("sanitizes DB failures while preserving conflict and validation classes", async () => {
    for (const [code, status] of [
      ["PT409", 409],
      ["PT422", 422],
      ["PT403", 403],
      ["PT423", 423],
      ["XX000", 503],
    ] as const) {
      const rpc = vi.fn(async () => ({
        data: null,
        error: { code, message: "SECRET URL token private source" },
      }));
      const error = (await createTermStorage(actor, ready, rpc)
        .execute(input())
        .catch((e) => e)) as AdminError;
      expect(error.status).toBe(status);
      expect(error.message).not.toMatch(/SECRET|token|private source/);
    }
  });
  it("validates draft concurrency fields and sends only its own draft identity", async () => {
    const rpc = vi.fn<TermRpc>(async () => ({
      data: { draft_revision: 1 },
      error: null,
    }));
    const storage = createTermStorage(actor, ready, rpc);
    const draft = {
      entity_type: "sense",
      entity_key: "S1",
      expected_revision: 0,
      base_sha256: "a".repeat(64),
      expected_draft_revision: 0,
      payload: { canonical_ko: "초안" },
    };
    await storage.saveDraft(draft);
    expect(rpc.mock.calls[0][0]).toBe("admin_save_term_draft");
    expect(rpc.mock.calls[0][1]).toMatchObject({
      actor: actor.user_id,
      expected_draft_revision: 0,
    });
    await expect(
      storage.saveDraft({ ...draft, expected_draft_revision: -1 }),
    ).rejects.toMatchObject({ status: 422 });
  });
});
