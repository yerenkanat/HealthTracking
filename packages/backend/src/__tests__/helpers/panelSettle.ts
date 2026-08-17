/**
 * Wait for the panel to be FINISHED, not for a clock to run out.
 *
 * Every jsdom panel suite in this directory was written the same way: boot the
 * page, click something, `await new Promise(r => setTimeout(r, 120))`, read the
 * DOM. 161 of those waits exist across 47 files, and each one decides its
 * verdict on elapsed wall-clock rather than on the work being finished — so
 * every one of them changes answer under load. The same tree produced
 * «1 failed | 165 passed» and «165 passed» on consecutive full runs, and the
 * failure moved when a neighbouring file added ~30 s of jsdom CPU.
 *
 * `adminRoleRouteAccess.test.ts` established the replacement: count the
 * requests issued and in flight, return when nothing is in flight and nothing
 * new has been issued for several consecutive turns, and THROW rather than
 * proceed on a half-drawn screen. This is that, extracted, plus the one thing
 * that file did not need.
 *
 * ---------------------------------------------------------------------------
 * THE ONE THING THAT FILE DID NOT NEED: the page's own timers
 *
 * Counting fetches alone is not "the panel has finished". `packages/admin/
 * index.html` schedules six timeouts, and three of them are DEBOUNCES that go
 * on to fetch:
 *
 *   · `searchTimer  = setTimeout(() => renderUsers(q), 250)`
 *   · `vacImpTimer  = setTimeout(vacLoadImpact, 180)`
 *   · `bcCountTimer = setTimeout(bcRefreshCount, 120)`
 *
 * A fetch-only wait returns ~5 ms after the keystroke, before the debounce has
 * fired, and then reads a screen that has not been asked to change. It would be
 * quiet, deterministic, and wrong — «a converted sleep that silently waits on
 * the wrong thing is worse than the sleep».
 *
 * So the page's `setTimeout` is intercepted and its callbacks are held. A timer
 * is pending work; the page is not finished while one exists. When the request
 * channel has gone calm and a timer is still outstanding, the harness runs it —
 * IMMEDIATELY, in due order, on a virtual clock — instead of sleeping until its
 * delay elapses in real time. Firing only when nothing is in flight preserves
 * the ordering that matters (no timer ever overtakes a live request), and
 * `clearTimeout` still cancels, so a debounce still debounces: three keystrokes
 * leave one timer, not three.
 *
 * The wall clock therefore appears nowhere in the verdict. The same sequence of
 * events is observed whether a request answers in one turn or in forty
 * milliseconds — which is what `latencyMs` is for: load as an INPUT, so a suite
 * can assert that its observations do not move when the transport is slowed.
 *
 * `setInterval` is deliberately NOT intercepted. An interval never completes,
 * so it can never be part of "finished"; the panel's two (`liveTick` every 20 s
 * and the "updated Ns ago" repaint every 5 s) start only behind `if(!LIVE)
 * return`, and neither fires inside a settle loop.
 *
 * ---------------------------------------------------------------------------
 * BOUNDS
 *
 * Both loops end in a throw, never in a shrug. Running out of turns means a
 * livelock; running out of flushes means a timer that reschedules itself. In
 * either case the test fails saying what was still outstanding, rather than
 * handing a half-drawn screen to an assertion.
 */

/**
 * Wait for something a test can SEE, and fail saying what never happened.
 *
 * For work no counter can observe — a script tag jsdom fetches itself, a
 * framework mounting from its own boot hook. The condition is the outcome the
 * test is about to assert on, so a wait that ends early ends in a named failure
 * rather than in a wrong verdict. Still bounded, and the bound throws.
 */
export async function until(
  cond: () => boolean,
  what: string,
  { turns = 3000 }: { turns?: number } = {},
): Promise<void> {
  for (let i = 0; i < turns; i++) {
    if (cond()) return;
    await new Promise((r) => { globalThis.setTimeout(r, 1); });
  }
  throw new Error(`never happened after ${turns} turns: ${what}`);
}

export interface PanelRequestInit {
  method?: string;
  body?: string | null;
  headers?: Record<string, string>;
}

/** The subset of Response the panel actually reads. */
export interface PanelResponse {
  ok: boolean;
  status: number;
  json: () => Promise<unknown>;
  text?: () => Promise<string>;
}

export type PanelFetch = (path: string, init?: PanelRequestInit) => Promise<PanelResponse>;

/** Only what this harness touches, so a test need not import jsdom's types. */
export interface PanelWindow {
  fetch: unknown;
  setTimeout: unknown;
  clearTimeout: unknown;
}

export interface PanelSettleOptions {
  /**
   * Delay injected before every request answers. Zero on an idle box is what
   * made fixed waits look fine; a suite that wants to prove its verdict is
   * load-independent runs the same scenario twice, once with this set.
   */
  latencyMs?: number;
  /** Consecutive turns with nothing in flight, nothing new, nothing pending. */
  calmTurns?: number;
  /**
   * Hold and run the page's own timers. Default true, because in the admin
   * panel three of them are debounces that go on to fetch.
   *
   * Set false for a page whose timers are its own business — the exported
   * landing artifact reschedules an animation timer forever, so holding them
   * would turn every quiet() into a flush loop that only ends in the throw.
   * Where this is off, quiet() means "no request outstanding" and nothing
   * stronger, and the caller must say what else it is waiting for.
   */
  holdTimers?: boolean;
  /** Hard bound on turns. Reaching it is a livelock, and throws. */
  maxTurns?: number;
  /** Hard bound on timers run early. Reaching it is a self-rescheduling timer. */
  maxFlushes?: number;
}

export interface PanelSettle {
  /**
   * Install the counting fetch and the timer interception. Call from
   * `beforeParse`, so it is in place before the panel's own scripts run.
   */
  attach(window: PanelWindow, impl: PanelFetch): void;
  /**
   * Resolve once the page has no request in flight, has issued no new one for
   * `calmTurns` turns, and has no timer outstanding. Throws rather than
   * returning a page that is still working.
   */
  quiet(label?: string): Promise<void>;
  /** Requests the page has issued since boot. */
  readonly issued: number;
  /** Requests still outstanding. */
  readonly inFlight: number;
  /** Page timers this harness ran ahead of their delay. */
  readonly flushed: number;
  /** Page timers scheduled and not yet run. */
  readonly pending: number;
}

interface HeldTimer {
  run: () => void;
  /** Virtual milliseconds, so ordering between timers of different delays holds. */
  due: number;
  /** Scheduling order, to break ties the way a real event loop does. */
  seq: number;
}

export function panelSettle(opts: PanelSettleOptions = {}): PanelSettle {
  const latencyMs = opts.latencyMs ?? 0;
  const calmTurns = opts.calmTurns ?? 5;
  const maxTurns = opts.maxTurns ?? 3000;
  const maxFlushes = opts.maxFlushes ?? 500;

  let issued = 0;
  let inFlight = 0;
  let flushed = 0;
  let seq = 0;
  let virtualNow = 0;
  const timers = new Map<number, HeldTimer>();

  /** A real macrotask turn on the RUNNER's clock — never the page's, which is held. */
  const turn = (): Promise<void> => new Promise((r) => { globalThis.setTimeout(r, 0); });

  function attach(window: PanelWindow, impl: PanelFetch): void {
    let nextId = 1;
    if (opts.holdTimers !== false) window.setTimeout = ((handler: unknown, delay?: number, ...args: unknown[]) => {
      const id = nextId++;
      const ms = Number.isFinite(Number(delay)) ? Math.max(0, Number(delay)) : 0;
      // A string handler is legal and the panel does not use one; running it
      // would need the page's eval, so it is refused loudly rather than
      // silently dropped.
      if (typeof handler !== 'function') {
        throw new Error('panelSettle: setTimeout with a non-function handler is not supported');
      }
      const fn = handler as (...a: unknown[]) => void;
      timers.set(id, { run: () => fn(...args), due: virtualNow + ms, seq: seq++ });
      return id;
    }) as never;
    if (opts.holdTimers !== false) window.clearTimeout = ((id: unknown) => { timers.delete(Number(id)); }) as never;

    window.fetch = (async (path: string, init?: PanelRequestInit) => {
      issued++;
      inFlight++;
      try {
        if (latencyMs) await new Promise((r) => { globalThis.setTimeout(r, latencyMs); });
        return await impl(String(path), init);
      } finally {
        inFlight--;
      }
    }) as never;
  }

  /** The single earliest outstanding timer, by due time then scheduling order. */
  function fireEarliest(): void {
    let bestId = -1;
    let best: HeldTimer | null = null;
    for (const [id, t] of timers) {
      if (!best || t.due < best.due || (t.due === best.due && t.seq < best.seq)) {
        best = t; bestId = id;
      }
    }
    if (!best) return;
    timers.delete(bestId);
    virtualNow = Math.max(virtualNow, best.due);
    flushed++;
    best.run();
  }

  async function quiet(label = 'the panel'): Promise<void> {
    let calm = 0;
    let lastIssued = -1;
    let flushes = 0;
    for (let i = 0; i < maxTurns; i++) {
      await turn();
      if (inFlight === 0 && issued === lastIssued) calm++; else calm = 0;
      lastIssued = issued;
      if (calm < calmTurns) continue;
      if (timers.size === 0) return;
      if (++flushes > maxFlushes) {
        throw new Error(
          `${label}: ${timers.size} page timer(s) still pending after running ${flushes - 1} of them — ` +
          'a timer is rescheduling itself, so "finished" can never be observed',
        );
      }
      fireEarliest();
      calm = 0;
      lastIssued = -1;
    }
    throw new Error(
      `${label} never went quiet: ${inFlight} request(s) in flight and ${timers.size} timer(s) pending ` +
      `after ${maxTurns} turns. The screen was NOT read — a half-drawn page is not a verdict.`,
    );
  }

  return {
    attach,
    quiet,
    get issued() { return issued; },
    get inFlight() { return inFlight; },
    get flushed() { return flushed; },
    get pending() { return timers.size; },
  };
}
