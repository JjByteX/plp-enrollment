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
//   admission_type  "new" or "transferee"
//   source_name     optional, defaults to "PLP Admissions"
import { isEmail } from '@/lib/auth/validate';

export type IntakePayload = {
  applicant_ref: string;
  full_name: string;
  email: string;
  program_code: string;
  admission_date: string;
  admission_type: 'new' | 'transferee';
  source_name: string;
};

export type ParsedIntake = { ok: true; value: IntakePayload } | { ok: false; reason: string };

export const DEFAULT_SOURCE = 'PLP Admissions';

function text(raw: Record<string, unknown>, key: string): string {
  const value = raw[key];
  return typeof value === 'string' ? value.trim() : '';
}

function isRealDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
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
  if (admissionType !== 'new' && admissionType !== 'transferee') {
    return { ok: false, reason: 'admission_type must be "new" or "transferee".' };
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
    },
  };
}

// The log table needs a value in every column, even for a request that failed
// validation. Missing or bad fields are logged as a placeholder; the real
// body is always kept in raw_payload and the reason says what was wrong.
export function logFieldsFor(raw: unknown, parsed: ParsedIntake) {
  if (parsed.ok) return parsed.value;

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
    admission_type: type === 'transferee' ? 'transferee' : 'new',
    source_name: text(body, 'source_name').slice(0, 60) || DEFAULT_SOURCE,
  };
}
