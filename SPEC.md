# ThermalThrottleWatch — specification

**Tagline:** See your Mac's thermal pressure and sensor temperatures in the menu bar and get warned before it throttles.

**Category:** System Monitoring

**Inspired by (paid):** TG Pro ($10 one-time)

**Frameworks:** SwiftUI, AppKit, IOKit, UserNotifications, Foundation

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: TG Pro from Tunabelly Software shows temperatures from many sensors in the menu bar, offers fan control and alerts, and keeps a history so you can see when your Mac got hot. It is sold as a one time licence listed at 10 dollars on sale and 20 dollars at list price. It has a Macworld Mac Gems review and is recommended in several fan control roundups and forum threads such as the long running MacRumors thread about stopping a burning lap, which is solid evidence of demand. Our clean-room version is read only and avoids fan writes, which would need privileged access. It focuses on knowing when your Mac is under thermal stress.

Feature set for our version: a menu bar readout with the system thermal state (Nominal, Fair, Serious, Critical) shown as a colored dot, plus an optional hottest sensor temperature. A popover lists the available temperature sensors such as CPU, GPU, battery and SSD, each with a current value and the highest value since launch. A 30 minute sparkline for the hottest sensor shows trends. A notification fires when the thermal state reaches Serious or when the hottest sensor exceeds a limit set by the user, and another when it recovers. A log of throttle events with start time and duration is kept for the last 14 days. Roughly 450 lines of Swift.

UI spec: a MenuBarExtra with window style. The label is a thermometer symbol and a number, with color changes by state. The popover has a header showing thermal state in words, a sensor list, the sparkline drawn with a SwiftUI Path, an events section with a Clear button, and footer buttons for Settings and Quit. Settings has a temperature unit picker, an alert threshold slider from 60 to 105 degrees Celsius, toggles for notifications, an option to show the number in the menu bar, a refresh interval picker of 2, 5, or 10 seconds, and launch at login. Empty state: if no sensors can be read, the list says that only the system thermal state is available on this Mac and still shows that state.

Technical approach: the public ProcessInfo thermalState property and the thermalStateDidChangeNotification give the reliable baseline. For temperatures, open the AppleSMC service through IOKit with IOServiceOpen and call the structure method selector to read four character keys, decoding the floating point and fixed point types. Keep a small table of known temperature keys for Intel and for common Apple Silicon generations, probe each key at startup, and only show the keys that return plausible values between 10 and 120 degrees. Battery temperature is also available from the AppleSmartBattery entry as a second source. Persist settings with AppStorage and events in Application Support as JSON. Use UserNotifications for alerts. Launch at login uses SMAppService. No Accessibility or Screen Recording permission is needed, and the SMC reads work only in a non sandboxed build, which the README should state.

Edge cases: unknown keys on new chips must fail silently without crashing, so every read checks the return code and size. Smooth readings with a short moving average to avoid flapping alerts. Add hysteresis of three degrees before sending a recovery notice. Do not notify more than once every five minutes for the same condition. If the SMC connection fails, fall back to thermal state only and show a quiet banner explaining the limitation.
