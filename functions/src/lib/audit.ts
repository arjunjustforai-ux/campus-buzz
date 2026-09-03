import { COL } from "../config/collections";
import { db, serverTs } from "./firestore";

export interface AuditInput {
  actorUid: string;
  action: string;
  entityType: string;
  entityId: string;
  campusId?: string | null;
  reason?: string;
  before?: Record<string, unknown> | null;
  after?: Record<string, unknown> | null;
  meta?: Record<string, unknown>;
}

/** Immutable audit log. Writes inside a transaction when one is supplied. */
export function writeAudit(input: AuditInput, tx?: FirebaseFirestore.Transaction): void {
  const ref = db.collection(COL.auditLogs).doc();
  const doc = {
    ...input,
    campusId: input.campusId ?? null,
    before: input.before ?? null,
    after: input.after ?? null,
    at: serverTs(),
  };
  if (tx) tx.set(ref, doc);
  else void ref.set(doc);
}
