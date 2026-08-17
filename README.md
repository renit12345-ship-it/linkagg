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
source(system.file("examples/edish-demo.R", package = "linkagg"))
```

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

## Performance

Selection is a `Uint8Array` mask plus an `Int32Array` of selected indices, not a
`Set`. Point pixel positions are precomputed once, so brushing compares numbers
rather than running an inverse scale per point. Above `canvas_threshold` rows
(6,000 by default) the scatter renders to canvas, so recolouring is one pass
instead of touching every DOM node.

Measured on a single core, resolving a full selection through the membership
index and re-running the brush pass:

| rows    | hit counting | brush pass | total  |
|---------|--------------|------------|--------|
| 10,000  | 1.9 ms       | 2.7 ms     | 4.6 ms |
| 100,000 | 2.1 ms       | 3.2 ms     | 5.3 ms |
| 500,000 | 16.2 ms      | 6.9 ms     | 23.0 ms |

Those are worst cases, with every row selected. Drawing is the remaining cost
above roughly 100,000 rows, not the arithmetic.

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
