/**
 * Read a medication off a photo — a prescription, a pharmacy label, or the box —
 * so the user can snap a picture instead of typing the name, the dose, and how
 * many times a day to take it.
 *
 * Like the vitals reader, Claude vision reports via a forced tool call (so the
 * result is structured, not prose) and the output is sanitised to the app's own
 * model: a free-text name and dose, and a doses-per-day clamped to 1..6. The
 * user always confirms in the editor before it is saved.
 *
 * Injected into the server (deps.extractMedication) like the chat LLM, so the
 * route is testable without the network and 503s when no API key is set.
 */

import Anthropic from '@anthropic-ai/sdk';

const MODEL = 'claude-opus-4-8';

// Mirrors maxDosesPerDay in app/lib/domain/medication.dart. Kept in sync by hand.
const MAX_DOSES_PER_DAY = 6;

export interface ExtractedMedication {
  name: string | null;
  dose: string | null; // free text as written, e.g. "400 mcg", "1 таблетка"
  perDay: number | null; // 1..MAX_DOSES_PER_DAY
  /** A short human note — what was seen, or that nothing was legible. */
  note: string | null;
}

export type MedicationExtractor = (imageBase64: string, mediaType: string) => Promise<ExtractedMedication>;

const trimmed = (v: unknown, max: number): string | null => {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length ? s.slice(0, max) : null;
};

/** Coerce a raw tool payload into a safe ExtractedMedication. Exported for tests. */
export function sanitizeMedication(raw: Record<string, unknown>): ExtractedMedication {
  const perDayRaw = raw.perDay;
  let perDay: number | null = null;
  if (typeof perDayRaw === 'number' && Number.isFinite(perDayRaw)) {
    perDay = Math.min(MAX_DOSES_PER_DAY, Math.max(1, Math.round(perDayRaw)));
  }
  return {
    name: trimmed(raw.name, 80),
    dose: trimmed(raw.dose, 60),
    perDay,
    note: trimmed(raw.note, 160),
  };
}

const SYSTEM =
  'You read a single medication off a photo of a prescription, a pharmacy label, ' +
  'or the box, and report it via the report_medication tool. Report the drug name ' +
  '(brand or generic, as written), the dose strength or amount exactly as printed ' +
  '(e.g. "400 mcg", "1 таблетка"), and how many times per day it is taken if that ' +
  'is stated (1–6). If the photo shows several medications, report the most ' +
  'prominent one. If something is not legible, leave it absent — never guess. Set ' +
  'note to a short phrase, in the same language as the label.';

const TOOL: Anthropic.Tool = {
  name: 'report_medication',
  description: 'Report the medication legible in the image. Omit anything not clearly shown.',
  input_schema: {
    type: 'object',
    properties: {
      name: { type: 'string', description: 'Medication name, brand or generic, as written' },
      dose: { type: 'string', description: 'Dose strength/amount exactly as printed, e.g. "400 mcg"' },
      perDay: { type: 'number', description: 'Times per day it is taken, 1 to 6, if stated' },
      note: { type: 'string', description: 'Short note: what was seen, or that nothing was legible' },
    },
    required: ['note'],
  },
};

export function createAnthropicMedicationExtractor(apiKey = process.env.ANTHROPIC_API_KEY): MedicationExtractor {
  const client = new Anthropic({ apiKey });
  return async (imageBase64, mediaType) => {
    const res = await client.messages.create({
      model: MODEL,
      max_tokens: 400,
      temperature: 0,
      system: SYSTEM,
      tools: [TOOL],
      tool_choice: { type: 'tool', name: 'report_medication' },
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: mediaType as Anthropic.ImageBlockParam.Source['media_type'], data: imageBase64 },
            },
            { type: 'text', text: 'Read the medication shown and report it with report_medication.' },
          ],
        },
      ],
    });
    const tool = res.content.find((b): b is Anthropic.ToolUseBlock => b.type === 'tool_use');
    if (!tool) return { name: null, dose: null, perDay: null, note: null };
    return sanitizeMedication(tool.input as Record<string, unknown>);
  };
}
