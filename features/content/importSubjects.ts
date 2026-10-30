// features/content/importSubjects.ts
//
// Turns the rows of an uploaded subject file (the template in public/templates)
// into subjects, and says which rows are wrong and why. No server imports and
// no file reading, so the modal can use it for the preview and the tests can
// run it on plain arrays. The real checks are parseSubjectInput's (the same
// ones the Add subject form uses); this file only turns spreadsheet cells into
// the values that function expects.
//
// The file format (keep public/templates/subjects-import-template.* in step):
//   Row 1 is the header. Columns may be in any order; extra columns are ignored.
//   Code, Title, Units, Year Level, Semester     required
//   Has Laboratory, Offered In Summer            optional, Yes or No, default No
//   One subject per row. Blank rows are skipped. The program is the one chosen
//   on the page, so the file has no program column.
import { yearLabel } from '@/features/cor/schema';
import { MAX_YEAR, parseSubjectInput, type SubjectInput } from './schema';

export const SUBJECT_TEMPLATE_XLSX = '/templates/subjects-import-template.xlsx';
export const SUBJECT_TEMPLATE_CSV = '/templates/subjects-import-template.csv';

export const SUBJECT_IMPORT_HEADERS = [
  'Code',
  'Title',
  'Units',
  'Year Level',
  'Semester',
  'Has Laboratory',
  'Offered In Summer',
] as const;

const REQUIRED_HEADERS = SUBJECT_IMPORT_HEADERS.slice(0, 5);

export const MAX_IMPORT_ROWS = 500;
export const MAX_IMPORT_BYTES = 2 * 1024 * 1024;

export type ImportRow = { row: number; subject: SubjectInput };
export type ImportProblem = { row: number; reason: string };
export type SubjectSheet =
  | { ok: true; rows: ImportRow[]; problems: ImportProblem[] }
  | { ok: false; reason: string }; // the file as a whole cannot be used

// "Year Level", "year_level" and " YEAR LEVEL " are the same column.
function headerKey(value: unknown): string {
  return typeof value === 'string' ? value.toLowerCase().replace(/[^a-z0-9]/g, '') : '';
}

function isBlank(cell: unknown): boolean {
  return cell === null || cell === undefined || (typeof cell === 'string' && cell.trim() === '');
}

function cellText(cell: unknown): string {
  if (typeof cell === 'string') return cell.trim();
  if (typeof cell === 'number' && Number.isFinite(cell)) return String(cell);
  return '';
}

// Units: a number cell, or text like "3", "3.0" or "3,0" (some locales write the decimal comma).
function cellUnits(cell: unknown): number {
  if (typeof cell === 'number') return cell;
  const raw = cellText(cell).replace(',', '.');
  return /^\d+(\.\d+)?$/.test(raw) ? Number(raw) : Number.NaN;
}

// Year level: 1 to 6, or the label the page shows ("First Year", "1st year").
const YEAR_BY_LABEL: Record<string, number> = Object.fromEntries(
  Array.from({ length: MAX_YEAR }, (_, index) => [yearLabel(index + 1).toLowerCase(), index + 1]),
);

function cellYear(cell: unknown): number {
  if (typeof cell === 'number') return cell;
  const raw = cellText(cell).toLowerCase();
  const byLabel = YEAR_BY_LABEL[raw];
  if (byLabel) return byLabel;
  const match = /^(\d+)(?:st|nd|rd|th)?(?:\s*year)?$/.exec(raw);
  return match ? Number(match[1]) : Number.NaN;
}

const SEMESTER_WORDS: Record<string, string> = {
  '1': '1st',
  '1st': '1st',
  first: '1st',
  '1st semester': '1st',
  'first semester': '1st',
  '2': '2nd',
  '2nd': '2nd',
  second: '2nd',
  '2nd semester': '2nd',
  'second semester': '2nd',
  summer: 'summer',
};

function cellSemester(cell: unknown): string | null {
  return SEMESTER_WORDS[cellText(cell).toLowerCase()] ?? null;
}

// Yes or No. An empty cell is No. Anything else is refused rather than guessed.
function cellFlag(cell: unknown): boolean | null {
  if (isBlank(cell)) return false;
  if (typeof cell === 'boolean') return cell;
  const raw = cellText(cell).toLowerCase();
  if (['yes', 'y', 'true', '1'].includes(raw)) return true;
  if (['no', 'n', 'false', '0'].includes(raw)) return false;
  return null;
}

export function parseSubjectSheet(grid: unknown[][], programId: string): SubjectSheet {
  if (grid.length === 0) return { ok: false, reason: 'The file is empty.' };

  const columns = new Map<string, number>();
  (grid[0] ?? []).forEach((cell, index) => {
    const key = headerKey(cell);
    if (key && !columns.has(key)) columns.set(key, index);
  });
  const at = (header: string) => columns.get(headerKey(header));

  const missing = REQUIRED_HEADERS.filter((header) => at(header) === undefined);
  if (missing.length > 0) {
    return {
      ok: false,
      reason: `The first row must be the header from the template. Missing: ${missing.join(', ')}.`,
    };
  }

  const dataRows: { row: number; cells: unknown[] }[] = [];
  grid.slice(1).forEach((cells, index) => {
    if (cells.some((cell) => !isBlank(cell))) dataRows.push({ row: index + 2, cells });
  });
  if (dataRows.length === 0) return { ok: false, reason: 'The file has no subjects below the header row.' };
  if (dataRows.length > MAX_IMPORT_ROWS) {
    return { ok: false, reason: `The file has more than ${MAX_IMPORT_ROWS} subjects. Split it into smaller files.` };
  }

  const rows: ImportRow[] = [];
  const problems: ImportProblem[] = [];
  const firstRowOfCode = new Map<string, number>();

  for (const { row, cells } of dataRows) {
    const cell = (header: string) => {
      const index = at(header);
      return index === undefined ? null : (cells[index] ?? null);
    };

    const semester = cellSemester(cell('Semester'));
    if (semester === null) {
      problems.push({ row, reason: 'Semester must be 1st, 2nd or summer.' });
      continue;
    }
    const hasLaboratory = cellFlag(cell('Has Laboratory'));
    if (hasLaboratory === null) {
      problems.push({ row, reason: 'Has Laboratory must be Yes or No.' });
      continue;
    }
    const offeredInSummer = cellFlag(cell('Offered In Summer'));
    if (offeredInSummer === null) {
      problems.push({ row, reason: 'Offered In Summer must be Yes or No.' });
      continue;
    }

    const parsed = parseSubjectInput({
      programId,
      code: cellText(cell('Code')),
      title: cellText(cell('Title')),
      units: cellUnits(cell('Units')),
      yearLevel: cellYear(cell('Year Level')),
      semester,
      hasLaboratory,
      offeredInSummer,
    });
    if (!parsed.ok) {
      problems.push({ row, reason: parsed.reason });
      continue;
    }

    // The database treats "COMP 101" and "comp 101" as two codes; in one file that is a slip.
    const key = parsed.value.code.toLowerCase();
    const first = firstRowOfCode.get(key);
    if (first !== undefined) {
      problems.push({ row, reason: `The code ${parsed.value.code} is already in row ${first}.` });
      continue;
    }
    firstRowOfCode.set(key, row);
    rows.push({ row, subject: parsed.value });
  }

  return { ok: true, rows, problems };
}
