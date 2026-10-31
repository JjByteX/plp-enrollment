// features/admissions-intake/schema.ts
//
// The contract for the one call PLP Admissions makes to Enrollment
// (enrollment-plan.md, Connection to PLP Admissions; decision-log.md #11).
// JSON body, snake_case keys:
//   applicant_ref   ADM-2026-000042, never changes, catches duplicates
//   full_name       full name
//   email           the applicant's email
//   program_code    one of the 13 Admissions program codes (for example BSENT)
//   admission_date  YYYY-MM-DD
//   admission_type  "new", "transferee" or "foreign"
//   source_name     optional, defaults to "PLP Admissions"
//   verified_documents  optional list of document_requirements doc_type slugs
//                   that Admissions staff already approved (information only)
//   password_hash   optional bcrypt hash of the applicant's Admissions password
//                   (DEMO SHORTCUT: same login on both systems). When valid, the
//                   account is created with it and no set-password email is sent.
//                   Missing or not a bcrypt hash (a Google sign-up has none):
//                   the account is invited by email as before. Never logged.
import { isEmail } from '@/lib/auth/validate';
import { isRealDate, text } from '@/lib/validate';

export type IntakePayload = {
  applicant_ref: string;
  full_name: string;
  email: string;
  program_code: string;
  admission_date: string;
  admission_type: 'new' | 'transferee' | 'foreign';
  source_name: string;
  verified_documents: string[];
  password_hash: string | null;
};

export type ParsedIntake = { ok: true; value: IntakePayload } | { ok: false; reason: string };

export const DEFAULT_SOURCE = 'PLP Admissions';
const MAX_VERIFIED = 30;

// Anything that is not a plain slug is dropped rather than failing the whole
// handoff: this list is a convenience and must never block an applicant.
function verifiedDocuments(raw: Record<string, unknown>): string[] {
  const value = raw.verified_documents;
  if (!Array.isArray(value)) return [];
  const slugs = value.filter((item): item is string => typeof item === 'string' && /^[a-z0-9_]{2,40}$/.test(item));
  return Array.from(new Set(slugs))
    .slice(0, MAX_VERIFIED)
    .sort((a, b) => a.localeCompare(b));
}

// bcrypt only. PHP writes "$2y$" and Supabase Auth reads "$2b$" (same algorithm),
// so the prefix is normalised. A value that is not a bcrypt hash is ignored,
// never rejected: it only decides how the login is made, and must not block an applicant.
const BCRYPT_HASH = /^\$2[abxy]\$\d{2}\$[./A-Za-z0-9]{53}$/;

function passwordHash(raw: Record<string, unknown>): string | null {
  const value = raw.password_hash;
  if (typeof value !== 'string' || !BCRYPT_HASH.test(value)) return null;
  return `$2b$${value.slice(4)}`;
}

// The request body as it is kept in the intake log: the password hash is never
// stored, only a note that one was sent. Admin resend reads this copy, so a
// resend of an applicant who has no account yet falls back to the email invite.
export function bodyForLog(raw: unknown): unknown {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return raw;
  if (!('password_hash' in raw)) return raw;
  return { ...raw, password_hash: '[not stored]' };
}

export function parseIntakePayload(raw: unknown): ParsedIntake {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'The request body must be a JSON object.' };
  }
  const body = raw as Record<string, unknown>;

  const applicantRef = text(body, 'applicant_ref');
  if (!/^[A-Za-z0-9-]{3,40}$/.test(applicantRef)) {
    return { ok: false, reason: 'applicant_ref is missing or not valid (3 to 40 letters, digits or dashes).' };
  }
  const fullName = text(body, 'full_name');
  if (fullName.length < 2 || fullName.length > 150) {
    return { ok: false, reason: 'full_name is missing or longer than 150 characters.' };
  }
  const email = text(body, 'email').toLowerCase();
  if (!isEmail(email) || email.length > 254) {
    return { ok: false, reason: 'email is missing or not a valid address.' };
  }
  const programCode = text(body, 'program_code');
  if (programCode.length === 0 || programCode.length > 20) {
    return { ok: false, reason: 'program_code is missing.' };
  }
  const admissionDate = text(body, 'admission_date');
  if (!isRealDate(admissionDate)) {
    return { ok: false, reason: 'admission_date must be a real date written YYYY-MM-DD.' };
  }
  const admissionType = text(body, 'admission_type');
  if (admissionType !== 'new' && admissionType !== 'transferee' && admissionType !== 'foreign') {
    return { ok: false, reason: 'admission_type must be "new", "transferee" or "foreign".' };
  }
  const sourceName = text(body, 'source_name') || DEFAULT_SOURCE;
  if (sourceName.length > 60) {
    return { ok: false, reason: 'source_name is longer than 60 characters.' };
  }

  return {
    ok: true,
    value: {
      applicant_ref: applicantRef,
      full_name: fullName,
      email,
      program_code: programCode,
      admission_date: admissionDate,
      admission_type: admissionType,
      source_name: sourceName,
      verified_documents: verifiedDocuments(body),
      password_hash: passwordHash(body),
    },
  };
}

// The log table needs a value in every column, even for a request that failed
// validation. Missing or bad fields are logged as a placeholder; the real
// body is always kept in raw_payload and the reason says what was wrong.
export function logFieldsFor(raw: unknown, parsed: ParsedIntake) {
  if (parsed.ok) {
    // The log table has no column for verified_documents; the raw body keeps it.
    // The password hash is never logged, not even in the raw body (see bodyForLog).
    const { verified_documents: _verified, password_hash: _hash, ...logged } = parsed.value;
    void _verified;
    void _hash;
    return logged;
  }

  const body: Record<string, unknown> =
    typeof raw === 'object' && raw !== null && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {};
  const pick = (key: string, max: number) => text(body, key).slice(0, max) || '(missing)';
  const date = text(body, 'admission_date');
  const type = text(body, 'admission_type');

  return {
    applicant_ref: pick('applicant_ref', 40),
    full_name: pick('full_name', 150),
    email: pick('email', 254),
    program_code: pick('program_code', 20),
    admission_date: isRealDate(date) ? date : new Date().toISOString().slice(0, 10),
    admission_type: type === 'transferee' || type === 'foreign' ? type : 'new',
    source_name: text(body, 'source_name').slice(0, 60) || DEFAULT_SOURCE,
  };
}
