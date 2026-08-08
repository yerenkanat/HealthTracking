/**
 * What a member of staff is allowed to do.
 *
 * The panel had three roles — admin, clinician, support — and one real check:
 * "are you admin?". docs/CLAUDE-admin-design.md §7 describes five, and the two
 * it adds are the ones that actually bound exposure:
 *
 *   * a SELLER takes orders and sees stock and contacts, and must not see
 *     margin or anybody's children;
 *   * a WAREHOUSE hand receives and ships, and has no business in a customer's
 *     health record at all.
 *
 * Guards ask for a CAPABILITY, not a role. That is what makes the spec's last
 * line implementable — «новая роль наследует минимум и добирает права
 * поштучно» — and it means adding a role is one line in [ROLE_CAPS] rather
 * than an audit of every route.
 *
 * PURE: no Fastify, no repository. The whole matrix is testable as data.
 */

/** The five in the spec, plus the three this system already issued. */
export const STAFF_ROLES = [
  'owner', 'operator', 'seller', 'warehouse', 'content',
  // Kept because real accounts carry them. Mapped below rather than migrated:
  // rewriting a live staff table on deploy is how somebody loses access at the
  // moment they need it, and these three still describe real jobs.
  'admin', 'clinician', 'support',
] as const;

export type StaffRole = (typeof STAFF_ROLES)[number];

/**
 * One thing a person can be allowed to do. Named after the job, not the route,
 * so a new endpoint joins an existing capability instead of inventing one.
 */
export type Capability =
  /** Orders, leads, the shop's own settings. */
  | 'orders'
  /** Customer list and contact details — names, phones, cities. */
  | 'customers'
  /** Health readings, cycle, children and their locations. Special-category. */
  | 'health'
  /** Money: cost, margin, revenue, the owner's dashboard. */
  | 'finance'
  /** Warehouse: inventory, stock moves, the device registry. */
  | 'stock'
  /** Timeline content, the course, audio, product copy. */
  | 'content'
  /** Creating and disabling staff accounts, and reading the audit log. */
  | 'staff'
  /** The emergency feed and acknowledging an SOS. */
  | 'emergencies';

/**
 * Every capability there is, in the order the permission matrix draws them.
 *
 * Exported because frame 23a serves the matrix from this file. A panel holding
 * its own list is a panel that shows a manager one set of rules while the
 * guards enforce another.
 */
export const ALL_CAPABILITIES: readonly Capability[] = [
  'orders', 'customers', 'health', 'finance', 'stock', 'content', 'staff', 'emergencies',
];

const ALL = ALL_CAPABILITIES;

/**
 * Role → what it may do.
 *
 * Read this against the spec's table. The two that matter most are `seller`,
 * which deliberately lacks `finance` and `health`, and `warehouse`, which has
 * `stock` and nothing else.
 */
export const ROLE_CAPS: Readonly<Record<StaffRole, readonly Capability[]>> = {
  // «всё, включая финансы, здоровье и геолокацию (с записью в журнал)»
  owner: ALL,
  // «заказы, клиенты, поддержка, экстренные»
  operator: ['orders', 'customers', 'emergencies'],
  // «заказы, витрина, остатки, контакты — без маржи и без детей»
  seller: ['orders', 'customers', 'stock'],
  // «склад, приёмка, отгрузка, инвентаризация»
  warehouse: ['stock'],
  // «статьи, календари, аудио, курс; описания товаров без цен»
  content: ['content'],

  // ---- The three already issued -------------------------------------------
  // `admin` was the only role with any power, and every existing owner has it.
  admin: ALL,
  // Read the medical side of a patient; never the money.
  clinician: ['health', 'customers', 'emergencies'],
  // What support actually did before the spec named it `operator`.
  support: ['orders', 'customers', 'emergencies'],
};

export function isStaffRole(v: unknown): v is StaffRole {
  return typeof v === 'string' && (STAFF_ROLES as readonly string[]).includes(v);
}

/**
 * May this role do this?
 *
 * An unknown role gets NOTHING. A typo in a role column must not read as
 * permission — the safe direction to fail is closed, and a member of staff
 * seeing an empty panel asks somebody, which is exactly the right outcome.
 */
export function can(role: string, cap: Capability): boolean {
  if (!isStaffRole(role)) return false;
  return ROLE_CAPS[role].includes(cap);
}

/** Everything this role may do — for the panel, which hides what it cannot use. */
export function capsOf(role: string): readonly Capability[] {
  return isStaffRole(role) ? ROLE_CAPS[role] : [];
}
