# Security policy

## Supported versions

Only the latest release gets security fixes.

## Report a vulnerability

Don't open a public issue. Report it privately through [GitHub's vulnerability reporting](https://github.com/firatciftci/fullstop/security/advisories/new).

Include the Fullstop and macOS versions, what you found, and the steps to reproduce it. You'll get a reply within a week. Once a fix ships, we publish the advisory and credit you, unless you'd rather stay anonymous.

## The helper

Fullstop's helper runs as root, so we give issues in it priority. It accepts XPC connections only from the Fullstop app signed by the same team. It can only change the charge limit, connect or disconnect the power adapter, set the MagSafe light, and set the Energy Mode. If you find a way to make it do anything else, or to reach it from another app, report it.
