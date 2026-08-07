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

export interface ReasonWindow {
  document: Document;
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
  reason = 'Обращение клиента',
): Promise<boolean> {
  const wrap = window.document.querySelector('#reasonWrap') as HTMLElement | null;
  if (!wrap || wrap.hidden) return false;
  await answerReasonPrompt(window, reason);
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
  reason = 'Обращение клиента',
): Promise<void> {
  const wrap = window.document.querySelector('#reasonWrap') as HTMLElement | null;
  if (!wrap || wrap.hidden) {
    throw new Error('the reason prompt did not appear — the record opened unasked');
  }
  const text = window.document.querySelector('#reasonText') as HTMLInputElement;
  text.value = reason;
  text.dispatchEvent(new (window.document.defaultView as Window & typeof globalThis).Event('input', { bubbles: true }));

  const ok = window.document.querySelector('#reasonOk') as HTMLButtonElement;
  if (ok.disabled) throw new Error(`the prompt refused "${reason}" as a reason`);
  ok.dispatchEvent(new (window.document.defaultView as Window & typeof globalThis).MouseEvent('click', { bubbles: true }));

  // Let the requests the prompt was gating actually run.
  await new Promise((r) => setTimeout(r, 250));
}
