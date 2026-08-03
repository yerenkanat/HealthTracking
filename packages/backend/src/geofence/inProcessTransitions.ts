/**
 * Geofence enter/exit debouncing held in this process, with no Redis.
 *
 * Two callers:
 *   1. `npm run dev` on test data, where no external service is running.
 *   2. The fallback when Redis is unreachable in production.
 *
 * (2) is the reason this is its own module rather than a closure inside
 * memoryDeps. Without it a Redis outage silently stopped every geofence alert:
 * resolveTransition rejected, the batch-level catch marked the whole fix
 * rejected, and a child leaving home produced a 200 and nothing else. Alerts
 * are the product; the cache is an optimisation, and an optimisation being
 * down must not switch the product off.
 *
 * What it gives up versus Redis: the state is per-process and does not survive
 * a restart. With one backend instance that is exactly equivalent. With several
 * it is not — each would debounce against its own view — so if this service is
 * ever scaled out, Redis has to be there rather than merely preferred.
 */

export type Transition = 'enter' | 'exit' | null;

export interface TransitionResolver {
  /** `null` means "no change" — debounced, so no alert. */
  resolve(childId: string, fenceId: string, inside: boolean): Transition;
}

/**
 * Wrap a Redis-backed resolver so an outage degrades instead of dropping the
 * crossing.
 *
 * Exported (rather than inlined at the one call site) so the outage behaviour
 * can be tested as the unit it is. Testing it through the ingest handler only
 * proves the handler's own error path, which is where this went wrong before:
 * every layer looked defensible on its own and the alert still vanished.
 */
export function withInProcessFallback(
  primary: (childId: string, fenceId: string, inside: boolean) => Promise<Transition>,
  onFallback: (err: Error) => void = () => {},
): (childId: string, fenceId: string, inside: boolean) => Promise<Transition> {
  const fallback = createInProcessTransitions();
  return async (childId, fenceId, inside) => {
    try {
      return await primary(childId, fenceId, inside);
    } catch (err) {
      onFallback(err as Error);
      return fallback.resolve(childId, fenceId, inside);
    }
  };
}

export function createInProcessTransitions(): TransitionResolver {
  const state = new Map<string, 'in' | 'out'>();
  return {
    resolve(childId, fenceId, inside) {
      const key = `${childId}:${fenceId}`;
      const next = inside ? 'in' : 'out';
      const prev = state.get(key) ?? null;
      state.set(key, next);

      if (prev === next) return null;
      // First fix we have ever seen for this fence, and the child is outside
      // it. Treated as "we simply do not know where they were before", not as
      // a crossing — otherwise every restart, and every child who is at school
      // when the process starts, fires a false "left home".
      if (prev === null && next === 'out') return null;
      return inside ? 'enter' : 'exit';
    },
  };
}
