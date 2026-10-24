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

export function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
}
