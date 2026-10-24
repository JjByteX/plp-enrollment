// lib/auth/roles.ts
//
// Roles, the area (URL folder) each role lands in, and which areas a role
// may open. The database enforces the real limits with row level security;
// this only decides which pages a person is sent to.
//
// Dean may also open /secretary (decision-log.md #4: the Dean can do
// everything the College Secretary does). Admin may open every staff area
// (enrollment-plan.md: Admin has every permission). Applicant and student
// areas are personal views, so Admin is not sent there.

export const ROLES = [
  'applicant',
  'student',
  'registrar',
  'finance',
  'dean',
  'college_secretary',
  'professor',
  'admin',
] as const;
export type Role = (typeof ROLES)[number];

export const AREAS = [
  'applicant',
  'student',
  'registrar',
  'finance',
  'dean',
  'secretary',
  'professor',
  'admin',
] as const;
export type Area = (typeof AREAS)[number];

// Roles an Admin may create. Applicants are created by the intake endpoint (step 5).
export const STAFF_ROLES = ['registrar', 'finance', 'dean', 'college_secretary', 'professor'] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

// Roles that belong to one college.
export const COLLEGE_ROLES: readonly Role[] = ['dean', 'college_secretary'];

export const ROLE_LABEL: Record<Role, string> = {
  applicant: 'Applicant',
  student: 'Student',
  registrar: 'Registrar',
  finance: 'Finance',
  dean: 'Dean',
  college_secretary: 'College Secretary',
  professor: 'Professor',
  admin: 'Admin',
};

const ROLE_HOME: Record<Role, Area> = {
  applicant: 'applicant',
  student: 'student',
  registrar: 'registrar',
  finance: 'finance',
  dean: 'dean',
  college_secretary: 'secretary',
  professor: 'professor',
  admin: 'admin',
};

const ROLE_AREAS: Record<Role, readonly Area[]> = {
  applicant: ['applicant'],
  student: ['student'],
  registrar: ['registrar'],
  finance: ['finance'],
  dean: ['dean', 'secretary'],
  college_secretary: ['secretary'],
  professor: ['professor'],
  admin: ['admin', 'registrar', 'finance', 'dean', 'secretary', 'professor'],
};

export function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (ROLES as readonly string[]).includes(value);
}

export function isArea(value: unknown): value is Area {
  return typeof value === 'string' && (AREAS as readonly string[]).includes(value);
}

export function homePath(role: Role): string {
  return `/${ROLE_HOME[role]}`;
}

export function canOpen(role: Role, area: Area): boolean {
  return ROLE_AREAS[role].includes(area);
}
