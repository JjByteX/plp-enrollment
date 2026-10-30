// features/section-documents/queries.ts
//
// Read for the Sections pages: for the current term, each section with its
// students and whether each holds an assessment slip and a COR. It runs under
// the signed-in person's session; the database function section_document_status()
// limits the Dean and College Secretary to their own college.
import { createClient } from '@/lib/supabase/server';

export type SectionDocStudent = {
  studentId: string;
  studentNumber: string;
  fullName: string;
  slipIssued: boolean;
  corIssued: boolean;
};

export type SectionDocGroup = {
  sectionId: string;
  section: string; // "BSIT 1A"
  students: SectionDocStudent[];
};

type Raw = {
  section_id: string;
  section: string;
  student_id: string;
  student_number: string;
  full_name: string;
  slip_issued: boolean;
  cor_issued: boolean;
};

export async function listSectionDocuments(): Promise<SectionDocGroup[]> {
  const supabase = createClient();
  const { data } = await supabase.rpc('section_document_status');

  // Rows arrive ordered by section, so a new group starts whenever the section changes.
  const groups: SectionDocGroup[] = [];
  const byId = new Map<string, SectionDocGroup>();
  for (const row of (data ?? []) as Raw[]) {
    let group = byId.get(row.section_id);
    if (!group) {
      group = { sectionId: row.section_id, section: row.section, students: [] };
      byId.set(row.section_id, group);
      groups.push(group);
    }
    group.students.push({
      studentId: row.student_id,
      studentNumber: row.student_number,
      fullName: row.full_name,
      slipIssued: row.slip_issued,
      corIssued: row.cor_issued,
    });
  }
  return groups;
}
