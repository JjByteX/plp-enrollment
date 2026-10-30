// features/content/readSubjectFile.ts
//
// Reads a chosen .csv or .xlsx file in the browser into rows of cells, for
// parseSubjectSheet. The file never leaves the browser; only the checked
// subjects are sent to the server. The two parsers load when a file is chosen,
// so the Content page does not carry them until then.
//
// Rows keep their place (blank rows are not dropped here), so a row number in a
// message is the row number Admin sees in Excel.
import { MAX_IMPORT_BYTES } from './importSubjects';

export type FileRead = { ok: true; grid: unknown[][] } | { ok: false; reason: string };

const UNREADABLE = 'The file could not be read. Use the template, saved as .csv or .xlsx.';

// Excel's "CSV (Comma delimited)" on Windows is not UTF-8. Try UTF-8 first, then Windows-1252,
// so a title with an accented letter does not turn into a broken character.
async function csvText(file: File): Promise<string> {
  const bytes = await file.arrayBuffer();
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder('windows-1252').decode(bytes);
  }
}

export async function readSubjectFile(file: File): Promise<FileRead> {
  if (file.size > MAX_IMPORT_BYTES) return { ok: false, reason: 'The file is larger than 2 MB.' };

  const name = file.name.toLowerCase();
  try {
    if (name.endsWith('.xlsx')) {
      const { readSheet } = await import('read-excel-file/browser');
      return { ok: true, grid: await readSheet(file) };
    }
    if (name.endsWith('.csv')) {
      const { default: Papa } = await import('papaparse');
      // The delimiter is detected, so a semicolon-separated file from a regional Excel also reads.
      const result = Papa.parse<string[]>(await csvText(file), { skipEmptyLines: false });
      return result.data.length > 0 ? { ok: true, grid: result.data } : { ok: false, reason: 'The file is empty.' };
    }
  } catch {
    return { ok: false, reason: UNREADABLE };
  }
  return { ok: false, reason: 'Choose a .csv or .xlsx file. An older .xls file must be saved as .xlsx first.' };
}
