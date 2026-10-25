'use client';

// components/PageHeading.tsx
//
// Shared page heading for subpages: "Previous Page > Current Page", the
// ancestor clickable. Ported from plp-admissions's page_header.php /
// AdminPageHeader pattern: small muted ancestor links that underline on
// hover, a caret-right separator, and the current page at full heading size.
//
// Usage: a top-level page (e.g. /registrar) renders just a <Title>, same as
// before. A subpage (e.g. /registrar/visits) renders <PageHeading title="Visits"
// parent={{ label: 'Registrar', href: '/registrar' }} /> instead.
import Link from 'next/link';
import { ChevronRightIcon } from '@heroicons/react/24/outline';
import { Group, Title } from '@mantine/core';
import { color, fontSize, fontWeight, layout, spacing } from '@/styles/tokens';

export type PageCrumb = { label: string; href: string };

export function PageHeading({
  title,
  parent,
  parents,
}: {
  title: string;
  // One ancestor ("Previous page"), or several for a deeper trail. Each is
  // clickable; the current page (title) is never itself a link.
  parent?: PageCrumb;
  parents?: PageCrumb[];
}) {
  const trail = parents ?? (parent ? [parent] : []);

  if (trail.length === 0) {
    return <Title order={3}>{title}</Title>;
  }

  return (
    <Group gap={spacing.xs} wrap="wrap" aria-label="Breadcrumb" component="nav">
      {trail.map((crumb) => (
        <Group key={crumb.href} gap={spacing.xs} wrap="nowrap">
          <Link
            href={crumb.href}
            style={{
              fontSize: fontSize.md,
              fontWeight: fontWeight.semibold,
              color: color.textSecondary,
              textDecoration: 'none',
            }}
            className="plp-breadcrumb-link"
          >
            {crumb.label}
          </Link>
          <ChevronRightIcon width={layout.iconSize - 6} height={layout.iconSize - 6} color={color.textSecondary} />
        </Group>
      ))}
      <Title order={3} aria-current="page">
        {title}
      </Title>
    </Group>
  );
}
