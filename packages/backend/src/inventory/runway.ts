/**
 * How long the shelf lasts.
 *
 * docs/CLAUDE-admin-design.md §"Карточка-метрика" puts it plainly: «26 шт»
 * ничего не значит, «хватит на 4 дня при поставке 12» значит всё. The panel
 * showed the first of those everywhere and the second nowhere, so the only
 * signal that anything needed ordering was a threshold somebody typed in once
 * — a fixed number that is right for one sales rate and wrong for every other.
 *
 * PURE: given a level and what left the shelf in a window, say how long the
 * rest lasts. No repository, no clock — the window is passed in, because a
 * function that reads the time cannot be tested against a fixed ledger.
 */

export interface Runway {
  /** Units sold per day over the window. */
  perDay: number;
  /** Whole days the current level lasts at that rate. Floored: 3.9 days of
   *  cover is three days you can promise and a fourth you cannot. */
  days: number;
  /** True when the window held no sales at all, so `days` is a floor and not
   *  a forecast. The panel says "продаж не было" rather than "хватит навсегда". */
  noSales: boolean;
}

/**
 * @param stock       units on hand now
 * @param soldUnits   units sold over the window (positive; a signed ledger
 *                    delta of −3 is 3 sold)
 * @param windowDays  how long that window was
 *
 * Returns null when the question cannot be answered — a window of zero days,
 * or a negative level, which means the ledger and the shelf disagree and a
 * forecast built on it would be worse than none.
 */
export function runwayOf(stock: number, soldUnits: number, windowDays: number): Runway | null {
  if (!Number.isFinite(stock) || !Number.isFinite(soldUnits) || !Number.isFinite(windowDays)) return null;
  if (windowDays <= 0 || stock < 0 || soldUnits < 0) return null;

  const perDay = soldUnits / windowDays;
  if (perDay === 0) {
    // Nothing sold. Reporting Infinity days would put "хватит на ∞ дней" next
    // to a product that is not selling, which reads as good news about the
    // worst case in a catalogue.
    return { perDay: 0, days: stock > 0 ? Number.POSITIVE_INFINITY : 0, noSales: true };
  }
  return { perDay, days: Math.floor(stock / perDay), noSales: false };
}

/**
 * Is this product running out sooner than a delivery can arrive?
 *
 * The threshold the panel had is a unit count, which cannot know that watches
 * sell four times faster than tags. This asks the question the buyer actually
 * has: will it last until the next shipment lands.
 *
 * @param leadTimeDays how long a resupply takes. 14 by default — the shipments
 *        this business receives come from abroad, and two weeks is the figure
 *        the warehouse works to.
 */
export function needsReorder(r: Runway | null, leadTimeDays = 14): boolean {
  if (!r || r.noSales) return false;
  return r.days < leadTimeDays;
}
