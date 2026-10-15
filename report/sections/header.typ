#import "../theme.typ": *

#let kpi(label, value, sub: none) = box(width: 100%, inset: (x: 2.5mm, y: 1.8mm), stroke: 0.4pt + rule, radius: 1mm, {
  text(6.5pt, weight: "bold", fill: muted, tracking: 0.4pt, upper(label)); linebreak()
  text(13pt, weight: "bold")[#value]
  if sub != none { h(1mm); text(7pt, fill: muted)[#sub] }
})

// Title, one line of context, then six key numbers.
#let header(d) = {
  grid(columns: (1fr, auto), align: (left + bottom, right + bottom),
    text(17pt, weight: "bold", fill: accent)[Session report],
    text(8pt, fill: muted)[#if d.first != none [#d.first -- #d.last]])
  v(0.5mm)
  text(8pt, fill: muted)[Professors: #if d.professors.len() > 0 [#d.professors.join(", ")] else [-]
    #if d.limits.talk > 0 [ · limits: setup #fmt-s(d.limits.setup), talk #fmt-s(d.limits.talk), Q&A #fmt-s(d.limits.qa), pack #fmt-s(d.limits.pack)]]
  v(2.5mm)
  let presented = d.teams.filter(t => t.presented).len()
  grid(columns: (1fr,) * 6, column-gutter: 2mm,
    kpi("Presented", [#presented/#d.teams.len()]),
    kpi("Mean score", [#f1(d.mean)], sub: "/ 9"),
    kpi("Best / worst", if d.spread == none [-] else [#f1(d.spread.at(0)) / #f1(d.spread.at(1))]),
    kpi("Session", if d.span == none [-] else [#fmt-s(d.span)], sub: "min:s"),
    kpi("Full talks", [#d.n_full], sub: "of " + str(presented)),
    kpi("Ended early", [#d.n_skip_talk], sub: "skip"))
}
