import { getApps, initializeApp } from "firebase-admin/app";
import { FieldValue, Firestore, getFirestore, Timestamp, Transaction } from "firebase-admin/firestore";

if (getApps().length === 0) {
  initializeApp();
}

export const db: Firestore = getFirestore();
try {
  db.settings({ ignoreUndefinedProperties: true });
} catch {
  // settings() can only be called once per instance (tests may re-import).
}

export { FieldValue, Timestamp, Transaction };

export const now = (): Timestamp => Timestamp.now();
export const serverTs = () => FieldValue.serverTimestamp();
export const inc = (n = 1) => FieldValue.increment(n);

export function tsToMs(v: unknown): number | null {
  if (!v) return null;
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === "object" && v !== null && "toMillis" in v && typeof (v as Timestamp).toMillis === "function") {
    return (v as Timestamp).toMillis();
  }
  if (v instanceof Date) return v.getTime();
  if (typeof v === "number") return v;
  if (typeof v === "string") {
    const ms = Date.parse(v);
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

export function toDate(v: unknown): Date | null {
  const ms = tsToMs(v);
  return ms === null ? null : new Date(ms);
}

/** Fetch every doc in a query in pages, running `fn` for each — keeps memory bounded. */
export async function forEachPage<T>(
  query: FirebaseFirestore.Query,
  pageSize: number,
  fn: (docs: FirebaseFirestore.QueryDocumentSnapshot[]) => Promise<T | void>,
): Promise<void> {
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = query.limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) return;
    await fn(snap.docs);
    if (snap.size < pageSize) return;
    last = snap.docs[snap.docs.length - 1];
  }
}

/** Commit an array of write callbacks in batches of ≤ 450 operations. */
export async function batchedWrites(ops: Array<(b: FirebaseFirestore.WriteBatch) => void>): Promise<number> {
  let count = 0;
  for (let i = 0; i < ops.length; i += 450) {
    const b = db.batch();
    for (const op of ops.slice(i, i + 450)) op(b);
    await b.commit();
    count += Math.min(450, ops.length - i);
  }
  return count;
}
