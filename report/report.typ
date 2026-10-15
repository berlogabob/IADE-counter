// Session report. Data comes from data.json (built by build.py); each section is its own file.
#import "theme.typ": doc
#import "sections/header.typ": header
#import "sections/results.typ": results
#import "sections/timetable.typ": timetable
#import "sections/notes.typ": notes

#let d = json("data.json")
#show: doc
#header(d)
#results(d)
#timetable(d)
#notes(d)
