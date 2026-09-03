/**
 * Payment adapter seam. CampusBuzz ships with entitlements + manual billing status
 * only (no gateway, no fake payment success). A real provider (e.g. Razorpay) can be
 * plugged in later by implementing this interface and wiring it into
 * `setEntitlement`; nothing in the domain depends on a concrete provider.
 */
export interface BillingAdapter {
  /** Create a checkout/session for a plan; returns a provider reference + URL. */
  createCheckout(input: { subjectType: "club" | "campus" | "brand"; subjectId: string; plan: string; amountMinor: number; currency: string }): Promise<{ reference: string; url: string }>;
  /** Verify a provider webhook/callback and report the resulting billing status. */
  verifyPayment(reference: string): Promise<{ status: "paid" | "pending" | "failed"; paidAt?: Date }>;
}

/** Default adapter: records that billing is handled manually (bank transfer / invoice). */
export class ManualBillingAdapter implements BillingAdapter {
  async createCheckout(input: { subjectType: string; subjectId: string; plan: string }): Promise<{ reference: string; url: string }> {
    return { reference: `manual:${input.subjectType}:${input.subjectId}:${input.plan}`, url: "" };
  }
  async verifyPayment(): Promise<{ status: "pending" }> {
    return { status: "pending" };
  }
}
