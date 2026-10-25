import { redirect } from 'next/navigation';
import Image from 'next/image';
import { Box, Paper, Stack, Text, Title } from '@mantine/core';
import { getCurrentUser } from '@/lib/auth/session';
import { homePath } from '@/lib/auth/roles';
import { color, fontSize, gray, green, padding, radius, spacing } from '@/styles/tokens';
import { LoginForm } from './LoginForm';

export const metadata = { title: 'Sign in | PLP Enrollment' };

const LOGO_SIZE = 80;
const CARD_WIDTH = 420;
// The blur pulls the edges in, so the photo is scaled up a little to hide them.
const PHOTO_BLUR = 14;
const PHOTO_SCALE = 1.12;
const TINT_OPACITY = 0.55;

export default async function LoginPage() {
  const user = await getCurrentUser();
  if (user) redirect(homePath(user.role));

  return (
    <Box
      component="main"
      pos="relative"
      mih="100dvh"
      bg={gray[1000]}
      style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}
    >
      {/* Campus photo, gaussian blurred */}
      <Box
        aria-hidden
        pos="absolute"
        style={{
          inset: 0,
          backgroundImage: 'url(/login-bg.jpg)',
          backgroundSize: 'cover',
          backgroundPosition: 'center',
          filter: `blur(${PHOTO_BLUR}px)`,
          transform: `scale(${PHOTO_SCALE})`,
        }}
      />
      {/* Blue tint so the white text stays readable on any photo */}
      <Box aria-hidden pos="absolute" bg={green[8]} style={{ inset: 0, opacity: TINT_OPACITY }} />

      <Stack
        gap={spacing.lg}
        align="center"
        w="100%"
        maw={CARD_WIDTH}
        px={spacing.md}
        py={spacing['4xl']}
        pos="relative"
      >
        <Stack gap={spacing.sm} align="center">
          <Box bg={color.surfacePage} p={spacing.sm} style={{ display: 'flex', borderRadius: radius.prominent }}>
            <Image src="/plp-logo.png" alt="PLP seal" width={LOGO_SIZE} height={LOGO_SIZE} priority />
          </Box>
          <Title order={1} fz={fontSize.lg} c={color.textOnAccent} ta="center">
            PLP Enrollment
          </Title>
          <Text size="sm" c={gray[100]} ta="center">
            Pamantasan ng Lungsod ng Pasig
          </Text>
        </Stack>

        <Paper p={padding.card} radius={radius.prominent} w="100%">
          <Stack gap={spacing.md}>
            <Stack gap={spacing.xs}>
              <Title order={2} fz={fontSize.lg}>
                Sign in
              </Title>
              <Text c="dimmed" size="sm">
                Use the account the school gave you.
              </Text>
            </Stack>
            <LoginForm />
          </Stack>
        </Paper>

        <Text size="sm" c={gray[200]} ta="center">
          Enrollment for newly admitted students
        </Text>
      </Stack>
    </Box>
  );
}
