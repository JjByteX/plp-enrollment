import { Skeleton, Stack } from '@mantine/core';

// Shown the moment a link is clicked, while the next page loads from the
// database. Next also uses it to prefetch pages, so most links open at once.
export default function PortalLoading() {
  return (
    <Stack gap="lg" aria-busy="true" aria-label="Loading">
      <Skeleton height={28} width="30%" radius="sm" />
      <Skeleton height={14} width="50%" radius="sm" />
      <Skeleton height={160} radius="sm" />
      <Skeleton height={240} radius="sm" />
    </Stack>
  );
}
