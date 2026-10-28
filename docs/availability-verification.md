# Availability verification

Run `swift test` for status parsing, expiration, invalid readings, error backoff,
uncertain requests, and explicit Apple errors inside a successful HTTP response.

For native tests without Apple or real sound requests, prepare a separate project:

```sh
python3 scripts/prepare-availability-qa.py /absolute/new/qa-folder
```

Build its `FindMyRing` scheme. Use the normal app-build workflow to sign and
install **Beckon QA**, keeping its separate bundle IDs and shared group. Do not
install the QA app over Beckon. Development signing may require profiles for
restricted identifier/Keychain entitlements; this QA build never needs Keychain
credentials. Do not weaken the normal app's entitlements to sign a test build.

`BECKON_QA` compiles fictional device and receipt handling into both the app and
widget. The normal build compiles those handlers out. The simulator window
changes Test iPhone among Online, Offline, and Needs refresh. Verify the actual
app's Ring control disables and recovers, then add its Ring desktop widget and
repeat. Use the widget's refresh arrow with the containing app closed, and click
Ring when online. The QA shared container records `qa-ring-receipt.txt` and a
history event whose source must be `Widget`. A Window receipt does not verify a
widget click. Preserve the user's existing widgets and remove test widgets after.

Also inspect the small/medium widget sizes and dimmed desktop appearance. Use a
future timeline entry to expire availability; don't rewrite a reading's timestamp
when reloading it. App polling frequency is distinct from visible redraw timing.

A normal signed build accepts `--status-probe` for a bounded read-only check using
that account's existing saved sign-in. It writes eight aggregate samples to
`~/Library/Logs/Beckon-status-probe.json` and exits. It never rings devices and
never logs account names, device IDs, passwords, locations, or raw responses.
Run through the normal application launch route. A passing burst does not prove
long-term polling behavior or device-transition latency. Verify real transitions
only with a controlled device and the user's participation.
