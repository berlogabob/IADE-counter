# 04 roster, notes, late/early

Steps 2-3 work (host pushes `Snapshot`, viewer mirrors, QR dialog). Keep the diff small, no new packages.

## Roster (host types it, viewer sees names)
Host setup block gets a multiline `TextField` "Roster", one group per line:
`14:30 Group A: Ana, Rui` (time optional, students optional; lines that are blank are ignored).
Pre-fill nothing. Parsing happens when Start is pressed from idle at student 1 of group 1, and the result is stored in the snapshot.

### session.dart additions
- `class Group { final String name; final String planned; /* 'HH:MM' or '' */ final List<String> students; }` with `toJson`/`fromJson`.
- `List<Group> parseRoster(String text)`: regex `^(\d{1,2}:\d{2})?\s*([^:]+?)\s*(?::\s*(.*))?$` per trimmed non-empty line; students = split on `,`, trimmed, empties dropped.
- `int? startDelta(String planned, DateTime actual)`: minutes `actual - planned` (positive = late); null when `planned` is empty or malformed. Same-day arithmetic only.
- `Snapshot` gains `List<Group> groups` (default const []), `int gi` (group index, default 0), `int si` (student index within group, default 0). Keep `student` (running 1-based total) and everything else. Update `toJson`/`fromJson`/`==`/`hashCode`. Notes are NOT in Snapshot (see below).

## Flow (main.dart, host)
- State: `List<Group> _groups`, `int _gi`, `int _si`.
- Label: when groups are non-empty show `<group name> · <student name or 'Student #n'>` instead of `Student #n` (host and viewer, idle and running).
- `_nextStudent`: log as today, then advance: `_si++`; when `_si >= max(1, group.students.length)` move to next group (`_gi++`, `_si = 0`). Past the last group: stay idle, label "All done".
- First start of a group's first student (idle -> run with `_si == 0`): record `startDelta(group.planned, DateTime.now())` and append ` start +N min` / ` start -N min` (omit when null or 0 -> ` start on time`) to that student's log line. Student log line format: `'${group} · ${studentName}  ' + logLine(...)` only when groups are non-empty.
- Viewer applies `groups/gi/si` from the snapshot.

## Notes (host only, never in state.json)
The viewer link can read state.json, so notes must not be in it. Notes live in a second Nextcloud file with its own share token.
- Route: `#/host/<token>` as today, or `#/host/<token>/<notesToken>`. Viewer route unchanged and never receives the notes token.
- `sync.dart`: add `Future<String?> getText()` and `Future<void> putText(String)` (raw body, same URL/ETag/error rules); rewrite `poll`/`push` to call them (behaviour unchanged).
- main.dart host: if a notes token exists, create a second `Sync(notesToken)`; on init `getText()` and decode `Map<String,String>` (group name -> text; ignore bad JSON). One host-only `ExpansionTile` "Notes" under the buttons with a multiline `TextField` bound to the current group's note. On change, debounce 2 s then `putText(jsonEncode(map))`. Without a notes token the notes still work but live in memory only.
- Include the current group's notes in "Copy log" output (append `Notes (<group>): ...` lines). Plain text.

## Tests (extend test/session_test.dart)
- `parseRoster` on 3 lines incl. no time, no students, extra spaces.
- `startDelta`: late, early, on time, empty planned, malformed.
- Snapshot roundtrip including `groups/gi/si`.

## Acceptance
`flutter analyze`, `flutter test`, `flutter build web` pass. Do not touch `lib/phase.dart` or pubspec.
