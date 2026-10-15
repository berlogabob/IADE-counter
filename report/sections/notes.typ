#import "../theme.typ": *

// Every professor's score and note per team, two columns to save pages.
#let notes(d) = {
  section("Notes")
  let order = d.teams.sorted(key: t => if t.order == none { 99 } else { t.order })
  columns(2, gutter: 8mm, for t in order {
    block(breakable: false, width: 100%, below: 3.2mm, {
      grid(columns: (1fr, auto),
        text(9pt, weight: "bold")[#t.name #if not t.presented [#text(fill: bad)[ not presented]]],
        text(9pt, weight: "bold", fill: accent)[#f1(t.avg)])
      if t.students.len() > 0 { text(7.5pt, fill: muted)[#t.students.join(", ")]; linebreak() }
      for s in t.scores {
        grid(columns: (3.5mm, 17mm, 1fr), column-gutter: 1mm,
          text(weight: "bold")[#dash(s.score)], text(fill: muted)[#s.prof], [#s.note])
        v(0.6mm)
      }
    })
  })
}
