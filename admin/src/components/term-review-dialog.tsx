"use client";
import { useEffect, useRef } from "react";
export function ReviewDialog({
  open,
  onClose,
  title,
  side,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  side?: "left" | "right";
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (open && !d?.open) d?.showModal();
    else if (!open && d?.open) d.close();
  }, [open]);
  return (
    <dialog
      ref={ref}
      aria-label={title}
      className={side ? `focus-drawer ${side}` : "focus-dialog"}
      onCancel={onClose}
      onClose={onClose}
    >
      <div className={side ? "drawer-close-bar" : "dialog-head"}>
        {!side && <h2>{title}</h2>}
        <button
          className="icon-button"
          type="button"
          aria-label={`${title} 닫기`}
          onClick={() => ref.current?.close()}
        >
          ×
        </button>
      </div>
      {open && children}
    </dialog>
  );
}
