/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: {
    // Keep visited pages in the browser for a short while so going back and
    // forth between pages is instant instead of waiting on Supabase again.
    // Saving something (server actions) still clears it, so data is not stale.
    staleTimes: { dynamic: 30, static: 180 },
    optimizePackageImports: ['@mantine/core', '@mantine/hooks', '@mantine/dates', '@mantine/notifications'],
  },
};

export default nextConfig;
