# Glass Test Lab reference

This directory is a clean source snapshot of the isolated Flutter Glass Test
Lab used on the same Android device as niraNG.

- `lib/main.dart`: latest test-lab implementation.
- `approved_checkpoint/lib/main.dart`: the visually approved checkpoint from
  2026-09-16.
- `packages/liquid_glass_renderer/`: the exact vendored renderer used by the
  test lab.

Compare these files with niraNG:

- `lib/core/widgets/glass_surface.dart`
- `lib/core/widgets/glass_dialog.dart`
- `lib/features/servers/servers_screen.dart`
- `lib/features/vpn/app_shell.dart`
- `packages/liquid_glass_renderer/`

The reported niraNG defect is not merely blur strength. On real-device output,
a single Home card can show different rendering regions separated by visible
horizontal/vertical seams, and the Servers top menu can leave some backdrop
text sharp while another region is blurred. The test lab does not show those
coverage seams with its approved layout.

Generated build products, `.dart_tool`, IDE files, Android `local.properties`,
and device-specific files are intentionally excluded.
