# linkagg

Brush a row-level display and watch aggregate displays fill in proportion to
the rows you selected.

Aggregate views such as bar charts summarise many rows into one mark. Existing
linked-brushing tools in R support only views of individual data points, and
crosstalk's authoring guide says partially highlighting a bar from a linked
selection is "not impossible" but unexplored, and advises steering clear.
`linkagg` keeps hold of the row-to-group mapping, so it can fill a bar
partially and draw the threads that produced the fill.

Output is an htmlwidget. It works inside Shiny, and it saves to a single
self-contained HTML file with no server, so an interactive figure can be
emailed, archived, and opened offline in five years like a static one.

## Status

Early. Not on CRAN. Passes `R CMD check` clean (0 errors, 0 warnings, 0 notes)
on R 4.5.3, with 62 passing tests. Not yet used on a real study.

The layout is fixed: row-level displays on the left, aggregate displays on the
right, listing below. Treat this as a working prototype, not a stable API.

## Install

```r
# install.packages("remotes")
remotes::install_github("renit12345-ship-it/linkagg")
```

## Try it

```r
source(system.file("examples/edish-demo.R", package = "linkagg"))   # simulated
source(system.file("examples/pbc-trial.R",  package = "linkagg"))   # real trial
source(system.file("examples/cdisc-adam.R", package = "linkagg"))   # real ADaM
```

## On a real trial

`pbc-trial.R` runs the figure on the Mayo Clinic primary biliary cholangitis
trial: real patient data from a real randomised study of D-penicillamine
against placebo, 1974 to 1984, 312 randomised patients, distributed in the
`survival` package and described in Fleming and Harrington (1991).

Two things come out of it that a static safety pack does not give you.

**The volcano finds nothing, correctly.** No clinical finding separates the
arms — the smallest p is 0.071 — which is what randomisation of baseline
findings should look like. A display that manufactures a signal here would be
worse than useless.

**Brushing answers an overlap question.** Select the high-bilirubin,
high-AST corner and each finding fills to the share of its own patients you
just caught. For the region bilirubin >= 3 mg/dL and AST >= 100 U/L, 87 of 312
patients:

| finding      | patients | in the region | share | enrichment |
|--------------|----------|---------------|-------|------------|
| Ascites      | 24       | 14            | 58.3% | 2.09x      |
| Oedema       | 49       | 26            | 53.1% | 1.90x      |
| Spider naevi | 90       | 43            | 47.8% | 1.71x      |
| Stage 4      | 109      | 47            | 43.1% | 1.55x      |
| Hepatomegaly | 160      | 64            | 40.0% | 1.43x      |

Ordered by clinical severity: the decompensation signs concentrate in the
high-bilirubin patients, the least specific sign least. A frequency table
gives you "24 patients had ascites" and "87 had bilirubin >= 3" as separate
rows and cannot tell you that most of the ascites patients are the same
people. That overlap is the thing this package exists to show.

## Use

```r
library(linkagg)

# adsl is one row per subject, restricted to the safety population.
# adsl$SOC is a list-column: each element is that subject's system organ
# classes, so a subject with events in three SOCs contributes to three bars.

fig <- linkagg(adsl, USUBJID) |>
  view_points(TBILI, ALT,
              log_x = TRUE, log_y = TRUE,
              x_lab = "Peak total bilirubin (xULN)",
              y_lab = "Peak ALT (xULN)",
              zone  = list(x = 2, y = 3, label = "REFERENCE THRESHOLD")) |>
  view_bars(SOC, by = ARM, label = "System organ class") |>
  view_table(cols = c("USUBJID", "ARM", "ALT", "TBILI")) |>
  as_linkagg_widget(caption = "ADSL / ADAE, safety population, cut 2026-06-30")

htmlwidgets::saveWidget(fig, "figure.html", selfcontained = TRUE)
```

`selfcontained = TRUE` requires pandoc. RStudio bundles its own, so this works
from the RStudio console with no setup. From a plain terminal `Rscript` it will
fail with "requires pandoc" unless you point R at one first:

```r
Sys.setenv(RSTUDIO_PANDOC =
  "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64")
```

## Treatment arms and denominators

`by` splits every group into one sub-bar per arm, which is how safety displays
are actually read. Nobody reviews a pooled count of 58 subjects with a
gastrointestinal event; they review 22 on placebo against 36 on active.

With `by` set, bar length is the percentage of that arm's analysis population,
matching the denominator convention of a standard adverse event summary. The
denominator defaults to the number of rows per arm in `data`, which is correct
when `data` is the analysis population. When it isn't, say so explicitly:

```r
view_bars(SOC, by = ARM, population = c(Placebo = 80, "Drug A" = 82))
view_bars(SOC, by = ARM, population = adsl_full)   # counted, not taken as sizes
```

A missing or zero denominator is an error rather than a silent `NaN`, because a
percentage against the wrong denominator is the classic way these displays go
wrong and it is not something to discover in review.

Selecting rows fills each arm's sub-bar to the share of *that arm's* affected
subjects who are selected, so the comparison across arms stays honest.

## Faceting

`facet` draws one small multiple per level on shared scales, so panels are
comparable. Brushing acts within a single panel, which is the correct
semantics: selecting the high-ALT corner of the high-dose panel should not
sweep in placebo subjects.

```r
view_points(TBILI, ALT, log_x = TRUE, log_y = TRUE, facet = ARM)
```

Rows whose facet value is outside `facet_levels` are marked rather than
silently dropped, so a typo in a level name does not quietly remove subjects.

Add `facet_row` for a full grid: one column per level of `facet`, one row per
level of `facet_row`.

```r
view_points(TBILI, ALT, log_x = TRUE, log_y = TRUE,
            facet = ARM, facet_row = SEX)
```

Scales stay shared across the whole grid, so every panel is comparable with
every other, and a brush still selects only the cell you dragged over: the
subjects in that arm *and* that sex. Internally a panel is one index,
`row * n_columns + column`, so the grid reuses the same selection path as a
single strip of panels rather than introducing a second one.

## Choosing columns at runtime

The view functions take a bare column name, a string, or any expression that
evaluates to a string. The last form is what makes them usable from Shiny,
where the column is chosen by the user:

```r
view_points(spec, TBILI, ALT, facet = input$fcol, facet_row = input$frow)
```

An expression evaluating to `NULL` means "no column", so an optional facet or
arm can be switched off without building a different call. A **bare name is
always taken literally**, so a variable that happens to share a column's name
can never silently redirect a reference. Wrap it in parentheses when you do
want the variable's value: `by = (arm_col)`.

## Drill-down

`drill` gives a second level below the grouping, such as preferred term below
system organ class. Click a group label to descend, click the breadcrumb to
come back. Arm splits, denominators and partial fills all work the same way at
the drilled level.

```r
view_bars(SOC, by = ARM, drill = PT)
```

`SOC` and `PT` must pair positionally: element `j` of `PT[[i]]` is the term for
element `j` of `SOC[[i]]`. Mismatched lengths are an error naming the offending
row, because a silent misalignment here would attribute events to the wrong
organ class.

## Histograms

The case crosstalk's own documentation names as unsupported, since each bar
stands for many rows. A selection fills each bin from the baseline up.

```r
view_hist(ALT, bins = 30, by = ARM, log = TRUE)
```

Log binning drops non-positive values, warns with the count, and reports the
number of unbinned rows on the display rather than passing over them.

## Volcano plot

```r
view_volcano(PT, by = ARM, ref = "Placebo", comp = "Drug A", min_n = 5)
```

One point per term, placed by risk difference (comparison minus reference, in
percentage points) against `-log10(p)` from Fisher's exact test. Volcano and
dot plots are the two displays content experts favour for summarising harms in
a trial, so this is the shape a safety reviewer already reads.

Each point stands for many subjects, which makes it an aggregate mark in the
sense this package exists for: with a selection active every point fills from
the bottom in proportion to the share of *its own* subjects selected. Brushing
the Hy's law corner of an eDISH plot and reading the volcano answers a question
no static safety pack contains — which adverse event signals those subjects
actually carry. In the bundled example, brushing 15 subjects from that corner
fills the four liver terms to 17–29% and every background term to under 6%.

The recognised weakness of a volcano is that it shows an effect estimate
without its precision: a term seen in two subjects can sit as far from the
origin as one seen in fifty. Two things guard against that here. Point area is
proportional to the number of subjects contributing, so sparse terms look
sparse; and `min_n` drops the thinnest terms while printing how many were
dropped on the display rather than passing over them silently. The `p = 0.05`
line is a guide to the eye with no multiplicity adjustment implied.

## Performance

Selection is a `Uint8Array` mask plus an `Int32Array` of selected indices, not a
`Set`. Point pixel positions are precomputed once, so brushing compares numbers
rather than running an inverse scale per point. Above `canvas_threshold` rows
(6,000 by default) the scatter renders to canvas, so recolouring is one pass
instead of touching every DOM node.

Measured end to end on one machine: building the spec in R, writing the file,
and the redraw the browser reports after a brush.

| subjects  | spec  | file size | brush redraw |
|-----------|-------|-----------|--------------|
| 254 (real CDISC pilot) | 0.02 s | 0.4 MB | 3 ms |
| 10,000    | 0.03 s | 0.6 MB   | 5 ms      |
| 200,000   | 0.83 s | 12.3 MB  | 344 ms    |
| 1,000,000 | 4.5 s  | 61.3 MB  | 1,746 ms  |

**Read the file-size column before the timing column.** The row-level data
travels inside the HTML, so size grows linearly at roughly 60 MB per million
subjects. That, not speed, is the real ceiling on a self-contained file:

- Up to ~200,000 subjects a brush stays under half a second and the file is
  small enough to email. This is the range the package is built for, and it is
  already far beyond any single trial.
- At 1,000,000 it still works, but a 61 MB file and a 1.7-second redraw are
  past the point where anyone would call it interactive.
- At 10,000,000 the arithmetic gives a ~600 MB file. That is not a figure you
  can archive or send, whatever the redraw time. Registry-scale cohorts need
  the aggregation done in R, with the widget receiving the aggregates and a
  sample of the row layer — not every row.

Drawing is the cost above roughly 100,000 subjects, not the arithmetic:
resolving a full selection through the membership index stays in the low
milliseconds, while repainting a million marks does not. Turning `threads`
off is the single biggest saving at that size.

## Provenance

`as_linkagg_widget(stamp = TRUE)` is the default and writes a footer line
recording the render time, package version, row count and per-arm denominators.
Add `caption` for the dataset and any subset applied. Keep both on for anything
you intend to share or archive, since the whole argument for a single-file
interactive figure is that it can be treated like a controlled output.

## In Shiny

```r
ui <- fluidPage(linkaggOutput("fig", height = "760px"), verbatimTextOutput("n"))

server <- function(input, output) {
  output$fig <- renderLinkagg({
    linkagg(adsl, USUBJID) |>
      view_points(TBILI, ALT, log_x = TRUE, log_y = TRUE) |>
      view_bars(soc)
  })
  output$n <- renderPrint(length(input$fig_selected))
}
```

The current selection arrives as `input$<outputId>_selected`, a character
vector of key values, or `NULL` when nothing is selected.

The bundled demo app shows both directions at once:

```r
linkagg::run_linkagg_app()
```

Shiny drives the figure: sidebar controls pick the grid variables, the bar
denominator and whether threads are drawn, and the figure is rebuilt
server-side. The figure drives Shiny: the brushed selection feeds the summary
cards, an arm-by-sex crosstab and a CSV download, all computed in R from
`input$fig_selected`.

One gotcha: `linkaggOutput(height = )` does not resize the figure, it only
sizes the container. If the figure is taller than the container it overlaps
whatever follows. Match the two by ending the pipe with an explicit
`as_linkagg_widget(height = 800)` and setting the same value on the output.

## Threads

By default, selecting rows draws animated threads from each selected row to
every group it belongs to. This is the mapping the package exists to keep, made
visible. Turn it off with `linkagg(..., threads = FALSE)` for a quieter figure.
Threads are capped (`thread_cap`) and are suppressed when the browser reports
`prefers-reduced-motion`.

## What it does not do yet

- One scatter, one bar display and one histogram per figure
- Drill-down is one level deep, so SOC to PT but not HLT in between
- No boxplots, no time-to-onset displays
- Above roughly 100,000 rows, drawing rather than arithmetic becomes the limit
- Never used on a real study: no clinical adopter, no real-data shakeout
- Not validated for any regulated use

## Licence

MIT. Bundles d3 v7.9.0 (ISC) in `inst/htmlwidgets/lib/`.
