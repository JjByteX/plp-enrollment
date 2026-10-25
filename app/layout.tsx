// app/layout.tsx
import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';
import '@/styles/global.css';
import { ColorSchemeScript, MantineProvider } from '@mantine/core';
import { Notifications } from '@mantine/notifications';
import { Manrope, Plus_Jakarta_Sans } from 'next/font/google';
import { theme } from '@/styles/theme';

// Fonts per the human's decision: Manrope for headings, Plus Jakarta Sans
// for body text. next/font self-hosts these at build time (no external
// stylesheet calls at runtime).
const manrope = Manrope({
  subsets: ['latin'],
  weight: ['400', '600'],
  variable: '--font-heading',
  display: 'swap',
});

const plusJakartaSans = Plus_Jakarta_Sans({
  subsets: ['latin'],
  weight: ['400', '600'],
  variable: '--font-body',
  display: 'swap',
});

export const metadata = {
  title: 'PLP Enrollment',
  description: 'Enrollment system for newly admitted PLP students.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${manrope.variable} ${plusJakartaSans.variable}`} suppressHydrationWarning>
      <head>
        <ColorSchemeScript defaultColorScheme="light" />
      </head>
      <body>
        <MantineProvider theme={theme} defaultColorScheme="light">
          <Notifications position="top-right" />
          {children}
        </MantineProvider>
      </body>
    </html>
  );
}
