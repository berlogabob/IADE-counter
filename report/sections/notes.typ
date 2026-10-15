#import "../theme.typ": *

// One block per team: its numbers, then every professor's score and note.
#let notes(d) = {
  section("Notes by team")
  let order = d.teams.sorted(key: t => if t.order == none { 99 } else { t.order })
  let n = d.teams.filter(t => t.rank != none).len()
  // Two cards per row: a grid keeps both columns level, unlike flowing text columns.
  grid(columns: (1fr, 1fr), column-gutter: 9mm, row-gutter: 4mm, ..order.map(t => {
    block(breakable: false, width: 100%, {
      grid(columns: (1fr, auto), align: (left, right),
        text(9.5pt, weight: "bold")[#t.name#if not t.presented [ #text(fill: bad)[not presented]]],
        text(11pt, weight: "bold", fill: accent)[#f1(t.avg)])
      if t.students.len() > 0 { text(7.5pt, fill: muted)[#t.students.join(", ")]; linebreak() }
      text(7pt, fill: muted)[
        #if t.rank != none [Rank #t.rank/#n · ]
        #if t.talk != none [talk #t.talk ] #if t.qa != none [· Q&A #t.qa ]
        #if t.delta_min != none [· start #if t.delta_min == 0 [on time] else [#t.delta_min min] ]
        #if t.lo != none [· scores #t.lo–#t.hi]
        #if t.sd != none [(sd #t.sd)]
        #if t.skipped.len() > 0 [· skipped #t.skipped.join(", ")]
      ]
      v(0.8mm)
      for s in t.scores {
        grid(columns: (3.5mm, 17mm, 1fr), column-gutter: 1mm,
          text(weight: "bold")[#dash(s.score)], text(fill: muted)[#s.prof], [#s.note])
        v(0.5mm)
      }
    })
  }))
}
