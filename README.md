# Sift

Talk the way you'd tell a friend. It comes back as a plan.

You speak (or type) whatever's going on. An agent reads it, rewrites it into
titles, works out the dates, and files it as events, tasks, backlog items or
notes. You confirm before anything lands.

## Running it

Sift parses captures one of two ways, switchable in Settings:

- **On device** (default) — Apple's Foundation Models. Free, offline, nothing
  leaves the phone. Needs iOS 26 and an Apple Intelligence–capable device.
- **Server** — Claude, via the FastAPI service below. Better on messy multi-item
  captures; costs a couple of cents each.

Nothing below is needed for the on-device engine. Just open the project and run.

### Reinstalling (every 7 days)

A free Apple developer account signs builds for a week. When Sift stops opening,
plug the phone in and run:

```bash
~/sift/reinstall.sh
```

It finds the device, rebuilds, reinstalls and relaunches. A paid developer
account ($99/yr) would make builds last a year instead.

### The parse server (optional)

Needs an Anthropic API key.

```bash
cd ~/sift/server
cp .env.example .env       # then put your key in it
~/.local/bin/uv run uvicorn app.main:app --host 0.0.0.0 --port 8787
```

`uv` fetches Python 3.12 and the dependencies on first run. Port 8787 because
8000 was already taken on this machine.

### 2. The app

```bash
open ~/sift/ios/Sift.xcodeproj
```

Pick a simulator and hit run. On a real phone, set the server address in
Settings (the gear on the capture screen) to your Mac's LAN address, e.g.
`http://192.168.1.20:8787` — both devices on the same Wi-Fi.

To see the layouts without a server, launch with the argument
`-siftSampleData YES` (Debug builds only) for a populated day.

## How it fits together

```
server/app/schema.py     wire contract — every field required, strict-schema safe
server/app/prompt.py     the parser's instructions + a 21-day date table
server/app/parser.py     messages.parse → validated items
server/app/main.py       POST /parse, GET /health

ios/Sift/Theme.swift     every colour and type style, in one file
ios/Sift/Models/         SwiftData store, recurrence expansion, sample data
ios/Sift/Speech/         on-device dictation
ios/Sift/Parsing/        on-device model + engine selection
ios/Sift/Networking/     server client, wire → model
ios/Sift/Notifications/  morning digest + per-event lead alerts
ios/Sift/Views/          capture · review · today · calendar · edit · settings
```

The server stores nothing — the phone owns the data. The key stays server-side,
and prompt changes ship without rebuilding the app.

## Decisions worth remembering

**Review before commit.** The parser rewrites aggressively, so every capture
lands in a review sheet first. One tap accepts. A calendar you can't trust is
worse than no calendar, and one silently wrong date is all it takes.

**The raw transcript is kept forever**, attached to every item it produced. When
a summary comes out wrong, that's the only source of truth.

**One morning digest, not three alerts.** iOS caps an app at 64 pending local
notifications. The 5-day / 1-day / morning-of steps are collapsed into a single
7am digest, leaving per-event hour-before alerts. 16 events would have filled
the whole budget the other way. Digest text is baked in at scheduling time, so
the set is rebuilt on every commit, edit and completion.

**Soft dates.** "Sometime next week" resolves to the end of that window and is
flagged approximate — shown differently, and left out of the escalation. A guess
shouldn't nag like a deadline.

**The model never computes a date.** It reports the timing words it heard
("before thursday", "the 14th", "next week") and `DatePhrase` resolves them in
Swift. The on-device model is unreliable at date arithmetic and reliable at
repeating what it heard, so the arithmetic moved to code where it is
deterministic and testable.

**Timing is verified against the transcript.** The model's most common failure is
giving several items the same timing when only one had any, or inventing it
outright. Since it is told to copy the words verbatim, `stripUnheardTiming`
checks they actually appear in what was said, and allows a phrase only as often
as it occurs.

**Booleans before values.** Generation is sequential, so `hasTiming` is asked
before `when`. Without it the model gives everything a date. It also reads "at 2"
as 02:00, so unqualified early hours shift to the afternoon.

**Colour is never the only channel.** Every chip pairs its hue with a glyph and
a count, so a month cell reads without colour vision.

## Not in v1

No sync or accounts. Recurrence is daily / weekly-on-weekdays / monthly-on-a-date
with no per-occurrence exceptions — editing a series edits all of it. No voice
editing of existing items ("move the dentist to 3"). Nothing writes to Apple or
Google Calendar. Transcripts are stored but not searchable.
