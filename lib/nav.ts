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
  | 'home' | 'visits' | 'reschedules' | 'documents' | 'schedules' | 'slips' | 'cor' | 'payments'
  | 'accounts' | 'content' | 'admissions' | 'audit' | 'registrar' | 'finance' | 'dean' | 'secretary' | 'professor';

export type NavItem = { label: string; href: string; icon: NavIconName; exact?: boolean };
export type NavGroup = { label: string | null; items: NavItem[] };

const REGISTRAR: NavItem[] = [
  { label: 'Visits', href: '/registrar/visits', icon: 'visits' },
  { label: 'Reschedules', href: '/registrar/reschedules', icon: 'reschedules' },
  { label: 'Documents', href: '/registrar/documents', icon: 'documents' },
  { label: 'Schedules', href: '/registrar/schedules', icon: 'schedules' },
  { label: 'Slips', href: '/registrar/slips', icon: 'slips' },
  { label: 'COR', href: '/registrar/cors', icon: 'cor' },
];

export function navFor(role: Role): NavGroup[] {
  switch (role) {
    case 'registrar':
      return [{ label: null, items: [{ label: 'Home', href: '/registrar', icon: 'home', exact: true }, ...REGISTRAR] }];
    case 'finance':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/finance', icon: 'home', exact: true },
            { label: 'Payments', href: '/finance/payments', icon: 'payments' },
          ],
        },
      ];
    case 'dean':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/dean', icon: 'home', exact: true },
            { label: 'Schedules', href: '/secretary/schedule', icon: 'schedules' },
          ],
        },
      ];
    case 'college_secretary':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/secretary', icon: 'home', exact: true },
            { label: 'Schedules', href: '/secretary/schedule', icon: 'schedules' },
          ],
        },
      ];
    case 'professor':
      return [{ label: null, items: [{ label: 'Home', href: '/professor', icon: 'home', exact: true }] }];
    case 'admin':
      return [
        {
          label: null,
          items: [
            { label: 'Home', href: '/admin', icon: 'home', exact: true },
            { label: 'Accounts', href: '/admin/accounts', icon: 'accounts' },
            { label: 'Content', href: '/admin/content', icon: 'content' },
            { label: 'Admissions', href: '/admin/admissions', icon: 'admissions' },
            { label: 'Audit log', href: '/admin/audit', icon: 'audit' },
          ],
        },
        {
          label: 'Staff areas',
          items: [
            { label: 'Registrar', href: '/registrar', icon: 'registrar' },
            { label: 'Finance', href: '/finance', icon: 'finance' },
            { label: 'Dean', href: '/dean', icon: 'dean' },
            { label: 'College Secretary', href: '/secretary', icon: 'secretary' },
            { label: 'Professor', href: '/professor', icon: 'professor' },
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
