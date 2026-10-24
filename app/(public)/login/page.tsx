import { Container, Text, Title } from '@mantine/core';

// Placeholder. The real sign-in form arrives in build step 4 (auth and roles).
export default function LoginPage() {
  return (
    <Container size="xs" py="xl">
      <Title order={2}>PLP Enrollment</Title>
      <Text c="dimmed">Sign in is coming soon.</Text>
    </Container>
  );
}
