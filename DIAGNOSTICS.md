# Runtime diagnostics

Cruor Sable Compat writes diagnostic messages to Minecraft's normal log. It does not create a separate log file, upload logs, or send any data anywhere.

## What is recorded

The mod uses the normal INFO and WARN log levels and avoids per-tick logging:

- Mod initialization and whether the required Sable Ragdolls mod was detected.
- The first positive server-side damage event, confirming that bleeding tracking received damage.
- The first time each Sable ragdoll part class reaches the compatibility physics hook.
- One-time warnings when a Sable source UUID or logical pose cannot be resolved.
- One-time warnings, including a stack trace, when the pose transform method fails.
- Confirmation when the first compatibility blood particle is emitted.

Repeated identical warnings are suppressed for the rest of the game session to keep `latest.log` readable.

## How to send a log

1. Start Minecraft with Cruor Sable Compat, Sable Ragdolls and the required dependencies enabled.
2. Reproduce the problem. For example, enter a world, cause damage, and reproduce the ragdoll situation where the compatibility effect should appear.
3. Close Minecraft normally.
4. In Prism Launcher, right-click the Minecraft instance and choose **Folder**.
5. Open `.minecraft/logs/latest.log` and attach that file to the conversation.

If Minecraft crashed, also attach the newest relevant file from `.minecraft/crash-reports/`.

For a dedicated server, the server's `logs/latest.log` may be needed as well. For a single-player test, start with the client instance's `latest.log`.

## What to include with the log

In the message, briefly state:
- what you expected to happen;
- what actually happened;
- the steps that reproduce it;
- whether the test was single-player or on a server.

Logs can contain local file paths, Windows account names, server addresses, and other mod information. Review the file before sharing it and redact details you do not want to disclose. Never send launcher account files, access tokens, or passwords.

The logger only writes locally through Minecraft's logging system. There is no automatic upload or GitHub authentication.
