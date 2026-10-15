#import "../theme.typ": *

// Title line plus one line of facts. No cards.
#let header(d) = {
  grid(columns: (1fr, auto), align: (left + bottom, right + bottom),
    text(16pt, weight: "bold", fill: accent)[Defence session report],
    text(8pt, fill: muted)[#if d.first != none [#d.first -- #d.last]])
  v(1mm)
  let presented = d.teams.filter(t => t.presented).len()
  text(8.5pt, fill: muted)[
    #presented of #d.teams.len() teams presented · #d.professors.len() professors
    #if d.mean != none [· mean #f1(d.mean) / 9]
    · limits: talk #fmt-s(d.limits.talk), Q&A #fmt-s(d.limits.qa)
    #if d.professors.len() > 0 [ \ #d.professors.join(", ")]
  ]
}
