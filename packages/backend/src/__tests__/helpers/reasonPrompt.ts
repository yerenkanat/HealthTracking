/**
 * Answer the "why are you opening this record?" prompt in a rendered panel.
 *
 * Opening a mother's card now asks why before it fetches anything — see
 * routes/admin.ts `readReason` and the spec line it implements. Every drawer
 * test therefore has one more step between clicking a row and reading the
 * drawer, and it belongs in one place rather than copied into six files that
 * would drift the first time the prompt changes.
 *
 * Deliberately NOT a way to skip the prompt. It types an answer and presses
 * the button, exactly as a person would, so a test that stops seeing the
 * prompt (because it broke) fails here rather than silently passing.
 */

/** Must clear the server's 8-character minimum, so not 'x'. */
const DEFAULT_REASON = 'Обращение клиента';

export interface ReasonWindow {
  document: Document;
}

/**
 * How to know the requests the prompt was gating have finished.
 *
 * This used to be a flat 250 ms sleep, which is a guess about somebody else's
 * machine: under a loaded pool the drawer's fetches had not landed and the
 * caller read an empty card. Pass the panel's `quiet` (helpers/panelSettle) and
 * the wait becomes the work being finished instead of a clock running out.
 *
 * REQUIRED. It used to be optional with a 250 ms sleep behind it, "while the
 * callers are converted one at a time" — and six drawer suites went on taking
 * that fallback for as long as it existed, each one a known flake. There is no
 * fallback now, so a new caller cannot quietly acquire one: it has to say how
 * the panel is known to be finished.
 */
export interface ReasonOpts {
  settled: () => Promise<void>;
}

/**
 * Answer it if it is up; say so if it was not.
 *
 * Tolerant on purpose, so a shared click helper can call it after every click
 * without knowing which ones open a record. That it appears AT ALL is asserted
 * where it belongs — adminReasonRender.test.ts — rather than incidentally in
 * twenty drawer tests that are about something else.
 *
 * @param reason what to type. Must clear the server's 8-character minimum, so
 *        the default is a real sentence rather than 'x'.
 * @returns whether there was a prompt to answer.
 */
export async function answerReasonPromptIfShown(
  window: ReasonWindow,
  reason: string | undefined,
  opts: ReasonOpts,
): Promise<boolean> {
  const wrap = window.document.querySelector('#reasonWrap') as HTMLElement | null;
  if (!wrap || wrap.hidden) return false;
  await answerReasonPrompt(window, reason, opts);
  return true;
}

/**
 * @param reason what to type. Must clear the server's 8-character minimum, so
 *        the default is a real sentence rather than 'x'.
 * @throws if the prompt is not on screen — a drawer that opened without asking
 *         is the defect this whole feature exists to prevent.
 */
export async function answerReasonPrompt(
  window: ReasonWindow,
  reason: string | undefined,
  opts: ReasonOpts,
): Promise<void> {
  const wrap = window.document.querySelector('#reasonWrap') as HTMLElement | null;
  if (!wrap || wrap.hidden) {
    throw new Error('the reason prompt did not appear — the record opened unasked');
  }
  const text = window.document.querySelector('#reasonText') as HTMLInputElement;
  text.value = reason ?? DEFAULT_REASON;
  text.dispatchEvent(new (window.document.defaultView as Window & typeof globalThis).Event('input', { bubbles: true }));

  const ok = window.document.querySelector('#reasonOk') as HTMLButtonElement;
  if (ok.disabled) throw new Error(`the prompt refused "${text.value}" as a reason`);
  ok.dispatchEvent(new (window.document.defaultView as Window & typeof globalThis).MouseEvent('click', { bubbles: true }));

  // Let the requests the prompt was gating actually run — by watching them
  // finish, never by guessing how long that takes.
  await opts.settled();
}
