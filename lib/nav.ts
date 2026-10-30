// lib/nav.ts
//
// Sidebar links per role. Plain data: each link names its icon (Heroicons, see
// components/NavIcons.tsx). Labels match the staff home lists in
// features/dashboards/queries.ts. Applicants and Students follow one linear
// flow shown by the "Your next step" card, so they get no sidebar
// (ux-ui-guidelines.md, layout pattern rules).
import type { Role } from '@/lib/auth/roles';

// Icon names are Heroicons (24 outline) component names without the "Icon"
// suffix. components/NavIcons.tsx maps each name to its component.
export type NavIconName =
  | 'home' | 'visits' | 'reschedules' | 'documents' | 'schedules' | 'slips' | 'cor' | 'sections' | 'payments'
  | 'grades' | 'prerequisites' | 'accounts' | 'content' | 'admissions' | 'audit' | 'registrar' | 'finance' | 'dean' | 'secretary' | 'professor';

// `keywords` are extra search-only terms (abbreviations, synonyms, the full
// name behind an acronym) that feed the top-bar search alongside the label,
// so a near-miss or shorthand still finds the right area.
// `children` are the item's own subpages (Admin's sidebar nests each staff
// area's pages under it). The item itself stays a link to that area's home.
export type NavItem = {
  label: string;
  href: string;
  icon: NavIconName;
  exact?: boolean;
  keywords?: string[];
  children?: NavItem[];
};
export type NavGroup = { label: string | null; items: NavItem[] };

const REGISTRAR: NavItem[] = [
  { label: 'Visits', href: '/registrar/visits', icon: 'visits', keywords: ['campus visit', 'appointment', 'tour'] },
  { label: 'Reschedules', href: '/registrar/reschedules', icon: 'reschedules', keywords: ['reschedule', 'rebook', 'move visit'] },
  { label: 'Documents', href: '/registrar/documents', icon: 'documents', keywords: ['docs', 'requirements', 'files'] },
  { label: 'Schedules', href: '/registrar/schedules', icon: 'schedules', keywords: ['sections', 'classes', 'timetable'] },
  { label: 'Slips', href: '/registrar/slips', icon: 'slips', keywords: ['assessment slip', 'fees', 'tuition'] },
  { label: 'COR', href: '/registrar/cors', icon: 'cor', keywords: ['certificate of registration', 'registration'] },
  { label: 'Sections', href: '/registrar/sections', icon: 'sections', keywords: ['who has cor', 'who has slip', 'issued', 'class list'] },
  { label: 'Grades', href: '/registrar/grades', icon: 'grades', keywords: ['grade changes', 'marks', 'incomplete', 'inc'] },
];

// One link per area, because each area has its own page. Admin and the Dean edit; the Registrar and
// the Secretary only read.
const PREREQUISITE_KEYWORDS = ['prerequisite', 'required subject', 'requires', 'curriculum', 'credit', 'transferee'];
function prerequisitesItem(href: string): NavItem {
  return { label: 'Prerequisites', href, icon: 'prerequisites', keywords: PREREQUISITE_KEYWORDS };
}

const SECRETARY_SCHEDULES: NavItem = {
  label: 'Schedules',
  href: '/secretary/schedule',
  icon: 'schedules',
  keywords: ['sections', 'classes', 'timetable'],
};
const DEAN_GRADES: NavItem = {
  label: 'Grades',
  href: '/dean/grades',
  icon: 'grades',
  keywords: ['approve grades', 'grade changes', 'marks'],
};
const PROFESSOR_GRADES: NavItem = {
  label: 'Grades',
  href: '/professor/grades',
  icon: 'grades',
  keywords: ['enter grades', 'submit grades', 'marks', 'incomplete', 'inc'],
};
const FINANCE_PAYMENTS: NavItem = {
  label: 'Payments',
  href: '/finance/payments',
  icon: 'payments',
  keywords: ['pay', 'tuition', 'fees', 'billing'],
};

export function navFor(role: Role): NavGroup[] {
  switch (role) {
    case 'registrar':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/registrar', icon: 'home', exact: true },
            ...REGISTRAR,
            prerequisitesItem('/registrar/prerequisites'),
          ],
        },
      ];
    case 'finance':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/finance', icon: 'home', exact: true },
            { label: 'Payments', href: '/finance/payments', icon: 'payments', keywords: ['pay', 'tuition', 'fees', 'billing'] },
          ],
        },
      ];
    case 'dean':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/dean', icon: 'home', exact: true },
            { label: 'Schedules', href: '/secretary/schedule', icon: 'schedules', keywords: ['sections', 'classes', 'timetable'] },
            { label: 'Sections', href: '/secretary/sections', icon: 'sections', keywords: ['who has cor', 'who has slip', 'issued', 'class list'] },
            DEAN_GRADES,
            prerequisitesItem('/dean/prerequisites'),
          ],
        },
      ];
    case 'college_secretary':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/secretary', icon: 'home', exact: true },
            { label: 'Schedules', href: '/secretary/schedule', icon: 'schedules', keywords: ['sections', 'classes', 'timetable'] },
            { label: 'Sections', href: '/secretary/sections', icon: 'sections', keywords: ['who has cor', 'who has slip', 'issued', 'class list'] },
            prerequisitesItem('/secretary/prerequisites'),
          ],
        },
      ];
    case 'professor':
      return [{ label: null, items: [{ label: 'Home', href: '/professor', icon: 'home', exact: true }, PROFESSOR_GRADES] }];
    case 'admin':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/admin', icon: 'home', exact: true },
            { label: 'Accounts', href: '/admin/accounts', icon: 'accounts', keywords: ['users', 'staff accounts', 'people'] },
            { label: 'Content', href: '/admin/content', icon: 'content', keywords: ['subjects', 'rooms', 'programs', 'grading scale', 'grade bands'] },
            prerequisitesItem('/admin/prerequisites'),
            { label: 'Admissions', href: '/admin/admissions', icon: 'admissions', keywords: ['intake', 'applicants', 'enroll'] },
            { label: 'Audit log', href: '/admin/audit', icon: 'audit', keywords: ['history', 'activity log'] },
          ],
        },
        {
          label: null,
          items: [
            { label: 'Registrar', href: '/registrar', icon: 'registrar', keywords: ['visits', 'documents', 'cor', 'slips'], children: REGISTRAR },
            { label: 'Finance', href: '/finance', icon: 'finance', keywords: ['payments', 'billing', 'tuition'], children: [FINANCE_PAYMENTS] },
            { label: 'Dean', href: '/dean', icon: 'dean', keywords: ['college', 'approval'], children: [DEAN_GRADES] },
            { label: 'College Secretary', href: '/secretary', icon: 'secretary', keywords: ['secretary', 'college', 'schedules'], children: [SECRETARY_SCHEDULES] },
            { label: 'Professor', href: '/professor', icon: 'professor', keywords: ['faculty', 'teacher', 'instructor'], children: [PROFESSOR_GRADES] },
          ],
        },
      ];
    default:
      return [];
  }
}

export const SIDEBAR_COOKIE = 'plp_sidebar';

export function isActive(pathname: string, item: NavItem): boolean {
  if (item.exact) return pathname === item.href;
  return pathname === item.href || pathname.startsWith(`${item.href}/`);
}

// Flat list of every item the current user's nav exposes, for the top-bar
// search: only areas the signed-in user is actually recommended/allowed to
// open (the same groups rendered in the sidebar), never the full site map.
export function flattenNav(nav: NavGroup[]): NavItem[] {
  return nav.flatMap((group) => group.items.flatMap((item) => [item, ...(item.children ?? [])]));
}
