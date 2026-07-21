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

// --- What the guardrail itself says ---
//
// Every string below used to be an English literal. The app defaults to Russian
// and displays these verbatim — it cannot translate free text — so a Russian
// speaker who typed "ребёнок не шевелится" was correctly DETECTED and then
// answered in a language she may not read. On the emergency path.
//
// input.locale was already threaded in for the LLM call; it just was not used
// for anything the guardrail authored itself.
type Loc = 'ru' | 'kk' | 'en';

/** Normalise "ru-RU"/"RU"/undefined → a supported locale. Russian is the app default. */
function toLocale(raw: string | undefined): Loc {
  const head = (raw ?? '').slice(0, 2).toLowerCase();
  return head === 'kk' ? 'kk' : head === 'en' ? 'en' : 'ru';
}

const MESSAGES: Record<string, Record<Loc, string>> = {
  injection: {
    ru: 'Я здесь, чтобы помочь с самочувствием во время беременности. Давайте вернёмся к тому, как вы себя чувствуете — о чём хотите поговорить?',
    kk: 'Мен жүктілік кезіндегі әл-ауқат туралы көмектесемін. Өзіңізді қалай сезінетініңізге оралайық — не туралы сөйлескіңіз келеді?',
    en: "I'm here to help with pregnancy wellness. Let's keep our chat about how you're feeling — what would you like to talk about?",
  },
  llmUnavailable: {
    ru: 'Сейчас не удаётся связаться с помощником. Если вопрос о самочувствии, обратитесь к врачу. Попробуйте ещё раз через минуту.',
    kk: 'Қазір көмекшіге қосыла алмай тұрмын. Сұрағыңыз денсаулыққа қатысты болса, дәрігеріңізге хабарласыңыз. Бір минуттан кейін қайталап көріңіз.',
    en: "I can't reach the assistant right now. If this is about how you feel physically, please contact your clinician. Try me again in a moment.",
  },
  unsafeOutput: {
    ru: 'Я могу рассказать об общем, но не могу сказать, безопасен ли конкретный показатель. С этим — к врачу. Объяснить что-нибудь в общих чертах?',
    kk: 'Мен жалпы мәліметпен бөлісе аламын, бірақ нақты көрсеткіштің қауіпсіз екенін айта алмаймын. Ол үшін дәрігерге жүгініңіз. Жалпы бірдеңе түсіндірейін бе?',
    en: "I can share general wellness information, but I can't tell you whether a specific reading is safe. For that, please check with your doctor. Is there something general I can help explain?",
  },
  symptomRedFlag: {
    ru: 'То, что вы описываете, при беременности может быть серьёзным и требует немедленной медицинской помощи.',
    kk: 'Сіз сипаттаған жағдай жүктілік кезінде қауіпті болуы мүмкін және дереу дәрігерлік көмекті қажет етеді.',
    en: 'What you describe can be serious in pregnancy and needs medical attention right away.',
  },
  genericEmergency: {
    ru: 'Обнаружен серьёзный признак. Пожалуйста, немедленно обратитесь за медицинской помощью.',
    kk: 'Күрделі белгі анықталды. Дереу дәрігерлік көмекке жүгініңіз.',
    en: 'A serious sign was detected. Please seek medical help immediately.',
  },
};

const say = (key: keyof typeof MESSAGES | string, locale: Loc): string =>
  MESSAGES[key][locale];

// --- Red-flag symptom detection on free text (defense-in-depth) ---
//
// These MUST cover every language the app ships in. The app defaults to
// Russian and the assistant answers in the user's own language, so an
// English-only rule set left this layer switched off for most users: "не могу
// дышать" and "ребёнок не шевелится" sailed through while "I can't breathe"
// escalated correctly.
//
// Note on \b and \w: both are ASCII-only in JavaScript, so neither works next
// to Cyrillic — `сильн\w*` never matches "сильная", and a \b before "не" is not
// a boundary at all. The non-English patterns use \p{L} with the /u flag for
// word characters, and match on stems so case endings come along for free
// (кровотечение / кровотечения / кровотечением).
const RED_FLAG_PATTERNS: RegExp[] = [
  // English
  /\b(can'?t|cannot|trouble|hard to)\s+breath/i,
  // "vision is blurry" and "blurred vision" both have to land, not just
  // "vision blurry" — this only matched the phrasing nobody uses.
  /\b(blurred|blurry|double)\s+vision/i,
  /\bvision\s+(is\s+|has\s+)?(blur|loss|lost|spots|chang|going)/i,
  /\b(severe|worst|terrible)\s+headache/i,
  /\b(heavy|severe)\s+(bleeding|blood)/i,
  /\b(baby|fetus).{0,20}(not moving|stopped moving|no movement|hasn'?t moved)/i,
  /\b(faint|passed out|blacked out|seizure|convuls)/i,
  /\bsevere\s+(abdominal|belly|stomach)\s+pain/i,

  // Russian
  /(не могу|тяжело|трудно|нечем)\s+дыш/iu,
  /задыха/iu,
  /кровотеч/iu,
  /(много|сильно)\s+кров/iu,
  /(туман|пелена|мушки|темнеет)/iu,
  /(зрение|вижу).{0,20}(упало|ухудш|плохо|пропа|не\s)/iu,
  /(сильн\p{L}*|невыносим\p{L}*|ужасн\p{L}*|резк\p{L}*)\s+(головная\s+боль|боль\s+в\s+голове)/iu,
  /сильно\s+болит\s+голова/iu,
  /(ребёнок|ребенок|малыш|плод).{0,25}(не\s+шевел|не\s+двига|не\s+толка)/iu,
  /(нет|отсутств\p{L}*)\s+шевелен/iu,
  /(потеряла\s+сознание|теряю\s+сознание|обморок|судорог|припадок)/iu,
  /(сильн\p{L}*|резк\p{L}*|остр\p{L}*)\s+боль\s+в\s+живот/iu,
  /сильно\s+болит\s+живот/iu,

  // Kazakh
  /(дем\s+ала\s+алмай|тыныс\s+ал\p{L}*\s+қиын|демігу|тұншығ)/iu,
  /қан\s*кет/iu,
  /(көз\p{L}*\s+(көрмей|тұманд)|көру\s+нашарла|көз\p{L}*\s+алды\s+тұманд)/iu,
  /бас\p{L}*\s+(қатты\s+)?ауыр/iu,
  /қатты\s+бас\s+ауру/iu,
  /(бала|нәресте).{0,25}(қозғалмай|қимылдамай|тыпырламай)/iu,
  /(есінен\s+тан|талып\s+қал|естен\s+тан|құрыс)/iu,
  /іш\p{L}*\s+(қатты\s+)?ауыр/iu,
  /қатты\s+іш\s+ауру/iu,
];
function textLooksEmergency(text: string): boolean {
  return RED_FLAG_PATTERNS.some((re) => re.test(text));
}

// --- Prompt-injection hardening ---
const INJECTION_PATTERNS: RegExp[] = [
  // The qualifiers repeat: "ignore all previous instructions" is the canonical
  // phrasing and the original pattern allowed only ONE of them, so the most
  // common injection of all slipped past.
  /ignore\s+(all\s+|the\s+above\s+|previous\s+|prior\s+)*(instructions|prompts?|rules)/i,
  /disregard\s+(all\s+|the\s+above\s+|previous\s+)*(instructions|prompts?|rules)/i,
  /you are (now|actually) [a-z ]{0,30}(dan|jailbreak|developer mode)/i,
  /(reveal|print|show|repeat).{0,20}(system prompt|instructions)/i,
  // Same reason as the red flags: most users are writing in Russian.
  /(игнорируй|игнорируйте|забудь|забудьте|не\s+обращай\s+внимания\s+на)\s+(на\s+)?(все\s+|вс[её]\s+|предыдущие\s+|прошлые\s+)*(инструкци\p{L}*|указани\p{L}*|правил\p{L}*)/iu,
  /(покажи|выведи|раскрой|напиши|повтори)\p{L}*\s*(мне\s+)?(свой\s+|свои\s+|системн\p{L}*\s+)(промпт|инструкци\p{L}*)/iu,
  /ты\s+(теперь|на\s+самом\s+деле)\s+[\p{L} ]{0,30}(dan|джейлбрейк|режим\s+разработчика)/iu,
  /(елемеу|елеме|ұмыт)\p{L}*\s+(алдыңғы\s+)?(нұсқаулар\p{L}*|ережелер\p{L}*)/iu,
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
function outputViolates(text: string, telemetry?: BandTelemetry): boolean {
  // A BP pair in the text is only "her reading" if it IS her reading.
  //
  // This used to treat ANY nn/nn as specific, which blocked the single most
  // useful thing a pregnancy app can teach: "normal blood pressure is under
  // 140/90" was refused in all three languages, and she got the "I can't tell
  // you whether a reading is safe" deflection instead of the threshold. The
  // code comment already said general education must not be blocked; the rule
  // just did not match the comment.
  //
  // Comparing against the actual telemetry is both narrower AND stricter: if her
  // reading really is 140/90, calling that fine is still blocked.
  const quotesHerNumbers = (() => {
    const sys = telemetry?.systolicMmHg;
    const dia = telemetry?.diastolicMmHg;
    if (sys == null && dia == null) return false;
    for (const m of text.matchAll(/\b(\d{2,3})\/(\d{2,3})\b/g)) {
      if (sys != null && Number(m[1]) === sys) return true;
      if (dia != null && Number(m[2]) === dia) return true;
    }
    return false;
  })();

  const specificReading =
    /\b(your|that|those|these|this)\s+(blood pressure|bp|spo2|oxygen|heart rate|pulse|temperature|reading|readings|numbers?|vitals?|results?)\b/i.test(text) ||
    /(ваш\p{L}*|эт\p{L}+|такое)\s+(давлени|пульс|сатураци|кислород|температур|показател|значени|результат|цифр)/iu.test(text) ||
    /(қысым|пульс|температура|көрсеткіш|оттег|нәтиже)\p{L}*(ыңыз|іңіз)/iu.test(text) ||
    quotesHerNumbers;
  // "Above normal" is a WARNING, not reassurance — but it contains the word
  // "normal", and matching on the bare word refused exactly the sentence we
  // most want said. Found by running the app's own advisory copy through this
  // filter: "Your temperature is above normal. Rest and hydrate" was blocked.
  //
  // Strip the comparative constructions before looking for reassurance.
  const withoutComparisons = text
    .replace(/\b(above|below|outside|over|under|higher than|lower than)\s+(the\s+)?normal\b/gi, ' ')
    .replace(/\b(not|isn'?t|is not|no longer)\s+(normal|fine|safe|healthy|okay|ok)\b/gi, ' ')
    .replace(/(выше|ниже|вне)\s+нормы/giu, ' ')
    .replace(/(не\s+в\s+норме|не\s+нормальн\p{L}*)/giu, ' ')
    .replace(/(қалыптан\s+жоғары|қалыптан\s+төмен)/giu, ' ');

  const reassure =
    /\b(fine|okay|ok|normal|safe|healthy)\b/i.test(withoutComparisons) ||
    /\b(nothing|no need)\s+to\s+worry\b/i.test(text) ||
    /\bdon'?t\s+worry\b/i.test(text) ||
    /(в\s+норме|нормальн\p{L}*|в\s+порядке|вс[её]\s+хорошо|безопасн\p{L}*|здоров\p{L}*)/iu.test(withoutComparisons) ||
    /(не\s+волнуйтесь|не\s+переживайте|не\s+беспокойтесь|беспокоиться\s+не\s+о\s+чем)/iu.test(text) ||
    /(қалыпты|қауіпсіз|жақсы|дұрыс)/iu.test(text) ||
    /(алаңдамаңыз|уайымдамаңыз)/iu.test(text);
  const falseReassurance = specificReading && reassure;

  // A dose plus an instruction to take it. Kept as two separate signals rather
  // than one phrase so word order doesn't matter — Kazakh puts the verb last
  // ("Күніне 500 мг қабылдаңыз"), which a verb-then-dose pattern would miss.
  const hasDose = /\d+\s*(mg|ml|mcg|tablets?|мг|мл|мкг|таблет\p{L}*|капс\p{L}*)/iu.test(text);
  const tellsToTake =
    /\b(take|takes?|taking)\b/i.test(text) ||
    /(приним\p{L}+|прими|выпей\p{L}*|пейте|пить)/iu.test(text) ||
    /(ішіңіз|қабылдаңыз|іш\p{L}*)/iu.test(text);

  // Naming a drug and telling her to take it is prescribing whether or not a
  // dose is attached — "принимайте аспирин каждый день" carried no number and
  // sailed through. It matters most in pregnancy, where the specific drug is
  // the whole question: ibuprofen and aspirin are not casual suggestions.
  //
  // A drug list can never be complete, so this is a floor, not a filter. The
  // system prompt remains the primary control; this catches what leaks past it.
  const namesADrug =
    /\b(ibuprofen|aspirin|paracetamol|acetaminophen|naproxen|codeine|antibiotics?|misoprostol|warfarin)\b/i.test(text) ||
    /(ибупрофен|аспирин|парацетамол|ацетаминофен|напроксен|кодеин|антибиотик|мизопростол|варфарин)/iu.test(text) ||
    /(ибупрофен|аспирин|парацетамол|антибиотик)\p{L}*/iu.test(text);

  const prescribes = tellsToTake && (hasDose || namesADrug);
  return falseReassurance || prescribes;
}

function emergencyOutcome(
  triage: TriageResult,
  contacts: Array<{ label: string; tel: string }>,
  locale: Loc,
): GuardrailOutcome {
  return {
    kind: 'emergency',
    action: 'SHOW_EMERGENCY_SCREEN',
    triage,
    // 'Call ambulance' stays in English deliberately: the app matches this exact
    // string in EmergencyLabels to pick a localized label. Translating it here
    // would break that match and ship English to the emergency screen.
    callButtons: contacts.length ? contacts : [{ label: 'Call ambulance', tel: '103' }],
    message: triage.findings[0]?.message ?? say('genericEmergency', locale),
  };
}

export async function processWithGuardrails(
  input: GuardrailInput,
  deps: GuardrailDeps,
): Promise<GuardrailOutcome> {
  const loc = toLocale(input.locale);

  // STEP 1 — telemetry triage overrides EVERYTHING.
  if (input.latestTelemetry) {
    const triage = assessTelemetry(input.latestTelemetry);
    if (triage.forceEmergencyScreen) {
      return emergencyOutcome(triage, input.emergencyContacts, loc);
    }
  }

  // STEP 2 — sanitise input.
  const { clean, injectionBlocked } = sanitizeUserMessage(input.userMessage);
  if (injectionBlocked) {
    return { kind: 'blocked', reason: 'prompt_injection', message: say('injection', loc) };
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
          message: say('symptomRedFlag', loc),
        },
      ],
    };
    return emergencyOutcome(triage, input.emergencyContacts, loc);
  }

  // STEP 4 — grounded LLM call (injected).
  const system = buildSystemPrompt(input.ragPassages);
  let raw: string;
  try {
    raw = await deps.callLLM(system, clean, input.locale);
  } catch {
    return { kind: 'blocked', reason: 'llm_unavailable', message: say('llmUnavailable', loc) };
  }

  // STEP 5 — output filter.
  if (outputViolates(raw, input.latestTelemetry)) {
    return { kind: 'blocked', reason: 'unsafe_output', message: say('unsafeOutput', loc) };
  }

  return { kind: 'chat', message: raw, grounded: input.ragPassages.length > 0 };
}

// Exported for focused unit tests.
export const _internal = { textLooksEmergency, sanitizeUserMessage, outputViolates, toLocale, MESSAGES };
