#let d = json("data.json")
#let ink = rgb("#1f2937")
#let accent = rgb("#5b3fd0")
#let soft = rgb("#f3f1fb")
#let muted = rgb("#6b7280")
#set page(paper: "a4", margin: (x: 18mm, y: 20mm),
  footer: context [#set text(8pt, fill: muted)
    Defence session report #h(1fr) #counter(page).display() / #counter(page).final().first()])
#set text(font: ("Helvetica", "Arial"), size: 10pt, fill: ink)
#set par(leading: 0.6em)
#show heading.where(level: 1): it => block(above: 1.4em, below: 0.8em,
  text(15pt, weight: "bold", fill: accent, it.body))
#show heading.where(level: 2): it => block(above: 1.2em, below: 0.6em,
  text(12pt, weight: "bold", it.body))

#let sc(v) = if v == none [-] else [#v]
#let score-bar(v) = if v == none { [] } else {
  box(width: 50mm, height: 4mm, fill: soft, radius: 1mm,
    box(width: 50mm * v / 9, height: 4mm, fill: accent, radius: 1mm))
}
#let f1(v) = if v == none { "-" } else {
  let r = int(calc.round(v * 10))
  str(calc.quo(r, 10)) + "." + str(calc.rem(r, 10))
}
#let dash(v) = if v == none [-] else [#v]

// ---- cover ----
#v(30mm)
#text(28pt, weight: "bold", fill: accent)[Defence session report]
#v(4mm)
#text(12pt, fill: muted)[
  #d.teams.len() teams · #d.professors.len() professors
  #if d.first != none [· #d.first -- #d.last]
]
#v(10mm)
#grid(columns: (1fr, 1fr, 1fr), gutter: 6mm,
  ..(
    ("Teams presented", str(d.teams.filter(t => t.presented).len()) + " of " + str(d.teams.len())),
    ("Mean score", f1(d.mean) + " / 9"),
    ("Limits (s)", "talk " + str(d.limits.talk) + " · Q&A " + str(d.limits.qa)),
  ).map(x => block(fill: soft, radius: 2mm, inset: 4mm)[
    #text(8pt, fill: muted)[#x.at(0)] \ #text(16pt, weight: "bold")[#x.at(1)]
  ])
)
#v(8mm)
*Professors:* #d.professors.join(", ")

#pagebreak()

// ---- ranking ----
= Ranking
#table(
  columns: (auto, 1fr, auto, 55mm),
  stroke: none, inset: 5pt, fill: (_, y) => if y == 0 { accent } else if calc.odd(y) { soft },
  table.header(..("#", "Team", "Avg", "").map(h => text(fill: white, weight: "bold")[#h])),
  ..d.teams.filter(t => t.rank != none).sorted(key: t => t.rank).map(t => (
    [#t.rank], [#t.name], [*#f1(t.avg)*], score-bar(t.avg))).flatten(),
)

// ---- timetable ----
= Timetable
#table(
  columns: (auto, 1fr, auto, auto, auto, auto, auto),
  stroke: (top: none, left: none, right: none, bottom: 0.4pt + muted), inset: 5pt,
  table.header(..("Order", "Team", "Planned", "Started", "Talk", "Q&A", "Finished").map(h => strong(h))),
  ..d.teams.filter(t => t.order != none).sorted(key: t => t.order).map(t => (
    [#t.order], [#t.name], [#t.planned],
    [#dash(t.t_talk)#if t.delta != none [ \ #text(8pt, fill: muted)[#t.delta]]],
    [#dash(t.talk)#if t.over != none [ #text(8pt, fill: red)[+#t.over]]], [#dash(t.qa)], [#dash(t.t_end)])).flatten(),
)

#if d.teams.any(t => t.obs.len() > 0) [
  == Observed stage durations (seconds)
  #table(
    columns: (1fr, auto, auto, auto, auto, auto),
    stroke: (top: none, left: none, right: none, bottom: 0.4pt + muted), inset: 5pt,
    table.header(..("Team", "Draw", "Setup", "Talk", "Q&A", "Pack").map(h => strong(h))),
    ..d.teams.filter(t => t.obs.len() > 0).map(t => (
      [#t.name], ..("draw", "setup", "talk", "qa", "pack").map(k => [#dash(t.obs.at(k, default: none))]))).flatten(),
  )
]

// ---- one page per team ----
#pagebreak()
= Teams
#for t in d.teams.sorted(key: t => if t.order == none { 99 } else { t.order }) [
  #block(breakable: false, above: 9mm)[
  == #t.name
  #text(fill: muted)[#t.students.join(", ")]
  #v(2mm)
  #grid(columns: (1fr, 1fr, 1fr, 1fr), gutter: 4mm,
    ..(
      ("Average", f1(t.avg)),
      ("Rank", if t.rank == none { "-" } else { str(t.rank) + " of " + str(d.teams.filter(x => x.rank != none).len()) }),
      ("Talk", if t.talk == none { "-" } else { t.talk }),
      ("Q&A", if t.qa == none { "-" } else { t.qa }),
    ).map(x => block(fill: soft, radius: 2mm, inset: 3mm, width: 100%)[
      #text(8pt, fill: muted)[#x.at(0)] \ #text(14pt, weight: "bold")[#x.at(1)]]))
  #if not t.presented [#text(fill: red)[Did not present.]]
  == Scores and notes
  #table(
    columns: (30mm, 12mm, 1fr), stroke: (top: none, left: none, right: none, bottom: 0.4pt + muted), inset: 5pt,
    table.header(..("Professor", "Score", "Note").map(h => strong(h))),
    ..t.scores.map(s => ([#s.prof], [#sc(s.score)], [#s.note])).flatten(),
  )
]
]
