// features/admissions-intake/secret.ts
//
// Checks the shared secret on calls from PLP Admissions (the intake call and
// the program list). Compares hashes so the check takes the same time whatever
// the guess is.
import { createHash, timingSafeEqual } from 'node:crypto';

export function hasValidSecret(header: string | null, secret: string): boolean {
  if (!header?.startsWith('Bearer ')) return false;
  const given = createHash('sha256').update(header.slice('Bearer '.length).trim()).digest();
  const expected = createHash('sha256').update(secret).digest();
  return timingSafeEqual(given, expected);
}
