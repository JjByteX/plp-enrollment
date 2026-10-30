// features/content/exportSubjects.ts
//
// Downloads the subjects of the chosen program as a CSV file in the same
// layout as the import template (importSubjects.ts), so the file can be edited
// and imported again. Browser only. The file starts with a byte-order mark so
// Excel reads accented letters correctly; the import reads it back.
import { SEMESTER_LABEL, type Semester } from '@/features/cor/schema';
import { SUBJECT_IMPORT_HEADERS } from './importSubjects';
import type { SubjectRow } from './queries';

function csvCell(value: string | number): string {
  const text = String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

const yesNo = (value: boolean) => (value ? 'Yes' : 'No');

export function subjectsToCsv(subjects: SubjectRow[]): string {
  const lines = [SUBJECT_IMPORT_HEADERS.join(',')];
  for (const subject of subjects) {
    // A subject with no year level cannot be imported (the import needs one), so its cell stays empty.
    const semester = subject.semester in SEMESTER_LABEL ? (subject.semester as Semester) : subject.semester;
    lines.push(
      [
        subject.code,
        subject.title,
        subject.units,
        subject.yearLevel ?? '',
        semester,
        yesNo(subject.hasLaboratory),
        yesNo(subject.offeredInSummer),
      ]
        .map(csvCell)
        .join(','),
    );
  }
  return `\uFEFF${lines.join('\r\n')}\r\n`;
}

export function downloadSubjectsCsv(programCode: string, subjects: SubjectRow[]): void {
  const blob = new Blob([subjectsToCsv(subjects)], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `${programCode.replace(/[^A-Za-z0-9_-]+/g, '-')}-subjects.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}
