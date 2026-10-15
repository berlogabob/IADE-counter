#import "../theme.typ": *

// Ranking and score matrix in one table: average bar, each professor's score (shaded), and the spread.
#let results(d) = {
  section("Results")
  let ranked = d.teams.sorted(key: t => if t.rank == none { 99 } else { t.rank })
  let heat(v) = if v == none { none } else { accent.transparentize(100% - v / 9 * 28% - 2%) }
  grid-table(
    (6mm, 1fr, auto, 22mm, ..d.raters.map(_ => 12mm), 11mm),
    align: (right, left, right, left, ..d.raters.map(_ => center), center),
    table.header(th[\#], th[Team], th[Avg], [], ..d.raters.map(r => th(r)), th[Range]),
    ..ranked.map(t => (
      text(fill: muted)[#dash(t.rank)],
      [#t.name],
      text(weight: "bold")[#f1(t.avg)],
      if t.avg == none { [] } else {
        box(width: 20mm, height: 2mm, fill: rule.lighten(50%),
          box(width: 20mm * t.avg / 9, height: 2mm, fill: accent))
      },
      ..t.row.map(v => table.cell(fill: heat(v))[#dash(v)]),
      text(fill: muted)[#if t.lo == none [-] else [#t.lo–#t.hi]],
    )).flatten(),
  )
}
