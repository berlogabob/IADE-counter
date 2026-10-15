// Shared look: one accent, hairline rules, small type. Change here, every section follows.
#let ink = rgb("#111827")
#let muted = rgb("#6b7280")
#let rule = rgb("#d1d5db")
#let accent = rgb("#1f4e8c")
#let bad = rgb("#b91c1c")

// 0-9 score with one decimal; none shows a dash.
#let f1(v) = if v == none { "-" } else {
  let r = int(calc.round(v * 10))
  str(calc.quo(r, 10)) + "." + str(calc.rem(r, 10))
}
#let dash(v) = if v == none [-] else [#v]
#let two(n) = if n < 10 { "0" + str(n) } else { str(n) }
#let fmt-s(v) = if v == none [-] else {
  let s = int(calc.round(v))
  [#two(calc.quo(s, 60)):#two(calc.rem(s, 60))]
}

// Shared table style: no fills, hairlines between rows, bold header with a heavier rule.
#let grid-table(columns, align: auto, ..args) = table(
  columns: columns, align: align, inset: (x: 3pt, y: 2.6pt),
  stroke: (x, y) => (bottom: if y == 0 { 0.8pt + ink } else { 0.3pt + rule }),
  ..args,
)
#let th(body) = text(7pt, weight: "bold", fill: muted, upper(body))

// A section title: small caps-style label with a rule under it.
#let section(title) = {
  v(5mm, weak: true)
  text(8pt, weight: "bold", fill: accent, tracking: 0.6pt, upper(title))
  v(-1mm)
  line(length: 100%, stroke: 0.5pt + accent)
  v(1.5mm)
}

#let doc(body) = {
  set page(paper: "a4", margin: (x: 14mm, top: 14mm, bottom: 16mm),
    footer: context text(7pt, fill: muted)[Session report #h(1fr)
      #counter(page).display() / #counter(page).final().first()])
  set text(font: ("Helvetica Neue", "Helvetica", "Arial"), size: 8.5pt, fill: ink)
  set par(leading: 0.5em, spacing: 0.6em)
  body
}
