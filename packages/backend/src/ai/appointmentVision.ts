/**
 * Read an appointment off a photo — a referral slip, a clinic talon, an SMS
 * screenshot — so the user can snap a picture instead of typing the title, date,
 * time, and place.
 *
 * Like the other readers, Claude vision reports via a forced tool call (so the
 * result is structured, not prose) and the output is sanitised: the date and
 * time are accepted only in strict formats the app can parse, and everything is
 * length-bounded. The user always confirms in the editor before it is saved —
 * the pickers are right there — so a misread date is corrected, not committed.
 *
 * Injected into the server (deps.extractAppointment) like the chat LLM, so the
 * route is testable without the network and 503s when no API key is set.
 */

import Anthropic from '@anthropic-ai/sdk';

const MODEL = 'claude-opus-4-8';

export interface ExtractedAppointment {
  title: string | null; // what the visit is: doctor, specialty, or procedure
  date: string | null; // YYYY-MM-DD, as printed on the slip
  time: string | null; // HH:MM, 24-hour
  place: string | null; // clinic, address, or cabinet → the appointment's note
  /** A short human note — what was seen, or that nothing was legible. */
  note: string | null;
}

export type AppointmentExtractor = (imageBase64: string, mediaType: string) => Promise<ExtractedAppointment>;

const trimmed = (v: unknown, max: number): string | null => {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s.length ? s.slice(0, max) : null;
};

// Accept a date only if it is a real calendar date in strict YYYY-MM-DD — the
// only shape the app's DateTime.parse takes without guessing. A string like
// "2026-13-40" matches the regex but is not a real date, so round-trip it.
const asDate = (v: unknown): string | null => {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v.trim())) return null;
  const s = v.trim();
  const d = new Date(`${s}T00:00:00Z`);
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s ? null : s;
};

const asTime = (v: unknown): string | null =>
  typeof v === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(v.trim()) ? v.trim() : null;

/** Coerce a raw tool payload into a safe ExtractedAppointment. Exported for tests. */
export function sanitizeAppointment(raw: Record<string, unknown>): ExtractedAppointment {
  return {
    title: trimmed(raw.title, 120),
    date: asDate(raw.date),
    time: asTime(raw.time),
    place: trimmed(raw.place, 200),
    note: trimmed(raw.note, 160),
  };
}

const SYSTEM =
  'You read one medical appointment off a photo of a referral slip, a clinic ' +
  'talon, or an appointment message, and report it via the report_appointment ' +
  'tool. title: what the visit is — the doctor, specialty, or procedure. date: ' +
  'the appointment date exactly as printed, as YYYY-MM-DD (do not invent a year ' +
  'that is not shown). time: the time as HH:MM on a 24-hour clock. place: the ' +
  'clinic name, address, or cabinet/room. If something is not shown, leave it ' +
  'absent — never guess. Set note to a short phrase in the label\'s language.';

const TOOL: Anthropic.Tool = {
  name: 'report_appointment',
  description: 'Report the appointment legible in the image. Omit anything not clearly shown.',
  input_schema: {
    type: 'object',
    properties: {
      title: { type: 'string', description: 'Doctor, specialty, or procedure — what the visit is' },
      date: { type: 'string', description: 'Appointment date as printed, YYYY-MM-DD' },
      time: { type: 'string', description: 'Appointment time, HH:MM 24-hour' },
      place: { type: 'string', description: 'Clinic name, address, or cabinet/room' },
      note: { type: 'string', description: 'Short note: what was seen, or that nothing was legible' },
    },
    required: ['note'],
  },
};

export function createAnthropicAppointmentExtractor(apiKey = process.env.ANTHROPIC_API_KEY): AppointmentExtractor {
  const client = new Anthropic({ apiKey });
  return async (imageBase64, mediaType) => {
    const res = await client.messages.create({
      model: MODEL,
      max_tokens: 400,
      temperature: 0,
      system: SYSTEM,
      tools: [TOOL],
      tool_choice: { type: 'tool', name: 'report_appointment' },
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: mediaType as Anthropic.ImageBlockParam.Source['media_type'], data: imageBase64 },
            },
            { type: 'text', text: 'Read the appointment shown and report it with report_appointment.' },
          ],
        },
      ],
    });
    const tool = res.content.find((b): b is Anthropic.ToolUseBlock => b.type === 'tool_use');
    if (!tool) return { title: null, date: null, time: null, place: null, note: null };
    return sanitizeAppointment(tool.input as Record<string, unknown>);
  };
}
