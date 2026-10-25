'use server';

// features/search/actions.ts
//
// Record search for the top bar: people and things inside the pages, not just
// the pages themselves. It runs under the signed-in person's own session, so
// row level security still decides what each role can see (a Dean only gets
// their college's sections, an Applicant gets nothing). Which kinds of record
// are looked up per role below only avoids pointless queries; it is not the
// security boundary. A result opens the page that lists the record, filtered to
// it where that page supports a search (Documents does; the others open unfiltered).
import { createClient } from '@/lib/supabase/server';
import { getCurrentUser } from '@/lib/auth/session';
import type { NavIconName } from '@/lib/nav';

export type RecordHit = {
  key: string;
  label: string;
  detail: string;
  href: string;
  icon: NavIconName;
  kind: string;
};

const LIMIT = 5;

// "%", "_" and "\" mean something to ILIKE; the typed text is literal.
function pattern(text: string): string {
  return `%${text.replace(/[\\%_]/g, '\\$&')}%`;
}

type StudentRow = {
  id: string;
  student_number: string;
  applicants: { programs: { code: string } | null; users: { full_name: string } | null } | null;
};
type ApplicantRow = {
  id: string;
  applicant_ref: string;
  programs: { code: string } | null;
  users: { full_name: string } | null;
};
type UserRow = { id: string; full_name: string; email: string; role: string };
type SectionRow = { id: string; name: string; year_level: number; programs: { code: string } | null };
type SubjectRow = { id: string; code: string; title: string };
type RoomRow = { id: string; name: string; capacity: number | null };

export async function searchRecords(raw: string): Promise<RecordHit[]> {
  const text = raw.trim().slice(0, 60);
  if (text.length < 2) return [];

  const user = await getCurrentUser();
  if (!user) return [];

  const supabase = createClient();
  const like = pattern(text);
  const role = user.role;
  const hits: RecordHit[] = [];

  const sees = (...roles: string[]) => roles.includes(role);
  const jobs: Promise<void>[] = [];

  // Students, by number or by name.
  if (sees('registrar', 'finance', 'admin')) {
    // The Documents page can filter by student number, so Registrar and Admin land on that student.
    const href = (studentNumber: string) =>
      role === 'finance' ? '/finance/payments' : `/registrar/documents?tab=received&q=${encodeURIComponent(studentNumber)}`;
    const select = 'id, student_number, applicants!inner(programs(code), users!inner(full_name))';
    jobs.push(
      (async () => {
        const [byNumber, byName] = await Promise.all([
          supabase.from('students').select(select).ilike('student_number', like).limit(LIMIT),
          supabase.from('students').select(select).ilike('applicants.users.full_name', like).limit(LIMIT),
        ]);
        const seen = new Set<string>();
        const rows = [...((byNumber.data ?? []) as unknown as StudentRow[]), ...((byName.data ?? []) as unknown as StudentRow[])];
        for (const row of rows) {
          if (seen.has(row.id) || seen.size >= LIMIT) continue;
          seen.add(row.id);
          hits.push({
            key: `student-${row.id}`,
            label: row.applicants?.users?.full_name ?? row.student_number,
            detail: [row.student_number, row.applicants?.programs?.code].filter(Boolean).join(' · '),
            href: href(row.student_number),
            icon: 'accounts',
            kind: 'Student',
          });
        }
      })()
    );
  }

  // Applicants, by reference or by name.
  if (sees('registrar', 'admin')) {
    const select = 'id, applicant_ref, programs(code), users!inner(full_name)';
    jobs.push(
      (async () => {
        const [byRef, byName] = await Promise.all([
          supabase.from('applicants').select(select).ilike('applicant_ref', like).limit(LIMIT),
          supabase.from('applicants').select(select).ilike('users.full_name', like).limit(LIMIT),
        ]);
        const seen = new Set<string>();
        const rows = [...((byRef.data ?? []) as unknown as ApplicantRow[]), ...((byName.data ?? []) as unknown as ApplicantRow[])];
        for (const row of rows) {
          if (seen.has(row.id) || seen.size >= LIMIT) continue;
          seen.add(row.id);
          hits.push({
            key: `applicant-${row.id}`,
            label: row.users?.full_name ?? row.applicant_ref,
            detail: [row.applicant_ref, row.programs?.code].filter(Boolean).join(' · '),
            href: `/registrar/documents?q=${encodeURIComponent(row.applicant_ref)}`,
            icon: 'documents',
            kind: 'Applicant',
          });
        }
      })()
    );
  }

  // Accounts: only Admin can read other people's users rows.
  if (sees('admin')) {
    jobs.push(
      (async () => {
        const [byName, byEmail] = await Promise.all([
          supabase.from('users').select('id, full_name, email, role').ilike('full_name', like).limit(LIMIT),
          supabase.from('users').select('id, full_name, email, role').ilike('email', like).limit(LIMIT),
        ]);
        const seen = new Set<string>();
        const rows = [...((byName.data ?? []) as UserRow[]), ...((byEmail.data ?? []) as UserRow[])];
        for (const row of rows) {
          if (seen.has(row.id) || seen.size >= LIMIT) continue;
          seen.add(row.id);
          hits.push({
            key: `account-${row.id}`,
            label: row.full_name,
            detail: `${row.email} · ${row.role.replace('_', ' ')}`,
            href: '/admin/accounts',
            icon: 'accounts',
            kind: 'Account',
          });
        }
      })()
    );
  }

  // Sections, by name.
  if (sees('registrar', 'dean', 'college_secretary', 'admin')) {
    const href = role === 'registrar' ? '/registrar/schedules' : '/secretary/schedule';
    jobs.push(
      (async () => {
        const { data } = await supabase
          .from('sections')
          .select('id, name, year_level, programs(code)')
          .ilike('name', like)
          .limit(LIMIT);
        for (const row of (data ?? []) as unknown as SectionRow[]) {
          hits.push({
            key: `section-${row.id}`,
            label: [row.programs?.code, `${row.year_level}`, row.name].filter(Boolean).join(' '),
            detail: `Year ${row.year_level}`,
            href,
            icon: 'schedules',
            kind: 'Section',
          });
        }
      })()
    );
  }

  // Subjects and rooms live under Admin's Content page.
  if (sees('admin')) {
    jobs.push(
      (async () => {
        const [byCode, byTitle, rooms] = await Promise.all([
          supabase.from('subjects').select('id, code, title').ilike('code', like).limit(LIMIT),
          supabase.from('subjects').select('id, code, title').ilike('title', like).limit(LIMIT),
          supabase.from('rooms').select('id, name, capacity').ilike('name', like).limit(LIMIT),
        ]);
        const seen = new Set<string>();
        for (const row of [...((byCode.data ?? []) as SubjectRow[]), ...((byTitle.data ?? []) as SubjectRow[])]) {
          if (seen.has(row.id) || seen.size >= LIMIT) continue;
          seen.add(row.id);
          hits.push({ key: `subject-${row.id}`, label: row.code, detail: row.title, href: '/admin/content', icon: 'content', kind: 'Subject' });
        }
        for (const row of (rooms.data ?? []) as RoomRow[]) {
          hits.push({
            key: `room-${row.id}`,
            label: row.name,
            detail: row.capacity ? `${row.capacity} seats` : 'Room',
            href: '/admin/content',
            icon: 'content',
            kind: 'Room',
          });
        }
      })()
    );
  }

  await Promise.all(jobs);
  return hits;
}
