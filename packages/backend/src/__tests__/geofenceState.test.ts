/**
 * The geofence state machine's decision table.
 *
 * Every rule here decides whether a parent's phone buzzes. They were written
 * inline inside a Redis call and so had no tests at all — the integration test
 * exercised the happy path through a fake, which is not the same as pinning
 * what each rule is FOR.
 */

import { describe, it, expect } from 'vitest';
import { decideTransition } from '../cache/redis';

describe('when a state change should alert', () => {
  it('arriving fires enter', () => {
    expect(decideTransition('out', true)).toBe('enter');
  });

  it('leaving fires exit', () => {
    expect(decideTransition('in', false)).toBe('exit');
  });

  it('staying inside says nothing', () => {
    // The ordinary case: a child sitting in a classroom, fix after fix.
    expect(decideTransition('in', true)).toBeNull();
  });

  it('staying outside says nothing', () => {
    expect(decideTransition('out', false)).toBeNull();
  });

  it('the first sighting INSIDE a fence fires enter', () => {
    // Nothing stored — a new child, or state that expired. Arriving is still
    // an arrival, and it is what the parent asked to be told about.
    expect(decideTransition(null, true)).toBe('enter');
  });

  it('the first sighting OUTSIDE every fence says nothing', () => {
    // "Left Home" for a child who was never recorded at home is the kind of
    // alert that teaches a parent to ignore alerts. We never saw them arrive,
    // so there is nothing to have left.
    expect(decideTransition(null, false)).toBeNull();
  });

  it('is exhaustive over the six possible inputs', () => {
    // Guards the guard: three previous states x two current, all decided, no
    // combination falling through to undefined.
    const all: Array<['in' | 'out' | null, boolean]> = [
      ['in', true], ['in', false],
      ['out', true], ['out', false],
      [null, true], [null, false],
    ];
    for (const [prev, inside] of all) {
      const r = decideTransition(prev, inside);
      expect(r === null || r === 'enter' || r === 'exit', `prev=${prev} inside=${inside}`).toBe(true);
    }
    expect(all).toHaveLength(6);
  });
});
