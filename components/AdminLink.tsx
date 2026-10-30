// A link to an Admin-only page. Admin gets the link; everyone else cannot open
// that page, so they are told to contact an Admin instead of seeing a dead end.
import Link from 'next/link';
import { Anchor } from '@mantine/core';
import type { Role } from '@/lib/auth/roles';

export function AdminLink({
  viewerRole,
  href,
  label,
  contact = 'Contact an Admin.',
}: {
  viewerRole: Role;
  href: string;
  label: string; // the link text Admin sees
  contact?: string; // what everyone else sees
}) {
  if (viewerRole === 'admin') {
    return (
      <Anchor component={Link} href={href} inherit>
        {label}
      </Anchor>
    );
  }
  return <>{contact}</>;
}
