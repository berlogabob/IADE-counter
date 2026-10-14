# Redesign: one screen at a time (decided 2026-10-14)

Cycle per presenter: Setup -> Presentation (warning before the end) -> Q&A -> Pack -> random draw of the next presenter -> Setup ...
Phases advance on their own with a beep; the host can tap Next to skip. Setup and Pack are separate timers; Setup has a x0.5..x3 coefficient.
Presenter names (teams / students / groups) are visible to everyone in the draw; a presenter who has finished is hidden from the list and the wheel.

Screens: 1 Welcome (Quick timer | New session) -> 2 Quick timer (no groups, no log, loops forever)
-> 3 New session wizard (names, timing, invite links, start) -> 4 Host (clock, current, next; draw, notes, break behind a drawer) -> 5 Viewer (clock, phase, presenter).
Look: dark, one colour per phase (setup blue, talk green, warning amber, Q&A purple, pack grey), huge digits.

| Task | What | Runner |
|---|---|---|
| T10 | lib/cycle.dart: Stage enum + Cycle (lengths, next with loop, skip zero-length, warning) + tests | codex |
| T11 | Welcome page + Quick timer page (lib/welcome.dart, lib/quick.dart); default route = Welcome | codex |
| T12 | Snapshot: setupMs, packMs, stage, done list; roundtrip tests | codex |
| T13 | Host loop: auto-advance stages, draw between presenters, mark done | codex |
| T14 | Wheel + name list show only remaining presenters; done hidden on all screens | codex |
| T15 | Wizard replaces AdminPage (4 steps) and the host setup column | codex |
| T16 | Theme: phase colours, big type, viewer screen cleanup | pi |
