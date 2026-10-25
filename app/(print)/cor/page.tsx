import { Anchor, Container, Group, Stack, Text } from '@mantine/core';
import { requireArea } from '@/lib/auth/session';
import { getMyCor } from '@/features/cor/queries';
import { CorView } from '@/features/cor/CorView';
import { PrintButton } from '@/features/assessment-slip/PrintButton';
import { color, spacing } from '@/styles/tokens';

export const metadata = { title: 'Certificate of registration | PLP Enrollment' };

// The student's own COR on a page without the portal shell, so printing it or
// saving it as a PDF gives the COR alone.
export default async function CorPage() {
  await requireArea('student');
  const cor = await getMyCor();

  return (
    <Container size="md" py={spacing.xl}>
      <Stack gap={spacing.md}>
        <Group justify="space-between" className="no-print">
          <Anchor href="/student">Back</Anchor>
          {cor && <PrintButton />}
        </Group>
        {cor ? (
          <CorView cor={cor} />
        ) : (
          <Text c={color.textSecondary}>Your certificate of registration has not been issued yet.</Text>
        )}
      </Stack>
    </Container>
  );
}
