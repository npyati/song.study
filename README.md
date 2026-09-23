# song.study

A single-page tool for listening to one song ten times in a row and writing down
what you hear.

The premise is that repeat listening is a method, not just repetition. On the
second pass you hear the hook. On the eighth you hear the shaker that drops out
for one bar before the chorus. Most note-taking tools throw that away by merging
everything into one list — this one keeps the pass number, so you can watch your
own attention move.

![A waveform with note pins stacked by pass, a listening prompt, and a ledger of
timestamped notes](docs/screenshot.png)

## The two ideas it's built on

**Typing competes with listening.** If your hands and eyes are on a text box you
have stopped doing the thing. So the timestamp is taken on your **first
keystroke**, not when you press Enter. You hear something, you start typing, the
anchor is already set, and you can take as long as you want finishing the
sentence while the song plays on.

**You notice things late.** You register a moment a second or two after it
happens, so every anchor is pulled back by an adjustable lag offset (default
1.5s). Tune it after one pass. Jumping to a note starts playback four seconds
early, so you hear the approach rather than the aftermath.

## Running it

```
./study.command
```

That serves the folder on `127.0.0.1:8788` and opens Chrome. It needs to be a
real origin rather than `file://`, because Chrome will not hold write permission
on your notes file across sessions for an opaque origin.

Then drag an MP3 onto the window. Chrome only — it leans on the File System
Access API.

## Using it

Click **save to .md** and pick where your notes go. Every change is written
there from that point on. Chrome drops write permission between sessions, so
next time the button reads `reconnect <name>.md` — one click and it resumes,
reading the file back in as the authority.

| key | |
|---|---|
| `space` | play / pause, unless you're mid-note |
| `←` `→` | scrub 5s, or nudge a selected note ±0.25s (`shift` for ±1s) |
| `alt` `←` `→` | move the pending timestamp while you're still typing |
| `enter` | log the note |
| `#tag` | anything with a hash becomes a tag |
| `s` | flag a note (with a row focused) |
| `esc` | clear the box |

The **listening prompt** above the text box is what the current pass is for. It
defaults to a ladder — just listen / form / drums / bass / lyrics / vocals /
arrangement / mix / the moment you keep returning to / free — and every line is
editable and saved per study. Pass one is deliberately a no-notes pass.

The waveform carries three things: note pins stacked vertically by pass and
colour-ramped across ten, a band underneath showing which seconds you have
actually spent time on, and a 30-second grid. Flagged notes get taller pins. The
heat band is the interesting one — it catches the passage you kept rewinding to
and never wrote a word about.

## Your notes are a Markdown file

Plain text, readable without this tool, diffable, yours:

```markdown
---
title: O Green World
file: O Green World.mp3
duration: 264.31
pass: 4
targetPasses: 10
lag: 1.75
prompts:
  1: just listen — no notes
  2: form — where are the sections
---

## Pass 2 — form — where are the sections

- **[0:14.2]** drum machine is dry, almost no room on it
- ★ **[0:41.8]** #bass enters under the second line, way later than I remembered
```

Round-trip tested: multi-line notes, Markdown metacharacters, flags and
timestamps past ten minutes all survive, and a second write is byte-identical.

Two things stay out of the file on purpose. The heat band is derived playback
telemetry and would bury the notes under 250 numbers. Note ids are regenerated
per session. Both live in browser storage, which also keeps a mirror of
everything as crash safety for the window before you have bound a file.

## Shape of it

One `index.html`, no build step, no dependencies, no server beyond a static file
handler, no network calls. Your audio and your notes never leave the machine.
