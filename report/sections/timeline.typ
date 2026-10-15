#import "../theme.typ": *

// One row per team on a shared clock: draw, setup, talk, Q&A, pack. A red tick marks a stage ended with Skip.
#let timeline(d) = {
  let rows = d.teams.filter(t => t.t0 != none and t.t2 != none).sorted(key: t => t.order)
  if rows.len() == 0 { return }
  section("Session timeline")
  let s0 = calc.min(..rows.map(t => t.t0 - t.draw_s - t.setup_s))
  let s1 = calc.max(..rows.map(t => t.t2 + t.pack_s))
  let W = 145mm
  let k = W / (s1 - s0)
  let seg(a, b, c) = if b > a { place(dx: (a - s0) * k, rect(width: (b - a) * k, height: 3mm, fill: c, stroke: none)) }
  let steps = (30, 60, 120, 300, 600, 900, 1800, 3600)
  let step = steps.find(x => (s1 - s0) / x <= 8)
  if step == none { step = 3600 }
  let clock(x) = two(calc.quo(calc.rem(x, 86400), 3600)) + ":" + two(calc.quo(calc.rem(x, 3600), 60)) + if step < 60 { ":" + two(calc.rem(x, 60)) } else { "" }
  let ticks = range(calc.ceil(s0 / step) * step, s1 + 1, step: step)
  grid(columns: (28mm, W), row-gutter: 1.2mm,
    ..rows.map(t => (
      text(8pt)[#t.order. #t.name],
      box(width: W, height: 3mm, {
        place(rect(width: W, height: 3mm, fill: rule.lighten(60%), stroke: none))
        seg(t.t0 - t.setup_s - t.draw_s, t.t0 - t.setup_s, rule)
        seg(t.t0 - t.setup_s, t.t0, muted.lighten(40%))
        seg(t.t0, if t.t1 != none { t.t1 } else { t.t2 }, accent)
        if t.t1 != none { seg(t.t1, t.t2, accent.lighten(45%)) }
        seg(t.t2, t.t2 + t.pack_s, rule)
        if "talk" in t.skipped and t.t1 != none { place(dx: (t.t1 - s0) * k - 0.3mm, rect(width: 0.6mm, height: 3mm, fill: bad, stroke: none)) }
        if "qa" in t.skipped { place(dx: (t.t2 - s0) * k - 0.3mm, rect(width: 0.6mm, height: 3mm, fill: bad, stroke: none)) }
      })
    )).flatten(),
    [], box(width: W, height: 4mm, for x in ticks {
      place(dx: (x - s0) * k, line(start: (0mm, 0mm), end: (0mm, 1mm), stroke: 0.4pt + muted))
      place(dx: (x - s0) * k - 5mm, dy: 1mm, box(width: 10mm, align(center, text(6.5pt, fill: muted, clock(x)))))
    }))
  v(0.5mm)
  let sw(c, l) = [#box(width: 2.5mm, height: 2mm, fill: c) #text(7pt, fill: muted)[#l]#h(3mm)]
  sw(rule, "draw / pack") + sw(muted.lighten(40%), "setup") + sw(accent, "talk") + sw(accent.lighten(45%), "Q&A") + [#box(width: 0.6mm, height: 2mm, fill: bad) #text(7pt, fill: muted)[ended early with Skip]]
}
