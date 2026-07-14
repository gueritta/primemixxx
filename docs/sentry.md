# Sentry Telemetry & Data Redirection

This document covers how the Denon Prime Go (and other Engine OS devices) uses **Sentry** for crash reporting and telemetry, and how to redirect or disable this tracking.

## Hardcoded Sentry Endpoints

Analysis of the `usr/Engine/Engine` binary revealed three hardcoded Sentry DSN (Data Source Name) URLs used to upload crash reports and telemetry data to inMusic's Sentry accounts:

1. `https://56d5dbf7dc264b6892b936f7a1be21bc@o230257.ingest.sentry.io/1388643`
2. `https://36ed0ada58dc4840953dd3d06c811c44@o230257.ingest.sentry.io/5608362`
3. `https://45cfde58e99249f79c5973bc263d691b@o230257.ingest.sentry.io/6661444`

These endpoints receive minidump crash reports, logs, and system environment info when an application crash occurs or during boot.

---

## Interception and Redirection Methods

If you wish to host your own Sentry instance or log server to capture these diagnostic files yourself, use one of the following methods.

### Method 1: Local DNS Redirection (`/etc/hosts`)

Since the endpoints target `o230257.ingest.sentry.io`, you can redirect all traffic to a custom server IP on the local network.

1. SSH into the device and add the redirect to `/etc/hosts`:
   ```bash
   echo "<YOUR_SERVER_IP> o230257.ingest.sentry.io" >> /etc/hosts
   ```
2. Configure a reverse proxy (e.g., Nginx) on your server with a wildcard TLS certificate listening on port 443 to receive and log the incoming HTTPS payloads.

---

### Method 2: Environment Variable Override (`SENTRY_DSN`)

The embedded `sentry-native` client will honor standard environment overrides. Setting `SENTRY_DSN` will supersede the compiled URLs.

1. Edit the Engine startup script `/usr/Engine/Scripts/runengine`.
2. Inject your target DSN endpoint:
   ```bash
   export SENTRY_DSN="https://<your-key>@<your-own-sentry-host>/<project-id>"
   ```

---

### Method 3: Disabling Sentry / GDPr Privacy Mode

If you simply want to block the outbound data transfer entirely:

1. Map the Sentry domain to localhost (`127.0.0.1` or `0.0.0.0`) in `/etc/hosts`:
   ```bash
   echo "127.0.0.1 o230257.ingest.sentry.io" >> /etc/hosts
   ```
