# Jaago Mohan

*Jaago Mohan Pyaare.* A website that keeps your laptop awake, keeps your Slack/Teams status green, and plays fake keyboard typing sounds.

| Feature | How it works |
|---|---|
| **Stay Awake** | Uses the Screen Wake Lock API in the browser. It only works while the tab is visible, and the page takes the lock again when you come back to the tab. |
| **Stay Active** | Websites can't fake keyboard or mouse input, so a small Windows tray helper ([`helper/`](helper/)) does it. Once you've been idle for 60s, it sends an F15 keypress and a zero-pixel mouse move. The page controls the helper through `http://localhost:47474`. |
| **Keyboard Sound** | Typing sounds generated with Web Audio, at about 70 wpm in bursts with gaps between them. There are no audio files. |

The whole site is one file, [`index.html`](index.html), with no build step.

## Helper API

The helper listens on `http://localhost:47474` and only answers sites in its origin allowlist (`AllowedOrigins` in [`JaagoMohan.ps1`](helper/JaagoMohan.ps1)). **Add the custom domain there once it's live**, then rebuild the zip.

- `GET /status` returns `{ active, idleMs, nudges }`
- `POST /active/on` and `POST /active/off`

## Rebuilding the helper download

```powershell
Compress-Archive -Force -Path helper\JaagoMohan.ps1, "helper\Start Jaago Mohan.cmd" -DestinationPath downloads\jaago-mohan-helper.zip
```
