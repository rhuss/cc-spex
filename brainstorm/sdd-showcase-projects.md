# SDD Showcase CLI Projects

10 small CLI projects to demonstrate Spec-Driven Development. Each is designed to be completed in a single spec within one hour.

---

## 1. `ipmap` - IP Geolocation on ASCII World Map

**Kick-off prompt:**

> Create a Go CLI called `ipmap` that takes an IP address (or defaults to your public IP) and displays its geolocation on an ASCII world map in the terminal. Use ip-api.com (free, no key) to resolve IP to lat/lon/city/country. Render a simplified ASCII world map with ANSI colors and place a marker at the coordinates. Support `ipmap 8.8.8.8` and `ipmap` (shows your own location). Output should include city, country, ISP, and the map with the dot.

---

## 2. `git-roast` - Humorous GitHub Repo Analysis

**Kick-off prompt:**

> Create a Go CLI called `git-roast` that takes a GitHub repo (e.g., `git-roast kubernetes/kubernetes`) and generates a humorous "roast" based on real repo stats. Use the GitHub REST API (unauthenticated for public repos, optional GITHUB_TOKEN for higher rate limits). Collect: commit frequency patterns, top committers, language breakdown, open vs closed issues ratio, average PR merge time, largest files, and repo age. Generate witty one-liners for each stat category (e.g., "73% Go and 27% regret"). Colorize output with ANSI. No AI API needed, the humor comes from templates and thresholds.

---

## 3. `qr` - Terminal QR Code Generator

**Kick-off prompt:**

> Create a Go CLI called `qr` that generates QR codes rendered directly in the terminal using Unicode block characters (upper/lower half blocks for 2x density). Accept input as argument (`qr "https://example.com"`) or from stdin (`echo "hello" | qr`). Support `--invert` for light/dark terminal backgrounds and `--size` to control module size. The QR code must be scannable from the terminal with a phone camera. Use a pure Go QR encoding library (e.g., `skip2/go-qrcode` or similar), no external service calls.

---

## 4. `deps-age` - Dependency Freshness Checker

**Kick-off prompt:**

> Create a Go CLI called `deps-age` that reads dependency files (`package.json`, `go.mod`, or `requirements.txt`, auto-detected) and shows how outdated each dependency is. Query the appropriate registry API (npm registry, proxy.golang.org, PyPI JSON API) to get the latest version and its publish date. Display a color-coded table: green (<30 days), yellow (30-180 days), red (>180 days), with columns for name, current version, latest version, and age. Show a summary line with overall "freshness score" percentage. Support `deps-age` (auto-detect) or `deps-age --file go.mod`.

---

## 5. `tldr-url` - URL Summarizer

**Kick-off prompt:**

> Create a Go CLI called `tldr-url` that takes a URL, fetches the page content, extracts the main text (stripping nav, ads, boilerplate), and summarizes it into 3 bullet points using the Claude API. Use `ANTHROPIC_API_KEY` env var for auth. For HTML extraction, use a readability algorithm or simple heuristic (find the largest text block). Support `tldr-url https://example.com/article` and optional `--bullets N` to control summary length. Output clean markdown-formatted bullets to stdout. Handle errors gracefully: unreachable URLs, non-HTML content, API failures.

---

## 6. `dns-race` - Global DNS Server Race

**Kick-off prompt:**

> Create a Go CLI called `dns-race` that queries a domain against 8 well-known public DNS servers (Google 8.8.8.8, Cloudflare 1.1.1.1, Quad9 9.9.9.9, OpenDNS 208.67.222.222, and 4 more) in parallel and shows the results as a race animation. Query all servers concurrently, display a live-updating progress bar for each server, and show results as they arrive (fastest first). Final output: sorted table with server name, IP, response time, and resolved addresses. Highlight any servers that returned different results (propagation issues). Support `dns-race example.com` and `--type AAAA` for record type selection.

---

## 7. `astro` - Terminal Stargazing Briefing

**Kick-off prompt:**

> Create a Go CLI called `astro` that gives you an instant stargazing briefing. Fetch: (1) ISS current position from open-notify.org API, (2) moon phase calculated from the current date (algorithmic, no API needed), (3) visible planets for tonight from a public astronomy API or calculated from orbital elements. Auto-detect location via ip-api.com or accept `--lat/--lon`. Display: moon phase with emoji and illumination %, ISS position with "visible from your location: yes/no" based on distance, planet visibility list. Use ANSI colors for a night-sky themed output.

---

## 8. `heatmap` - GitHub Contribution Graph in Terminal

**Kick-off prompt:**

> Create a Go CLI called `heatmap` that renders a GitHub user's contribution graph (the familiar green squares) directly in the terminal. Use the GitHub GraphQL API to fetch the contributionCalendar data for a user. Render using Unicode block characters with ANSI 256-color or truecolor for the green gradient (4 intensity levels matching GitHub's). Display the last 52 weeks with day-of-week labels (Mon/Wed/Fri) and month labels on top. Support `heatmap rhuss` (default: last year) and `--year 2024`. Include total contribution count and current streak. Requires GITHUB_TOKEN env var for GraphQL access.

---

## 9. `exchange` - Currency Converter with Sparkline

**Kick-off prompt:**

> Create a Go CLI called `exchange` that converts currencies and shows a 30-day rate trend as an inline sparkline chart. Use the frankfurter.app API (free, no key, ECB data). Usage: `exchange 100 EUR USD` outputs the converted amount plus a sparkline showing the rate trend over the last 30 days using Unicode braille or block characters. Include the min, max, and average rate in the period. Support `--days N` to change the history window. Handle edge cases: same currency, unsupported currencies (API returns error), weekend gaps in data.

---

## 10. `port-who` - Port Process Identifier with Vulnerability Check

**Kick-off prompt:**

> Create a Go CLI called `port-who` that identifies what process is listening on a given port and checks for known vulnerabilities. Step 1: Use `lsof -i :PORT` (or equivalent) to find the process name, PID, and user. Step 2: Try to determine the software version (from process args, binary --version, or package manager). Step 3: Query the OSV.dev API (free, no key) with the package name and version to check for known CVEs. Display: port, protocol, PID, process name, version, user, and a color-coded vulnerability summary (green: none, yellow: low/medium, red: high/critical). Support `port-who 8080` or `port-who --scan 8000-9000` to scan a range.
