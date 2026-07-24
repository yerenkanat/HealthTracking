/**
 * The boot guard's auth decision, kept in its own side-effect-free module so it
 * can be tested without importing index.ts (which starts the server on import).
 *
 * `authUser` becomes real with `REAL_AUTH=1` + a Firebase service account.
 * `authAdmin` does NOT: it trusts `x-staff-id` / `x-staff-role` outright and there
 * is no real staff/RBAC verifier yet. So `REAL_AUTH` secures only the USER path —
 * reading it as "everything is authenticated" is exactly the mistake that would
 * ship a back-office anyone can enter by typing a header.
 */
export function authPosture(env: NodeJS.ProcessEnv): {
  userStub: boolean;
  adminStub: boolean;
  safeForProduction: boolean;
} {
  const userStub = env.REAL_AUTH !== '1';
  // Hardcoded true: no real staff verifier is implemented (see authAdmin in
  // index.ts). Whoever wires one flips this here — deliberately NOT an env flag,
  // so a stub can never be waved through in production by setting a variable.
  const adminStub = true;
  return { userStub, adminStub, safeForProduction: !userStub && !adminStub };
}
