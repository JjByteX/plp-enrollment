'use client';

// features/settings/SettingsModal.tsx
//
// Opened from the profile menu. Two controls: a font size slider (scales the
// whole app, since Mantine sizes are rem-based) and a theme switch
// (Light / Dark / Match device). Both apply immediately and persist.
import { ComputerDesktopIcon, MoonIcon, SunIcon } from '@heroicons/react/24/outline';
import { Divider, Group, Modal, SegmentedControl, Slider, Stack, Text } from '@mantine/core';
import { color, fontWeight, layout, padding, spacing } from '@/styles/tokens';
import { FONT_SCALE_MARKS, FONT_SCALE_MAX, FONT_SCALE_MIN, FONT_SCALE_STEP, useSettings } from './SettingsContext';

function iconProps() {
  return { width: layout.iconSize, height: layout.iconSize };
}

export function SettingsModal({ onClose }: { onClose: () => void }) {
  const { fontScale, setFontScale, colorScheme, setColorScheme } = useSettings();

  return (
    <Modal opened onClose={onClose} title="Settings" padding={padding.modal} radius="lg" size="sm">
      <Stack gap={spacing.lg}>
        <Stack gap={spacing.sm}>
          <Text fw={fontWeight.semibold}>Font size</Text>
          <Text size="sm" c={color.textSecondary}>
            Adjusts text size across the whole app.
          </Text>
          <Slider
            value={fontScale}
            onChange={setFontScale}
            min={FONT_SCALE_MIN}
            max={FONT_SCALE_MAX}
            step={FONT_SCALE_STEP}
            label={(value) => `${Math.round(value * 100)}%`}
            marks={FONT_SCALE_MARKS}
            color="green"
            mb={spacing.lg}
          />
        </Stack>

        <Divider />

        <Stack gap={spacing.sm}>
          <Text fw={fontWeight.semibold}>Theme</Text>
          <Text size="sm" c={color.textSecondary}>
            Choose how PLP Enrollment looks on this device.
          </Text>
          <SegmentedControl
            fullWidth
            value={colorScheme}
            onChange={(value) => setColorScheme(value as typeof colorScheme)}
            color="green"
            data={[
              {
                value: 'light',
                label: (
                  <Group gap={spacing.xs} justify="center" wrap="nowrap">
                    <SunIcon {...iconProps()} />
                    <span>Light</span>
                  </Group>
                ),
              },
              {
                value: 'dark',
                label: (
                  <Group gap={spacing.xs} justify="center" wrap="nowrap">
                    <MoonIcon {...iconProps()} />
                    <span>Dark</span>
                  </Group>
                ),
              },
              {
                value: 'auto',
                label: (
                  <Group gap={spacing.xs} justify="center" wrap="nowrap">
                    <ComputerDesktopIcon {...iconProps()} />
                    <span>Auto</span>
                  </Group>
                ),
              },
            ]}
          />
        </Stack>
      </Stack>
    </Modal>
  );
}
