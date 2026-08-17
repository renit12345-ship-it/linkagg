# linkagg 0.1.0

First release.

* `linkagg()` starts a figure from a subject level data frame.
* `view_points()` draws the row level display that is brushed, with optional
  faceting by one variable or a full grid of two (`facet`, `facet_row`).
* `view_bars()` draws aggregate bars that fill in proportion to the share of
  their own rows selected, optionally split by treatment arm, with population
  denominators and drill down through a hierarchy of terms (`drill`).
* `view_hist()` and `view_volcano()` add a linked histogram and a linked
  volcano plot of between arm risk differences.
* `view_table()` adds a listing that filters to the selection.
* `as_linkagg_widget()` renders the figure; `linkaggOutput()` and
  `renderLinkagg()` provide the 'shiny' bindings, reporting the selection as
  `input$<outputId>_selected`.
* `run_linkagg_app()` launches a demo application.
* Worked examples in `inst/examples`, including two built on real data.
