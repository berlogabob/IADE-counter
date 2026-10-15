#import "../theme.typ": *

// What happened, in presentation order. Times are clock times from the host log.
#let timetable(d) = {
  section("Timetable")
  let order = d.teams.filter(t => t.order != none).sorted(key: t => t.order)
  let flag(t, k) = if k in t.skipped { text(7pt, fill: muted)[ skip] }
  grid-table(
    (6mm, 1fr, auto, auto, auto, auto, auto, auto, auto, auto),
    align: (right, left, center, center, right, right, right, right, right, right),
    table.header(th[\#], th[Team], th[Plan], th[Start], th[Talk], th[Q&A], th[End], th[Draw], th[Setup], th[Pack]),
    ..order.map(t => (
      text(fill: muted)[#t.order], [#t.name], [#dash(t.planned)],
      [#dash(t.t_talk)#if t.delta != none [ #text(7pt, fill: muted)[#t.delta.replace(" min", "'").replace("start ", "")]]],
      [#dash(t.talk)#if t.over != none [ #text(7pt, fill: bad)[+#t.over]]#flag(t, "talk")],
      [#dash(t.qa)#flag(t, "qa")], [#dash(t.t_end)],
      [#fmt-s(t.obs.at("draw", default: none))], [#fmt-s(t.obs.at("setup", default: none))], [#fmt-s(t.obs.at("pack", default: none))],
    )).flatten(),
  )
  v(0.8mm)
  text(7pt, fill: muted)[Start offset in minutes against the plan (- early). "skip": ended early with Skip. Draw, Setup and Pack are stage lengths.]
}
