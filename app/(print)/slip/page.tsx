import { Anchor, Container, Group, Stack, Text } from '@mantine/core';
import { requireArea } from '@/lib/auth/session';
import { getMySlip } from '@/features/assessment-slip/queries';
import { SlipView } from '@/features/assessment-slip/SlipView';
import { PrintButton } from '@/features/assessment-slip/PrintButton';
import { color, spacing } from '@/styles/tokens';

export const metadata = { title: 'Assessment slip | PLP Enrollment' };

// The student's own slip on a page without the portal shell, so printing it or
// saving it as a PDF gives the slip alone.
export default async function SlipPage() {
  await requireArea('student');
  const slip = await getMySlip();

  return (
    <Container size="md" py={spacing.xl}>
      <Stack gap={spacing.md}>
        <Group justify="space-between" className="no-print">
          <Anchor href="/student">Back</Anchor>
          {slip && <PrintButton />}
        </Group>
        {slip ? (
          <SlipView slip={slip} />
        ) : (
          <Text c={color.textSecondary}>Your assessment slip has not been issued yet.</Text>
        )}
      </Stack>
    </Container>
  );
}
