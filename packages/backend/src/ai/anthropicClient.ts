/**
 * Real Anthropic Claude implementation of the injected LLMCaller.
 * Kept separate from AIGuardrailProcessor so the safety logic stays SDK-free
 * (and unit-testable). Model: claude-opus-4-8 via the Messages API.
 */

import Anthropic from '@anthropic-ai/sdk';
import type { LLMCaller } from './AIGuardrailProcessor';

const MODEL = 'claude-opus-4-8';

export function createAnthropicCaller(apiKey = process.env.ANTHROPIC_API_KEY): LLMCaller {
  const client = new Anthropic({ apiKey });
  return async (system, userMessage, locale) => {
    const res = await client.messages.create({
      model: MODEL,
      max_tokens: 700,
      temperature: 0.3, // low — safety-adjacent, we want steadiness
      system,
      messages: [{ role: 'user', content: `[user_locale=${locale}]\n${userMessage}` }],
    });
    return res.content
      .filter((b): b is Anthropic.TextBlock => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim();
  };
}
