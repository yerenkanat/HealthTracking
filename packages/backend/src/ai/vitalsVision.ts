/**
 * Read vitals off a photo — a glucometer, a BP monitor, an oximeter, a
 * thermometer, or a printed lab slip — so the user can snap a picture instead
 * of typing six numbers.
 *
 * Claude vision is asked to report ONLY what is plainly shown, via a forced
 * tool call so the result is structured (never prose we would have to parse).
 * Every value is then clamped to the same physiological ranges the app enforces
 * on hand entry: a misread that lands out of range becomes null rather than a
 * plausible-looking wrong number, and the user still confirms before saving.
 *
 * The caller is INJECTED into the server (deps.extractVitals) exactly like the
 * chat LLM, so the route is testable without the network and the whole feature
 * degrades to a 503 when no API key is configured.
 */

import Anthropic from '@anthropic-ai/sdk';

const MODEL = 'claude-opus-4-8';

export interface ExtractedVitals {
  systolic: number | null; // mmHg
  diastolic: number | null; // mmHg
  heartRate: number | null; // bpm
  spo2: number | null; // %
  temperature: number | null; // °C
  glucose: number | null; // mmol/L
  /** A short, human note — which device was seen, or that nothing was legible. */
  note: string | null;
}

export type VitalsExtractor = (imageBase64: string, mediaType: string) => Promise<ExtractedVitals>;

// The app's own plausibility ranges (app/lib/domain/manual_vitals.dart). Kept in
// sync by hand — a value outside these is dropped, not stored.
const RANGES = {
  systolic: [50, 260],
  diastolic: [30, 200],
  heartRate: [20, 250],
  spo2: [50, 100],
  temperature: [30, 45],
  glucose: [1, 40],
} as const;

const asInt = (n: unknown, [lo, hi]: readonly [number, number]): number | null =>
  typeof n === 'number' && Number.isFinite(n) && n >= lo && n <= hi ? Math.round(n) : null;
const asNum = (n: unknown, [lo, hi]: readonly [number, number]): number | null =>
  typeof n === 'number' && Number.isFinite(n) && n >= lo && n <= hi ? Math.round(n * 10) / 10 : null;

/** Coerce a raw tool payload into a safe, range-checked ExtractedVitals. Exported for tests. */
export function sanitizeVitals(raw: Record<string, unknown>): ExtractedVitals {
  const note = typeof raw.note === 'string' ? raw.note.slice(0, 160) : null;
  return {
    systolic: asInt(raw.systolic, RANGES.systolic),
    diastolic: asInt(raw.diastolic, RANGES.diastolic),
    heartRate: asInt(raw.heartRate, RANGES.heartRate),
    spo2: asInt(raw.spo2, RANGES.spo2),
    temperature: asNum(raw.temperature, RANGES.temperature),
    glucose: asNum(raw.glucose, RANGES.glucose),
    note,
  };
}

const SYSTEM =
  'You read health measurements off a photo of a home medical device or a lab ' +
  'slip and report them via the report_vitals tool. Report ONLY values that are ' +
  'clearly legible on the display or page. Convert units to the reported ones: ' +
  'glucose in mg/dL → mmol/L (divide by 18), temperature in °F → °C. Blood ' +
  'pressure shows as systolic/diastolic (the larger over the smaller). If a value ' +
  'is not visible or you are unsure, leave it absent — never guess. Set note to a ' +
  'short phrase naming the device or saying nothing was legible.';

const TOOL: Anthropic.Tool = {
  name: 'report_vitals',
  description: 'Report the health values legible in the image. Omit anything not clearly shown.',
  input_schema: {
    type: 'object',
    properties: {
      systolic: { type: 'number', description: 'Systolic blood pressure, mmHg (the larger BP number)' },
      diastolic: { type: 'number', description: 'Diastolic blood pressure, mmHg (the smaller BP number)' },
      heartRate: { type: 'number', description: 'Pulse, beats per minute' },
      spo2: { type: 'number', description: 'Blood oxygen saturation, percent' },
      temperature: { type: 'number', description: 'Body temperature in degrees Celsius' },
      glucose: { type: 'number', description: 'Blood glucose in mmol/L' },
      note: { type: 'string', description: 'Short note: the device seen, or that nothing was legible' },
    },
    required: ['note'],
  },
};

export function createAnthropicVitalsExtractor(apiKey = process.env.ANTHROPIC_API_KEY): VitalsExtractor {
  const client = new Anthropic({ apiKey });
  return async (imageBase64, mediaType) => {
    const res = await client.messages.create({
      model: MODEL,
      max_tokens: 400,
      temperature: 0, // reading digits off a display — we want determinism, not creativity
      system: SYSTEM,
      tools: [TOOL],
      tool_choice: { type: 'tool', name: 'report_vitals' },
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: mediaType as Anthropic.ImageBlockParam.Source['media_type'], data: imageBase64 },
            },
            { type: 'text', text: 'Read the measurements shown and report them with report_vitals.' },
          ],
        },
      ],
    });
    const tool = res.content.find((b): b is Anthropic.ToolUseBlock => b.type === 'tool_use');
    if (!tool) return { systolic: null, diastolic: null, heartRate: null, spo2: null, temperature: null, glucose: null, note: null };
    return sanitizeVitals(tool.input as Record<string, unknown>);
  };
}
