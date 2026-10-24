import { PortalShell } from '@/components/PortalShell';

// Authenticated shell. Auth checks are added in build step 4.
export default function PortalLayout({ children }: { children: React.ReactNode }) {
  return <PortalShell>{children}</PortalShell>;
}
