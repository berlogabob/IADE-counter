#import "../theme.typ": *

// Time actually used per stage against its limit, over all presented teams.
#let budget(d) = {
  if d.budget.all(b => b.n == 0) { return }
  section("Time budget")
  grid-table(
    (1fr, auto, auto, auto, auto, 38mm),
    align: (left, right, right, right, right, left),
    table.header(th[Stage], th[Limit], th[Avg], th[Min], th[Max], th[Avg vs limit]),
    ..d.budget.filter(b => b.n > 0).map(b => (
      [#b.stage], [#fmt-s(b.limit)], text(weight: "bold")[#fmt-s(b.avg)], [#fmt-s(b.min)], [#fmt-s(b.max)],
      if b.limit == none or b.limit == 0 { [] } else {
        let r = b.avg / b.limit
        box(width: 20mm, height: 1.8mm, fill: rule.lighten(50%), box(width: 20mm * calc.min(r, 1), height: 1.8mm, fill: accent))
        h(1mm); text(7pt, fill: muted)[#calc.round(r * 100) %]
      },
    )).flatten(),
  )
}
