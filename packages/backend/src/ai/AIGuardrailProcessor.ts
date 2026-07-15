/**
 * AIGuardrailProcessor — the deterministic safety wrapper around the LLM.
 * Specialists: AI Engineer (lead), OB-GYN (triage authority), Cybersecurity.
 *
 * ORDER OF OPERATIONS (all BEFORE the model can speak):
 *   1. TELEMETRY TRIAGE  → critical band data BYPASSES the LLM → EMERGENCY response.
 *   2. INPUT SANITISATION → strip prompt-injection, cap length.
 *   3. RED-FLAG NLU       → user's TEXT describes an emergency → bypass + escalate.
 *   4. LLM CALL           → grounded, guardrailed chat (only if 1–3 are clear).
 *   5. OUTPUT FILTER      → block diagnosis / false reassurance / prescribing.
 *
 * The LLM caller is INJECTED (`deps.callLLM`) so this safety logic is unit-testable
 * with no network/SDK. The real Anthropic implementation lives in anthropicClient.ts.
 */

import { assessTelemetry } from '@fcs/shared';
import type { BandTelemetry, TriageResult } from '@fcs/shared';
import { buildSystemPrompt } from './systemPrompt';

export type GuardrailOutcome =
  | {
      kind: 'emergency';
      action: 'SHOW_EMERGENCY_SCREEN';
      triage: TriageResult;
      callButtons: Array<{ label: string; tel: string }>;
      message: string;
    }
  | { kind: 'chat'; message: string; grounded: boolean }
  | { kind: 'blocked'; reason: string; message: string };

export interface GuardrailInput {
  userId: string;
  locale: string;
  userMessage: string;
  latestTelemetry?: BandTelemetry;
  ragPassages: string[];
  emergencyContacts: Array<{ label: string; tel: string }>;
}

/** Injected LLM caller: (system, userMessage, locale) → assistant text. */
export type LLMCaller = (system: string, userMessage: string, locale: string) => Promise<string>;

export interface GuardrailDeps {
  callLLM: LLMCaller;
}

// --- Red-flag symptom detection on free text (defense-in-depth) ---
const RED_FLAG_PATTERNS: RegExp[] = [
  /\b(can'?t|cannot|trouble|hard to)\s+breath/i,
  /\b(heavy|severe)\s+(bleeding|blood)/i,
  /\bvision\s+(blur|loss|spots|changes)/i,
  /\b(severe|worst)\s+headache/i,
  /\b(baby|fetus).{0,20}(not moving|stopped moving|no movement)/i,
  /\b(faint|passed out|blacked out|seizure|convuls)/i,
  /\bsevere\s+(abdominal|belly|stomach)\s+pain/i,
];
function textLooksEmergency(text: string): boolean {
  return RED_FLAG_PATTERNS.some((re) => re.test(text));
}

// --- Prompt-injection hardening ---
const INJECTION_PATTERNS: RegExp[] = [
  /ignore (all|previous|the above) (instructions|prompt)/i,
  /you are (now|actually) [a-z ]{0,30}(dan|jailbreak|developer mode)/i,
  /(reveal|print|show).{0,20}(system prompt|instructions)/i,
];
function sanitizeUserMessage(text: string): { clean: string; injectionBlocked: boolean } {
  const injectionBlocked = INJECTION_PATTERNS.some((re) => re.test(text));
  return { clean: text.slice(0, 2000), injectionBlocked };
}

// --- Output filter: catch the two failure modes the OB-GYN cares about ---
// The dangerous case is the model declaring the USER'S SPECIFIC reading safe.
// We block when a reassurance word co-occurs with a reference to the user's own
// reading (possessive/demonstrative + metric, or a concrete BP number). General
// education ("a normal resting heart rate is 60–100") lacks that specific anchor
// and is intentionally NOT blocked.
function outputViolates(text: string): boolean {
  const specificReading =
    /\b(your|that|those|these|this)\s+(blood pressure|bp|spo2|oxygen|heart rate|pulse|temperature|reading|readings|numbers?|vitals?|results?)\b/i.test(text) ||
    /\b\d{2,3}\/\d{2,3}\b/.test(text);
  const reassure =
    /\b(fine|okay|ok|normal|safe|healthy)\b/i.test(text) ||
    /\b(nothing|no need)\s+to\s+worry\b/i.test(text) ||
    /\bdon'?t\s+worry\b/i.test(text);
  const falseReassurance = specificReading && reassure;
  const prescribes = /\btake\s+\d+\s*(mg|ml|mcg|tablets?)\b/i.test(text);
  return falseReassurance || prescribes;
}

function emergencyOutcome(
  triage: TriageResult,
  contacts: Array<{ label: string; tel: string }>,
): GuardrailOutcome {
  return {
    kind: 'emergency',
    action: 'SHOW_EMERGENCY_SCREEN',
    triage,
    callButtons: contacts.length ? contacts : [{ label: 'Call ambulance', tel: '103' }],
    message:
      triage.findings[0]?.message ??
      'A serious sign was detected. Please seek medical help immediately.',
  };
}

export async function processWithGuardrails(
  input: GuardrailInput,
  deps: GuardrailDeps,
): Promise<GuardrailOutcome> {
  // STEP 1 — telemetry triage overrides EVERYTHING.
  if (input.latestTelemetry) {
    const triage = assessTelemetry(input.latestTelemetry);
    if (triage.forceEmergencyScreen) return emergencyOutcome(triage, input.emergencyContacts);
  }

  // STEP 2 — sanitise input.
  const { clean, injectionBlocked } = sanitizeUserMessage(input.userMessage);
  if (injectionBlocked) {
    return {
      kind: 'blocked',
      reason: 'prompt_injection',
      message:
        "I'm here to help with pregnancy wellness. Let's keep our chat about how you're feeling — what would you like to talk about?",
    };
  }

  // STEP 3 — red-flag NLU on the user's words.
  if (textLooksEmergency(clean)) {
    const triage: TriageResult = {
      severity: 'emergency',
      forceEmergencyScreen: true,
      findings: [
        {
          code: 'SYMPTOM_RED_FLAG',
          severity: 'emergency',
          metric: 'symptom',
          message: 'What you describe can be serious in pregnancy and needs medical attention right away.',
        },
      ],
    };
    return emergencyOutcome(triage, input.emergencyContacts);
  }

  // STEP 4 — grounded LLM call (injected).
  const system = buildSystemPrompt(input.ragPassages);
  let raw: string;
  try {
    raw = await deps.callLLM(system, clean, input.locale);
  } catch {
    return {
      kind: 'blocked',
      reason: 'llm_unavailable',
      message:
        "I can't reach the assistant right now. If this is about how you feel physically, please contact your clinician. Try me again in a moment.",
    };
  }

  // STEP 5 — output filter.
  if (outputViolates(raw)) {
    return {
      kind: 'blocked',
      reason: 'unsafe_output',
      message:
        "I can share general wellness information, but I can't tell you whether a specific reading is safe. For that, please check with your doctor. Is there something general I can help explain?",
    };
  }

  return { kind: 'chat', message: raw, grounded: input.ragPassages.length > 0 };
}

// Exported for focused unit tests.
export const _internal = { textLooksEmergency, sanitizeUserMessage, outputViolates };
