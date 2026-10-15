// Session report. Data comes from data.json (built by build.py); each section is its own file.
// Drop, reorder or add a section by editing the list below.
#import "theme.typ": doc
#import "sections/header.typ": header
#import "sections/results.typ": results
#import "sections/timeline.typ": timeline
#import "sections/timetable.typ": timetable
#import "sections/budget.typ": budget
#import "sections/insights.typ": insights
#import "sections/notes.typ": notes

#let d = json("data.json")
#show: doc
#header(d)
#results(d)
#timeline(d)
#timetable(d)
#budget(d)
#insights(d)
#pagebreak(weak: true)
#notes(d)
