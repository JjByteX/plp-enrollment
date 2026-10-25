// components/NavIcons.tsx
//
// Which Heroicons icon each sidebar link uses (ux-ui-guidelines.md, icon rules:
// one library, the same icon for the same concept everywhere). Library:
// @heroicons/react, 24 outline (line) set. Placement: left of the label; alone,
// with a tooltip, when the sidebar is collapsed.
import type { ComponentType, SVGProps } from 'react';
import {
  AcademicCapIcon,
  ArrowPathIcon,
  BanknotesIcon,
  BookOpenIcon,
  BuildingLibraryIcon,
  CalendarDaysIcon,
  ClockIcon,
  CreditCardIcon,
  DocumentCheckIcon,
  DocumentTextIcon,
  HomeIcon,
  IdentificationIcon,
  InboxArrowDownIcon,
  MapPinIcon,
  TicketIcon,
  UserIcon,
  UsersIcon,
} from '@heroicons/react/24/outline';
import type { NavIconName } from '@/lib/nav';

export const NAV_ICONS: Record<NavIconName, ComponentType<SVGProps<SVGSVGElement>>> = {
  home: HomeIcon, // house: Home
  visits: MapPinIcon, // map pin: Visits
  reschedules: ArrowPathIcon, // circular arrows: Reschedules
  documents: DocumentTextIcon, // page with lines: Documents
  schedules: CalendarDaysIcon, // calendar: Schedules
  slips: TicketIcon, // ticket: Slips
  cor: DocumentCheckIcon, // page with check: COR
  payments: CreditCardIcon, // card: Payments
  accounts: UsersIcon, // people: Accounts
  content: BookOpenIcon, // open book: Content
  admissions: InboxArrowDownIcon, // inbox with arrow: Admissions
  audit: ClockIcon, // clock: Audit log
  registrar: IdentificationIcon, // ID card: Registrar
  finance: BanknotesIcon, // banknotes: Finance
  dean: AcademicCapIcon, // graduation cap: Dean
  secretary: BuildingLibraryIcon, // college building: College Secretary
  professor: UserIcon, // person: Professor
};
