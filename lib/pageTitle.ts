// lib/pageTitle.ts
//
// Every page's <title> ends in the same suffix. pageTitle(name) builds the
// metadata object so a page need not repeat "| PLP Enrollment" itself.

export function pageTitle(name: string): { title: string } {
  return { title: `${name} | PLP Enrollment` };
}
