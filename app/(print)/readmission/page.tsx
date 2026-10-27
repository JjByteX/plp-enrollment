import { Anchor, Container, Group, Stack, Text } from '@mantine/core';
import { requireArea } from '@/lib/auth/session';
import { getMyReadmission } from '@/features/leave-of-absence/queries';
import { ReadmissionView } from '@/features/leave-of-absence/ReadmissionView';
import { PrintButton } from '@/features/assessment-slip/PrintButton';
import { color, spacing } from '@/styles/tokens';

export const metadata = { title: 'Readmission slip | PLP Enrollment' };

// The returning student's own readmission slip on a page without the portal shell, so printing it
// or saving it as a PDF gives the slip alone.
export default async function ReadmissionPage() {
  await requireArea('student');
  const slip = await getMyReadmission();

  return (
    <Container size="md" py={spacing.xl}>
      <Stack gap={spacing.md}>
        <Group justify="space-between" className="no-print">
          <Anchor href="/student">Back</Anchor>
          {slip && <PrintButton />}
        </Group>
        {slip ? (
          <ReadmissionView slip={slip} />
        ) : (
          <Text c={color.textSecondary}>You have no readmission slip.</Text>
        )}
      </Stack>
    </Container>
  );
}
