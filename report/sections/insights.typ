#import "../theme.typ": *

// Plain-language findings computed from the data.
#let insights(d) = {
  if d.insights.len() == 0 { return }
  section("Observations")
  for i in d.insights [- #i]
}
