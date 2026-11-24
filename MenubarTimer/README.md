# Tact

Open Tact.app and look for the timer icon in the macOS menu bar.

- Drag straight down from the icon. The preview shows a duration from 0 to 60 minutes in one-minute steps. Release at 1–60 minutes to start. Return to 0 or press Escape to cancel the gesture.
- After releasing a drag, use Learn, Work, or Break to apply a name, icon, and colour while the timer runs. You can also enter a custom name or use the colour dot. The card closes after four seconds when idle.
- Open the timer panel’s … menu and choose Manage Presets to create or edit presets and choose up to three for the quick card.
- Click the icon to open the timer panel. Enter an optional name, choose a color, set the duration, and click Start.
- Use the pencil beside a running timer to rename or recolor it, including timers created by dragging. Use the × to cancel a running timer or dismiss a finished one. Each timer has its own countdown and progress bar.
- The macOS menu bar shows each running timer’s coloured icon, ordered by when it finishes. As space fills, the soonest timers keep their countdowns and later timers use compact icons. A +N badge counts timers beyond the available display space. Click anywhere on the status item to see every countdown, or drag down to start another timer. Timer completion plays the system alert sound. Click the icon to dismiss completed timers.
- Active timers use absolute deadlines, so they catch up after sleep or when you reopen the app. Haptic feedback depends on the trackpad and system settings.

To rebuild on a Mac with the Swift command-line tools installed, run `./build.sh` from the `source` folder. The app is built under `build/`.

## Trackers and desktop cards

Click the menu bar icon, then choose **Trackers → New tracker**. Create a countdown to a date, a recurring event, a time-since tracker with optional milestone days, or a date range with percentage progress. Recurring trackers support working-day rules and one-off date overrides.

Choose from 32 palettes or enter a custom hex accent. You can select a symbol, tint the card, and preview light and dark appearances. **Pin to Desktop** creates a draggable card managed by Tact. The card and its position are restored when the app launches again.

Use **Reminders** to enable a quiet macOS notification on a tracker’s event or milestone day.
