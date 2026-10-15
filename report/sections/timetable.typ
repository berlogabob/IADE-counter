#import "../theme.typ": *

// Planned against actual, with talk and Q&A shown against their limits.
#let timetable(d) = {
  section("Timetable")
  let order = d.teams.filter(t => t.order != none).sorted(key: t => t.order)
  let use(v, lim, skip) = if v == none { [-] } else {
    let r = if lim > 0 { calc.min(v / lim, 1) } else { 0 }
    box(width: 9mm, height: 1.6mm, fill: rule.lighten(50%), box(width: 9mm * r, height: 1.6mm, fill: if skip { muted } else { accent }))
    h(1mm); fmt-s(v)
  }
  grid-table(
    (6mm, 1fr, auto, auto, 21mm, 21mm, auto, auto, auto, auto),
    align: (right, left, center, center, left, left, right, right, right, right),
    table.header(th[\#], th[Team], th[Plan], th[Start], th[Talk], th[Q&A], th[End], th[Draw], th[Setup], th[Pack]),
    ..order.map(t => (
      text(fill: muted)[#t.order], [#t.name], [#dash(t.planned)],
      [#dash(t.t_talk)#if t.delta_min != none [ #text(7pt, fill: if t.delta_min > 0 { bad } else { muted })[#if t.delta_min == 0 [on time] else [#str(t.delta_min)']]]],
      [#use(t.talk_s, d.limits.talk, "talk" in t.skipped)#if t.over_s > 0 [ #text(7pt, fill: bad)[+#t.over_s s]]],
      [#use(t.qa_s, d.limits.qa, "qa" in t.skipped)],
      [#dash(t.t_end)],
      [#fmt-s(t.obs.at("draw", default: none))], [#fmt-s(t.obs.at("setup", default: none))], [#fmt-s(t.obs.at("pack", default: none))],
    )).flatten(),
  )
  v(0.8mm)
  text(7pt, fill: muted)[Bars show time used against the limit; grey = ended early with Skip. Start offset in minutes against the plan (- early, red = late).]
}
