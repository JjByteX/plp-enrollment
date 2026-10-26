// lib/auth/validate.ts
//
// Checks shared by the forms (browser) and the server actions, so both
// apply the same rules. The server actions always re-check.

export const MIN_PASSWORD_LENGTH = 8;

// Returns the problem in plain words, or null when the password is fine.
export function checkPassword(password: string, confirm: string): string | null {
  if (password.length < MIN_PASSWORD_LENGTH) {
    return `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
  }
  if (password !== confirm) {
    return 'The two passwords do not match.';
  }
  return null;
}

// One local part and one domain around a single @, no spaces, and a dot in the
// domain with something on both sides of it. Checked step by step, because the
// one-line regex for this backtracks badly on long input.
export function isEmail(value: string): boolean {
  const email = value.trim();
  const at = email.indexOf('@');
  if (at < 1 || email.includes('@', at + 1) || /\s/.test(email)) return false;
  return email.slice(at + 1).slice(1, -1).includes('.');
}
