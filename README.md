# song.study

A tool for listening to one song ten times in a row and writing down what you hear.

**Open it: https://npyati.github.io/song.study/** — then drag an MP3 onto the window.
Your audio never leaves your machine; the page reads it locally.

Repeat listening is a method, not just repetition. On the second pass you hear the
hook. On the eighth you hear the shaker that drops out for one bar before the chorus.
Most note-taking tools throw that away by merging everything into one list. This one
keeps the pass number, so you can watch your own attention move.

![A waveform with note pins stacked by pass, section markers, a listening prompt with
filter controls, and a ledger of timestamped notes](docs/screenshot.png)

## The ideas it's built on

**Typing competes with listening.** If your hands and eyes are on a text box, you've
stopped doing the thing. So the timestamp is taken on your **first keystroke**, not
when you press Enter. You hear something, start typing, and the anchor is already
set. Take as long as you like finishing the sentence while the song plays on.

**You notice things late.** Every anchor is pulled back by a lag offset (default
1.5s) to cover the gap between hearing a thing and reaching for the keys. It scales
with playback speed, and it doesn't apply while paused — paused, you aren't late,
you're placed. **calibrate** measures how fast your hands answer your ears, which
gives you a floor for it.

**Each pass is for something.** The listening prompt above the note box gives every
pass a job: just listen / form / drums / bass / lyrics / vocals / arrangement / mix /
the moment you keep returning to / free. Every prompt is editable. **blind** hides
everything except the note box, and the screen comes back when the pass ends — made
for pass one.

**The prompts come with filters.** *listen through* runs the song through a
low-pass, a band around the voice, or a high-pass — and a stereo matrix that can play
mono, left, right, or **side**: only what differs between the channels, which is the
width of the mix and nothing else. The bass pass defaults to lows and the mix pass to
side. Your choices stick to the pass. It's all Web Audio in the page.

**A pass has to be a pass.** One only counts if you heard three-quarters of the song
since the last one — skipping to the last ten seconds doesn't count. At the target
the study finishes: playback stops and the prompt asks for the thesis.

## Keys

| key | |
|---|---|
| `space` | play / pause, unless you're mid-note |
| `←` `→` | scrub 5s — or, with a note selected, nudge it ±0.25s (`shift` ±1s) and hear a breath from the new spot |
| `alt` `←` `→` | move the pending timestamp while you're still typing |
| `enter` | log the note · `shift+enter` for a new line |
| `[` `]` | set loop start / end · `\` loop on and off without losing the points · `\|` clears |
| `#tag` | anything with a hash becomes a tag |
| `=name` | a note starting with `=` marks a section — `=chorus`, `=bridge` — drawn on the waveform |
| `esc` | clear the box, end a tour, leave blind, close a panel |

Click a note to hear it from four seconds before, and edit its text where it sits.
Click the track name to rename the study.

## Looking back

- **Waveform** — pins stacked by pass, section boundaries, and a band underneath
  showing which seconds you've actually spent time on. Hover a pin to read its note.
  **spectrum** draws a spectrogram behind it, lows at the bottom.
- **list / compare / map** — every note by pass or by time; two passes side by side,
  with notes within three seconds of each other on one row; or a grid of passes
  against ten-second columns showing where you wrote something. The map shows
  presence and flags only. No counts.
- **tour** — plays the song back and stops at each flagged note to show it to you.
- **index** — searches every note across every study, with tag filters. Point it at
  a notes folder to include studies this browser hasn't seen.
- **poster** — the whole study as one printable SVG: waveform, pins, sections, time
  spent, and every note, numbered against the timeline.
- **midi** — map a knob to scrub, a knob to lag, and a button to play.

## Your notes are a Markdown file

Click **save to .md** and pick where the notes live. Every change is written there.
Edit the file in Obsidian or anything else while the app is open and it picks up the
change within a couple of seconds. Chrome drops write permission between sessions, so
next time the button reads `reconnect <name>.md` — one click and you're back.

```markdown
---
title: "O Green World"
file: "O Green World.mp3"
duration: 275.40
pass: 4
targetPasses: 10
lag: 1.5
prompts:
  1: "just listen — no notes"
  2: "form — where are the sections"
filters:
  8: full side
---

## Pass 2 — form — where are the sections

- **[0:00.4]** =intro
- **[0:14.2]** drum machine is dry, almost no room on it
- ★ **[0:41.8]** #bass enters under the second line, way later than I remembered
```

Continuation lines are indented two spaces; blank lines inside a note survive.
Files from older versions, without quoted values, still load.

The heat band is kept in browser storage rather than the file, so the file stays
something you'd want to read. Browser storage also mirrors everything as crash
safety for the window before you've bound a file.

## Running it locally

The hosted page is the easy way. To run from a checkout, `./study.command` serves
the folder on `127.0.0.1:8788` and opens Chrome. Opening `index.html` directly also
works, but a `file://` page has no real origin and Chrome won't remember file
permissions for it.

Chrome or Edge — it leans on the File System Access API.

## Shape of it

One `index.html`. No build step, no dependencies, no server beyond a static file
host, no network calls except the web fonts.
