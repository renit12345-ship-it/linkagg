/* linkagg - linked selection across aggregate views
 *
 * Every aggregate display (bars, histogram) is reduced to the same shape: a
 * membership index mapping each row to the levels it belongs to, plus an arm
 * index. recomputeHits() resolves a selection back through that index, which
 * is what lets a bar fill partially. Existing linked-brushing tools in R drop
 * the mapping, and that is exactly why they cannot do this.
 */
HTMLWidgets.widget({

  name: "linkagg",
  type: "output",

  factory: function (el, width, height) {

    var PAL = {
      ground: "#FFFFFF", panel: "#F8FAFC", rule: "#E3E8EF",
      dim: "#667085", text: "#101828", data: "#64748B",
      mute: "#CBD5E1", select: "#1D4ED8", zone: "#475467"
    };
    // Arm colours are Okabe-Ito derived: distinguishable under the common
    // forms of colour blindness, and legible when a figure is printed. The
    // first is deliberately neutral, since the first arm is usually placebo.
    var ARM_COLS = ["#7A8794", "#0072B2", "#D55E00", "#009E73", "#CC79A7", "#5A4FCF"];
    var reduce = window.matchMedia &&
                 window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    function arr(v) {
      if (v === null || v === undefined) return [];
      return Array.isArray(v) ? v : [v];
    }
    function one(v) { var a = arr(v); return a.length ? a[0] : null; }
    function armColor(a) { return ARM_COLS[a % ARM_COLS.length]; }

    var st = {
      x: null, n: 0,
      mask: null, selIdx: null, selCount: 0, has: false, source: "none",
      px: null, py: null,
      pv: null, bv: null, hv: null, tv: null,
      barAgg: null, histAgg: null,
      drillG: null,
      facets: null, panels: [], brushes: [],
      useCanvas: false, xs: null, ys: null,
      VB: { w: 1180, h: 560 },
      SC: { l: 62, t: 48, w: 424, h: 330 },
      B: { x0: 700, w: 392, top: 74, subH: 12, subGap: 2, labH: 16, gap: 14 },
      H: { top: 0, h: 128 }
    };

    // ---- DOM -------------------------------------------------------------
    var root = d3.select(el).append("div")
        .style("background", PAL.ground).style("color", PAL.text)
        .style("font-family", "-apple-system, BlinkMacSystemFont, \"Segoe UI\", " +
               "Inter, Roboto, \"Helvetica Neue\", Arial, sans-serif")
        // Tabular figures keep counts and percentages aligned down a column,
        // which is the whole reason the old build used a monospace face.
        .style("font-variant-numeric", "tabular-nums")
        .style("font-size", "12px")
        .style("border", "1px solid " + PAL.rule)
        .style("border-radius", "10px")
        .style("overflow", "hidden");
    var stage = root.append("div").style("position", "relative")
        .on("pointermove", function (ev) { onFigureMove(ev); })
        .on("pointerleave", function () {
          hoverIx = -1; hideTip();
          if (st.halo) st.halo.attr("opacity", 0);
        });
    var canvas = stage.append("canvas")
        .style("position", "absolute").style("top", 0).style("left", 0)
        .style("pointer-events", "none").style("width", "100%");
    var svg = stage.append("svg").style("position", "relative")
        .style("display", "block").style("width", "100%").style("height", "auto");

    var defs = svg.append("defs");
    var bl = defs.append("filter").attr("id", "lk-bloom-" + el.id)
        .attr("x", "-60%").attr("y", "-200%").attr("width", "220%").attr("height", "500%");
    bl.append("feGaussianBlur").attr("stdDeviation", 3.2).attr("result", "b");
    var mg = bl.append("feMerge");
    mg.append("feMergeNode").attr("in", "b");
    mg.append("feMergeNode").attr("in", "SourceGraphic");
    var sf = defs.append("filter").attr("id", "lk-soft-" + el.id)
        .attr("x", "-50%").attr("y", "-50%").attr("width", "200%").attr("height", "200%");
    sf.append("feGaussianBlur").attr("stdDeviation", 2);

    var gZone = svg.append("g"), gAxis = svg.append("g"), gPts = svg.append("g"),
        gHist = svg.append("g"), gVol = svg.append("g"),
        gArcs = svg.append("g").attr("pointer-events", "none"),
        gBars = svg.append("g"), gTag = svg.append("g"), gBrush = svg.append("g");

    var statbar = root.append("div")
        .style("display", "flex").style("gap", "32px").style("align-items", "center")
        .style("padding", "14px 20px").style("background", PAL.panel)
        .style("border-top", "1px solid " + PAL.rule);
    function stat(label, big) {
      var d = statbar.append("div");
      d.append("div").text(label).style("font-size", "10px")
        .style("letter-spacing", "0.06em").style("font-weight", "500")
        .style("margin-bottom", "2px").style("color", PAL.dim);
      return d.append("div").style("font-size", big ? "20px" : "13px")
        .style("font-weight", big ? "650" : "500")
        .style("letter-spacing", big ? "-0.01em" : "0")
        .style("color", PAL.text);
    }
    var vSel = stat("Selected", true), vSrc = stat("Source"), vMs = stat("Redraw");
    var clearBtn = statbar.append("button").text("Clear selection")
        .style("margin-left", "auto").style("font", "inherit").style("font-size", "12px")
        .style("font-weight", "500").style("padding", "7px 14px")
        .style("cursor", "pointer").style("background", PAL.ground)
        .style("color", PAL.text).style("border", "1px solid " + PAL.rule)
        .style("border-radius", "7px").style("transition", "background 120ms ease")
        .on("mouseenter", function () { d3.select(this).style("background", PAL.panel); })
        .on("mouseleave", function () { d3.select(this).style("background", PAL.ground); })
        .on("click", function () { clearSel(); });

    // Hover readout. "Which subject is that point?" is the first question a
    // reviewer asks, and until now it could only be answered by brushing.
    var tip = stage.append("div")
        .style("position", "absolute").style("pointer-events", "none")
        .style("opacity", 0).style("z-index", 5)
        .style("background", PAL.text).style("color", PAL.ground)
        .style("padding", "7px 10px").style("border-radius", "7px")
        .style("font-size", "11.5px").style("line-height", 1.45)
        .style("white-space", "pre").style("transition", "opacity 90ms ease")
        .style("box-shadow", "0 4px 14px rgba(16,24,40,.18)");

    function showTip(ev, text) {
      var b = stage.node().getBoundingClientRect();
      var x = ev.clientX - b.left, y = ev.clientY - b.top;
      tip.text(text).style("opacity", 1);
      var tw = tip.node().offsetWidth, th = tip.node().offsetHeight;
      // Keep the readout inside the figure rather than clipped at its edge.
      tip.style("left", Math.max(4, Math.min(x + 14, b.width - tw - 4)) + "px")
         .style("top", Math.max(4, y - th - 10) + "px");
    }
    function hideTip() { tip.style("opacity", 0); }

    // Nearest-mark lookup, driven from one listener on the whole figure rather
    // than a handler per mark: the brush overlay sits above the points and
    // would swallow per-mark events, and a handler per mark does not scale to
    // a hundred thousand of them. A linear scan over the projected
    // coordinates is comfortably fast at the sizes the point renderer allows.
    function nearestPoint(vx, vy, maxDist) {
      if (!st.px || !st.pv) return -1;
      var best = -1, bd = maxDist * maxDist, i, dx, dy, d;
      for (i = 0; i < st.n; i++) {
        if (st.px[i] < -1000) continue;
        dx = st.px[i] - vx; dy = st.py[i] - vy;
        d = dx * dx + dy * dy;
        if (d < bd) { bd = d; best = i; }
      }
      return best;
    }

    function pointReadout(i) {
      var pv = st.pv, kv = arr(st.x.cols[st.x.key]);
      var xv = arr(st.x.cols[pv.x])[i], yv = arr(st.x.cols[pv.y])[i];
      var num = function (z) {
        return (typeof z === "number")
          ? (Math.round(z) === z ? String(z) : z.toFixed(2)) : String(z);
      };
      var out = String(kv[i]) +
        "\n" + String(one(pv.xlab)) + ": " + num(xv) +
        "\n" + String(one(pv.ylab)) + ": " + num(yv);
      if (st.facets) {
        out += "\n" + String(st.facets.col) + ": " + panelLabel(st.facets.index[i]);
      }
      return out;
    }

    var hoverIx = -1;
    function onFigureMove(ev) {
      if (!st.pv || !st.px) return;
      var rect = svg.node().getBoundingClientRect();
      if (!rect.width) return;
      var k = st.VB.w / rect.width;
      var vx = (ev.clientX - rect.left) * k, vy = (ev.clientY - rect.top) * k;
      var i = nearestPoint(vx, vy, 9 * k);
      if (i === hoverIx) return;
      hoverIx = i;
      if (i < 0) {
        hideTip();
        if (st.halo) st.halo.attr("opacity", 0);
        return;
      }
      if (st.halo) {
        st.halo.attr("cx", st.px[i]).attr("cy", st.py[i]).attr("opacity", 0.9);
      }
      showTip(ev, pointReadout(i));
    }

    var tableWrap = root.append("div").style("display", "none");
    var footer = root.append("div")
        .style("padding", "10px 16px").style("border-top", "1px solid " + PAL.rule)
        .style("color", PAL.dim).style("font-size", "10.5px").style("line-height", 1.7);

    // ---- helpers ---------------------------------------------------------
    function makeScale(vals, isLog, range) {
      var s = isLog ? d3.scaleLog() : d3.scaleLinear();
      var lo = d3.min(vals), hi = d3.max(vals);
      if (isLog) { lo = Math.max(lo, 1e-9); if (!(hi > lo)) hi = lo * 10; }
      else if (!(hi > lo)) { hi = lo + 1; }
      return s.domain(isLog ? [lo / 1.6, hi * 1.6]
                            : [lo - (hi - lo) * 0.05, hi + (hi - lo) * 0.05])
              .range(range);
    }
    function ticksFor(scale, isLog, n) {
      return isLog ? scale.ticks(n || 4).filter(function (t) {
        var m = t / Math.pow(10, Math.floor(Math.log10(t)));
        return Math.abs(m - 1) < 1e-9 || Math.abs(m - 3) < 1e-9;
      }) : scale.ticks(n || 5);
    }
    function fmt(t) {
      if (t >= 10000 || (t > 0 && t < 0.01)) return d3.format(".1e")(t);
      return d3.format(t < 1 ? ".2~f" : "~g")(t);
    }
    // Counts get thousands separators: at registry scale "1000000" is not a
    // number anyone reads at a glance.
    var fmtN = d3.format(",");

    // ---- aggregate views reduced to one shape ---------------------------
    function aggFromBars(bv, drillG) {
      var mem, levels, nA, armIndex, cells, i, j;
      armIndex = bv.armIndex ? Int32Array.from(arr(bv.armIndex)) : null;
      nA = bv.byLevels ? arr(bv.byLevels).length : 1;
      var rawMem = arr(bv.membership);

      if (drillG === null || drillG === undefined || !bv.drillLevels) {
        levels = arr(bv.levels).slice();
        mem = new Array(st.n);
        for (i = 0; i < st.n; i++) mem[i] = Int32Array.from(arr(rawMem[i]));
        cells = Int32Array.from(arr(bv.cellTotals));
      } else {
        // Drilled: sub-levels are the drill terms recorded under this group.
        // This path reads pairGroup, which keeps one entry per group/term pair
        // and so stays aligned with drillIdx. bv.membership is de-duplicated
        // for counting and would not line up.
        rawMem = arr(bv.pairGroup);
        var rawDrill = arr(bv.drillIdx);
        var dLev = arr(bv.drillLevels);
        var counts = {}, present = [];
        for (i = 0; i < st.n; i++) {
          var gm = arr(rawMem[i]), dm = arr(rawDrill[i]);
          for (j = 0; j < gm.length; j++) {
            if (gm[j] !== drillG) continue;
            var d = dm[j];
            if (d < 0) continue;
            if (counts[d] === undefined) { counts[d] = 0; present.push(d); }
            counts[d]++;
          }
        }
        present.sort(function (a, b) { return counts[b] - counts[a]; });
        var pos = {};
        present.forEach(function (d, ix) { pos[d] = ix; });
        levels = present.map(function (d) { return dLev[d]; });

        mem = new Array(st.n);
        for (i = 0; i < st.n; i++) {
          var gm2 = arr(rawMem[i]), dm2 = arr(rawDrill[i]), out = [];
          for (j = 0; j < gm2.length; j++) {
            if (gm2[j] !== drillG) continue;
            var d2 = dm2[j];
            if (d2 >= 0 && pos[d2] !== undefined && out.indexOf(pos[d2]) < 0) {
              out.push(pos[d2]);
            }
          }
          mem[i] = Int32Array.from(out);
        }
        cells = new Int32Array(levels.length * nA);
        for (i = 0; i < st.n; i++) {
          var a = armIndex ? armIndex[i] : 0;
          if (a < 0) continue;
          var m = mem[i];
          for (j = 0; j < m.length; j++) cells[m[j] * nA + a]++;
        }
      }

      return {
        kind: "bars", mem: mem, armIndex: armIndex,
        levels: levels, nL: levels.length, nA: nA,
        cells: cells, denom: bv.denom ? arr(bv.denom) : null,
        denominator: bv.denominator,
        hits: new Int32Array(levels.length * nA)
      };
    }

    function aggFromHist(hv) {
      var bins = one(hv.bins), nA = hv.byLevels ? arr(hv.byLevels).length : 1;
      var bi = Int32Array.from(arr(hv.binIndex));
      var mem = new Array(st.n);
      for (var i = 0; i < st.n; i++) {
        mem[i] = bi[i] >= 0 ? Int32Array.of(bi[i]) : new Int32Array(0);
      }
      return {
        kind: "hist", mem: mem,
        armIndex: hv.armIndex ? Int32Array.from(arr(hv.armIndex)) : null,
        nL: bins, nA: nA, cells: Int32Array.from(arr(hv.cellTotals)),
        denom: hv.denom ? arr(hv.denom) : null,
        denominator: hv.denominator,
        breaks: arr(hv.breaks),
        hits: new Int32Array(bins * nA)
      };
    }

    // A volcano point is one term standing for many subjects, so it reduces to
    // the same shape as a bar cell: a membership index plus a total. One
    // "arm" only, because the two arms are already contrasted by the x axis.
    function aggFromVolcano(vv) {
      var rawMem = arr(vv.membership), mem = new Array(st.n), i;
      for (i = 0; i < st.n; i++) mem[i] = Int32Array.from(arr(rawMem[i]));
      var lv = arr(vv.levels);
      return {
        kind: "volcano", mem: mem,
        armIndex: vv.armIndex ? Int32Array.from(arr(vv.armIndex)) : null,
        levels: lv, nL: lv.length, nA: 1,
        cells: Int32Array.from(arr(vv.cellTotals)),
        denom: null, denominator: "count",
        rd: arr(vv.riskDiff), p: arr(vv.pValue),
        cRef: arr(vv.countRef), cComp: arr(vv.countComp),
        hits: new Int32Array(lv.length)
      };
    }

    function recomputeHits(agg) {
      agg.hits.fill(0);
      if (!st.has) return;
      var mem = agg.mem, ai = agg.armIndex, nA = agg.nA, hits = agg.hits;
      for (var s = 0; s < st.selCount; s++) {
        var i = st.selIdx[s];
        var a = ai ? ai[i] : 0;
        if (a < 0) continue;
        var m = mem[i], L = m.length;
        for (var j = 0; j < L; j++) hits[m[j] * nA + a]++;
      }
    }

    function aggValue(agg, cellN, a) {
      if (agg.denominator === "population" && agg.denom) {
        var d = agg.denom[a];
        return d > 0 ? (cellN / d) * 100 : 0;
      }
      return cellN;
    }

    // Panel grid. With a row variable the panels are a true grid, one column
    // per level of `facet` and one row per level of `facet_row`; without one
    // they wrap. Both cases resolve to a panel index of row * nCols + col.
    function facetGrid() {
      if (!st.facets) return { nC: 1, nR: 1, nF: 1, grid: false };
      var nCol = st.facets.levels.length;
      if (st.facets.rowLevels) {
        var nRow = st.facets.rowLevels.length;
        return { nC: nCol, nR: nRow, nF: nCol * nRow, grid: true };
      }
      var c = nCol <= 1 ? 1 : (nCol <= 3 ? nCol : Math.ceil(Math.sqrt(nCol)));
      return { nC: c, nR: Math.ceil(nCol / c), nF: nCol, grid: false };
    }

    // Human-readable name for a panel index, for the selection source line.
    function panelLabel(f) {
      if (!st.facets) return "";
      var fg = facetGrid();
      if (!fg.grid) return st.facets.levels[f];
      return st.facets.levels[f % fg.nC] + " / " +
             st.facets.rowLevels[Math.floor(f / fg.nC)];
    }

    // ---- layout ----------------------------------------------------------
    function computeLayout() {
      var B = st.B, SC = st.SC;
      var fg = facetGrid();
      var nF = fg.nF;
      SC.w = nF > 1 ? 556 : 424;
      B.x0 = nF > 1 ? 700 : 700;

      // The value label sits to the right of each bar and grows with the
      // magnitude of the counts, so the bar has to give up width for it.
      // At registry scale "1,727 / 99,672 (1.7%)" needs roughly twice the room
      // "12 / 86 (14.0%)" does, and a fixed width clipped it.
      var maxCell = 0;
      if (st.barAgg) {
        for (var ci = 0; ci < st.barAgg.cells.length; ci++) {
          if (st.barAgg.cells[ci] > maxCell) maxCell = st.barAgg.cells[ci];
        }
      }
      var digits = fmtN(maxCell).length;
      var reserve = Math.ceil((digits * 2 + 10) * 5.4) + 16;
      B.w = Math.max(150, Math.min(392, st.VB.w - B.x0 - reserve));

      var pitch = B.labH + (st.barAgg ? st.barAgg.nA : 1) * (B.subH + B.subGap) + B.gap;
      st.rowPitch = pitch;
      var barsBottom = B.top + (st.barAgg ? st.barAgg.nL : 0) * pitch + 20;

      // A grid of panels needs room to stay readable as rows are added.
      SC.h = fg.nR > 1 ? Math.max(300, 152 * fg.nR) : (nF > 1 ? 300 : 330);
      var scatterBottom = SC.t + SC.h + 44;
      st.H.top = scatterBottom + 18;
      var leftBottom = st.hv ? st.H.top + st.H.h + 34 : scatterBottom;

      // The volcano goes in the left column under the scatter and histogram,
      // not under the bars: a bar display grows with its level count, and
      // stacking beneath it pushed the volcano off the bottom of tall figures.
      var volBottom = 0;
      if (st.vv) {
        st.V = { x0: SC.l, w: SC.w, h: 206, top: leftBottom + 40 };
        volBottom = st.V.top + st.V.h + 46;
      } else {
        st.V = null;
      }

      // Let content drive the height. The floor is only a sanity bound: a hard
      // 500 left a dead band under figures that have no histogram.
      st.VB.h = Math.max(360,
        Math.max(leftBottom, Math.max(barsBottom, volBottom)) + 20);
      svg.attr("viewBox", "0 0 " + st.VB.w + " " + st.VB.h);
    }

    // ---- scatter, with facets -------------------------------------------
    function drawScatterFrame() {
      gZone.selectAll("*").remove();
      gAxis.selectAll("*").remove();
      gTag.selectAll("*").remove();
      gPts.selectAll("*").remove();
      st.panels = [];
      if (!st.pv) return;
      var pv = st.pv, SC = st.SC;
      var xv = arr(st.x.cols[pv.x]), yv = arr(st.x.cols[pv.y]);

      var fg = facetGrid();
      var colLv = st.facets ? st.facets.levels : [null];
      var rowLv = st.facets ? st.facets.rowLevels : null;
      var nF = fg.nF, cols = fg.nC, rowsN = fg.nR;
      var gapX = 22, gapY = fg.grid ? 34 : 30;
      var pw = (SC.w - (cols - 1) * gapX) / cols;
      var ph = (SC.h - (rowsN - 1) * gapY) / rowsN;

      // shared domains across panels
      var xsBase = makeScale(xv, pv.xlog, [0, 1]);
      var ysBase = makeScale(yv, pv.ylog, [0, 1]);

      st.px = new Float64Array(st.n);
      st.py = new Float64Array(st.n);

      var panelN = new Int32Array(Math.max(1, nF));
      if (st.facets) {
        for (var pn = 0; pn < st.n; pn++) {
          var pf = st.facets.index[pn];
          if (pf >= 0 && pf < nF) panelN[pf]++;
        }
      } else { panelN[0] = st.n; }

      // Context layer: every panel also shows the whole cohort faintly behind
      // its own subjects, so a cell can be read against the distribution as a
      // whole rather than only against itself. Panels share scales and differ
      // by a translation, so the ghost positions come from the live ones
      // without re-running a scale per point per panel.
      st.ghost = (nF > 1) && !st.useCanvas &&
                 (st.n * nF <= 60000);

      d3.range(nF).forEach(function (f) {
        var cx = f % cols, cy = Math.floor(f / cols);
        var lab = fg.grid ? null : colLv[f];
        var x0 = SC.l + cx * (pw + gapX);
        var y0 = SC.t + cy * (ph + gapY);
        var xs = (pv.xlog ? d3.scaleLog() : d3.scaleLinear())
                    .domain(xsBase.domain()).range([x0, x0 + pw]);
        var ys = (pv.ylog ? d3.scaleLog() : d3.scaleLinear())
                    .domain(ysBase.domain()).range([y0 + ph, y0]);
        var panel = { f: f, x0: x0, y0: y0, w: pw, h: ph, xs: xs, ys: ys };
        st.panels.push(panel);
        if (f === 0) { st.xs = xs; st.ys = ys; }

        if (pv.zone && pv.zone.x != null && pv.zone.y != null) {
          var zx = xs(one(pv.zone.x)), zy = ys(one(pv.zone.y));
          gZone.append("rect").attr("x", Math.max(x0, zx)).attr("y", y0)
              .attr("width", Math.max(0, x0 + pw - Math.max(x0, zx)))
              .attr("height", Math.max(0, Math.min(zy, y0 + ph) - y0))
              .attr("fill", PAL.zone).attr("fill-opacity", 0.055);
          gZone.append("line").attr("x1", zx).attr("x2", zx).attr("y1", y0)
              .attr("y2", y0 + ph).attr("stroke", PAL.zone)
              .attr("stroke-opacity", 0.45).attr("stroke-dasharray", "4 4");
          gZone.append("line").attr("x1", x0).attr("x2", x0 + pw).attr("y1", zy)
              .attr("y2", zy).attr("stroke", PAL.zone)
              .attr("stroke-opacity", 0.45).attr("stroke-dasharray", "4 4");
        }

        // No box around each panel. In a grid of small multiples the repeated
        // frame is the loudest thing on the page and carries no information;
        // gridlines and a baseline place the data just as well.
        gAxis.append("line").attr("x1", x0).attr("x2", x0 + pw)
            .attr("y1", y0 + ph).attr("y2", y0 + ph).attr("stroke", PAL.rule);

        // Tick labels go on the outer edge only. Repeating the same numbers
        // under all six panels is noise, and the scales are shared anyway.
        var bottomRow = (cy === rowsN - 1) || (f + cols >= nF);
        ticksFor(xs, pv.xlog, nF > 1 ? 3 : 5).forEach(function (t) {
          if (xs(t) < x0 - 1 || xs(t) > x0 + pw + 1) return;
          gAxis.append("line").attr("x1", xs(t)).attr("x2", xs(t))
              .attr("y1", y0).attr("y2", y0 + ph)
              .attr("stroke", PAL.rule).attr("stroke-opacity", 0.7);
          if (!bottomRow) return;
          gAxis.append("text").attr("x", xs(t)).attr("y", y0 + ph + 13)
              .attr("text-anchor", "middle").attr("fill", PAL.dim)
              .style("font-size", "9px").text(fmt(t));
        });
        ticksFor(ys, pv.ylog, nF > 1 ? 3 : 5).forEach(function (t) {
          if (ys(t) < y0 - 1 || ys(t) > y0 + ph + 1) return;
          gAxis.append("line").attr("x1", x0).attr("x2", x0 + pw)
              .attr("y1", ys(t)).attr("y2", ys(t))
              .attr("stroke", PAL.rule).attr("stroke-opacity", 0.7);
        });
        if (cx === 0) {
          ticksFor(ys, pv.ylog, nF > 1 ? 3 : 5).forEach(function (t) {
            if (ys(t) < y0 - 1 || ys(t) > y0 + ph + 1) return;
            gAxis.append("text").attr("x", x0 - 7).attr("y", ys(t) + 3)
                .attr("text-anchor", "end").attr("fill", PAL.dim)
                .style("font-size", "9px").text(fmt(t));
          });
        }
        if (lab !== null && lab !== undefined) {
          gAxis.append("text").attr("x", x0 + 2).attr("y", y0 - 6)
              .attr("fill", PAL.text).style("font-size", "10px").text(lab);
        }
        // Count in the panel, so each cell states its own denominator rather
        // than making the reader infer it from mark density.
        if (fg.grid || nF > 1) {
          gAxis.append("text").attr("x", x0 + pw - 3).attr("y", y0 + 11)
              .attr("text-anchor", "end").attr("fill", PAL.dim)
              .style("font-size", "9px")
              .text("n = " + fmtN(panelN[f] || 0));
        }

        // Grid strips: column headings across the top, row headings down the
        // right, each drawn once rather than repeated on every panel. They are
        // set typographically instead of in filled boxes — at six panels the
        // boxes framed the labels more strongly than the data.
        if (fg.grid && cy === 0) {
          gAxis.append("text").attr("x", x0).attr("y", y0 - 12)
              .attr("fill", PAL.text).style("font-size", "11px")
              .style("font-weight", "600").style("letter-spacing", "0.01em")
              .text(colLv[cx]);
          gAxis.append("line").attr("x1", x0).attr("x2", x0 + pw)
              .attr("y1", y0 - 6).attr("y2", y0 - 6)
              .attr("stroke", PAL.text).attr("stroke-opacity", 0.28);
        }
        if (fg.grid && cx === cols - 1) {
          gAxis.append("text")
              .attr("transform", "translate(" + (x0 + pw + 15) + "," +
                    (y0 + ph / 2) + ") rotate(90)")
              .attr("text-anchor", "middle").attr("fill", PAL.text)
              .style("font-weight", "600").style("font-size", "11px")
              .text(rowLv[cy]);
        }

        for (var i = 0; i < st.n; i++) {
          if (st.facets && st.facets.index[i] !== f) continue;
          st.px[i] = xs(xv[i]);
          st.py[i] = ys(yv[i]);
        }
      });

      // rows in no panel (unmatched facet level) go off-canvas
      if (st.facets) {
        for (var i2 = 0; i2 < st.n; i2++) {
          if (st.facets.index[i2] < 0) { st.px[i2] = -9999; st.py[i2] = -9999; }
        }
      }

      gAxis.append("text").attr("x", SC.l + SC.w / 2).attr("y", SC.t + SC.h + 34)
          .attr("text-anchor", "middle").attr("fill", PAL.dim)
          .style("font-size", "10px").style("letter-spacing", "0.06em")
          .text(String(one(pv.xlab)).toUpperCase());
      gAxis.append("text")
          .attr("transform", "translate(18," + (SC.t + SC.h / 2) + ") rotate(-90)")
          .attr("text-anchor", "middle").attr("fill", PAL.dim)
          .style("font-size", "10px").style("letter-spacing", "0.06em")
          .text(String(one(pv.ylab)).toUpperCase());
      gTag.append("text").attr("x", SC.l).attr("y", 26).attr("fill", PAL.dim)
          .style("font-size", "10px").style("letter-spacing", "0.07em")
          .text("ROW LEVEL \u2014 " + st.n + " ROWS" +
                (st.facets ? " \u00b7 BY " + String(st.facets.col).toUpperCase() +
                   (st.facets.rowLevels
                      ? " \u00d7 " + String(st.facets.rowCol).toUpperCase() : "") : "") +
                (st.useCanvas ? " \u00b7 CANVAS" : ""));

      if (!st.useCanvas) {
        var r = st.n > 2500 ? 2.0 : st.n > 800 ? 2.6 : 3.1;
        st.ptSel = gPts.selectAll("circle").data(d3.range(st.n)).enter().append("circle")
            .attr("cx", function (i) { return st.px[i]; })
            .attr("cy", function (i) { return st.py[i]; })
            .attr("r", r).attr("fill", PAL.data).attr("fill-opacity", 0.5);
      } else { st.ptSel = null; }
      // The halo marks whichever point the pointer is nearest. It lives above
      // the marks but takes no pointer events of its own.
      st.halo = gPts.append("circle").attr("r", 6).attr("fill", "none")
          .attr("stroke", PAL.text).attr("stroke-width", 1.5)
          .attr("opacity", 0).attr("pointer-events", "none");
    }

    function sizeCanvas() {
      var node = canvas.node();
      var cssW = stage.node().clientWidth || st.VB.w;
      var k = cssW / st.VB.w, dpr = window.devicePixelRatio || 1;
      var cssH = st.VB.h * k;
      node.width = Math.max(1, Math.round(cssW * dpr));
      node.height = Math.max(1, Math.round(cssH * dpr));
      canvas.style("height", cssH + "px");
      var ctx = node.getContext("2d");
      ctx.setTransform(dpr * k, 0, 0, dpr * k, 0, 0);
      ctx.clearRect(0, 0, st.VB.w, st.VB.h);
      return ctx;
    }

    // Draws the whole cohort into every panel, faintly, behind the live marks.
    function paintGhosts() {
      if (!st.ghost || !st.pv || !st.panels.length || !st.facets) return;
      var ctx = sizeCanvas();
      var P = st.panels, nP = P.length, fi = st.facets.index;
      ctx.fillStyle = PAL.mute;
      ctx.globalAlpha = 0.5;
      for (var p = 0; p < nP; p++) {
        var ox = P[p].x0, oy = P[p].y0;
        for (var i = 0; i < st.n; i++) {
          var f = fi[i];
          if (f < 0 || f === p) continue;   // its own panel draws it properly
          var bx = st.px[i] - P[f].x0 + ox, by = st.py[i] - P[f].y0 + oy;
          ctx.beginPath(); ctx.arc(bx, by, 1.5, 0, 6.283185); ctx.fill();
        }
      }
      ctx.globalAlpha = 1;
    }

    function paintCanvas() {
      if (!st.useCanvas || !st.pv) return;
      var node = canvas.node();
      var cssW = stage.node().clientWidth || st.VB.w;
      var k = cssW / st.VB.w, dpr = window.devicePixelRatio || 1;
      var cssH = st.VB.h * k;
      node.width = Math.max(1, Math.round(cssW * dpr));
      node.height = Math.max(1, Math.round(cssH * dpr));
      canvas.style("height", cssH + "px");
      var ctx = node.getContext("2d");
      ctx.setTransform(dpr * k, 0, 0, dpr * k, 0, 0);
      ctx.clearRect(0, 0, st.VB.w, st.VB.h);
      var r = st.n > 40000 ? 0.9 : st.n > 15000 ? 1.2 : 1.7, i;
      ctx.globalAlpha = st.has ? 0.45 : 0.55;
      ctx.fillStyle = st.has ? PAL.mute : PAL.data;
      for (i = 0; i < st.n; i++) {
        if (st.has && st.mask[i]) continue;
        if (st.px[i] < -1000) continue;
        ctx.beginPath(); ctx.arc(st.px[i], st.py[i], r, 0, 6.283185); ctx.fill();
      }
      if (st.has) {
        ctx.globalAlpha = 0.95;
        ctx.fillStyle = PAL.select;
        for (i = 0; i < st.selCount; i++) {
          var j = st.selIdx[i];
          if (st.px[j] < -1000) continue;
          ctx.beginPath(); ctx.arc(st.px[j], st.py[j], r + 0.5, 0, 6.283185); ctx.fill();
        }
      }
      ctx.globalAlpha = 1;
    }

    // ---- bars, with drill-down -------------------------------------------
    function drawBars() {
      gBars.selectAll("*").remove();
      st.rows = [];
      if (!st.barAgg || !st.bv) return;
      var agg = st.barAgg, bv = st.bv, B = st.B;
      var nA = agg.nA, pct = agg.denominator === "population";
      var armLv = bv.byLevels ? arr(bv.byLevels) : [null];

      var maxV = 0;
      for (var g = 0; g < agg.nL; g++) {
        for (var a = 0; a < nA; a++) {
          var v = aggValue(agg, agg.cells[g * nA + a], a);
          if (v > maxV) maxV = v;
        }
      }
      var scale = d3.scaleLinear().domain([0, maxV || 1]).range([0, B.w]);
      st.barScale = scale;

      var title = "AGGREGATE \u2014 " + String(one(bv.label)).toUpperCase() +
                  (pct ? "  (% OF ARM POPULATION)" : "  (COUNT)");
      gTag.append("text").attr("x", B.x0).attr("y", 26).attr("fill", PAL.dim)
          .style("font-size", "10px").style("letter-spacing", "0.07em").text(title);

      // breadcrumb
      if (bv.drillLevels) {
        var crumb = gBars.append("g");
        if (st.drillG === null) {
          crumb.append("text").attr("x", B.x0).attr("y", 44).attr("fill", PAL.dim)
              .style("font-size", "10px")
              .text("click a bar label to drill into " + String(one(bv.drill)));
        } else {
          var back = crumb.append("text").attr("x", B.x0).attr("y", 44)
              .attr("fill", PAL.select).style("font-size", "10px")
              .style("cursor", "pointer").attr("tabindex", 0)
              .text("\u2190 all " + String(one(bv.group)) + "  /  " +
                    arr(bv.levels)[st.drillG])
              .on("click", function () { setDrill(null); })
              .on("keydown", function (ev) {
                if (ev.key === "Enter") setDrill(null);
              });
          back.append("title").text("Back to the full grouping");
        }
      }

      if (bv.byLevels) {
        var lg = gBars.append("g").attr("transform",
                   "translate(" + B.x0 + "," + (B.top - 12) + ")");
        var off = 0;
        armLv.forEach(function (nm, a) {
          lg.append("rect").attr("x", off).attr("y", -8).attr("width", 9)
              .attr("height", 9).attr("fill", armColor(a)).attr("rx", 2);
          var t = lg.append("text").attr("x", off + 14).attr("y", 0).attr("fill", PAL.dim)
              .style("font-size", "10px")
              .text(nm + (pct && agg.denom ? " (N=" + agg.denom[a] + ")" : ""));
          // Measure the rendered label. The face is proportional, so guessing
          // a per-character width overlaps the next swatch.
          var tw;
          try { tw = t.node().getComputedTextLength(); } catch (e) { tw = 0; }
          if (!tw) tw = String(nm).length * 6.2;
          off += 14 + tw + 24;
        });
      }

      agg.levels.forEach(function (name, g) {
        var top = B.top + g * st.rowPitch;
        var grp = gBars.append("g");
        var canDrill = bv.drillLevels && st.drillG === null;

        var lab = grp.append("text").attr("x", B.x0).attr("y", top + 10)
            .attr("fill", canDrill ? PAL.select : PAL.text)
            .style("font-size", "10.5px")
            .style("cursor", canDrill ? "pointer" : "default")
            .text(name + (canDrill ? " \u203a" : ""));
        if (canDrill) {
          lab.attr("tabindex", 0).attr("role", "button")
             .attr("aria-label", "Drill into " + name)
             .on("click", function () { setDrill(g); })
             .on("keydown", function (ev) { if (ev.key === "Enter") setDrill(g); });
        }

        for (var a = 0; a < nA; a++) {
          (function (a) {
            var yy = top + B.labH + a * (B.subH + B.subGap);
            var cellN = agg.cells[g * nA + a];
            var len = scale(aggValue(agg, cellN, a));
            var colr = armColor(a);

            grp.append("rect").attr("x", B.x0).attr("y", yy).attr("width", len)
                .attr("height", B.subH).attr("fill", colr).attr("fill-opacity", 0.34)
                .attr("rx", 2);
            // The selected share. On a light ground this reads as solid colour
            // against a tinted track, so it needs no glow to separate it.
            var fill = grp.append("rect").attr("x", B.x0).attr("y", yy)
                .attr("width", 0).attr("height", B.subH).attr("fill", colr)
                .attr("rx", 2);
            var men = grp.append("line").attr("x1", B.x0).attr("x2", B.x0)
                .attr("y1", yy - 2).attr("y2", yy + B.subH + 2)
                .attr("stroke", PAL.text).attr("stroke-width", 1.4).attr("opacity", 0);
            var txt = grp.append("text").attr("x", B.x0 + B.w + 10)
                .attr("y", yy + B.subH - 2).attr("fill", PAL.dim)
                .style("font-size", "9.5px").text(cellText(agg, cellN, 0, a, false));

            // Drawn behind the bar so the row reads as one clickable target.
            var back = grp.insert("rect", ":first-child")
                .attr("x", B.x0 - 6).attr("y", yy - 1)
                .attr("width", B.w + 130).attr("height", B.subH + 2)
                .attr("rx", 3).attr("fill", PAL.panel).attr("opacity", 0);

            grp.append("rect").attr("x", B.x0 - 6).attr("y", yy - 1)
                .attr("width", B.w + 130).attr("height", B.subH + 2)
                .attr("fill", "transparent").style("cursor", "pointer")
                .attr("tabindex", 0).attr("role", "button")
                .attr("aria-label", "Select " + cellN + " rows, " + name +
                      (bv.byLevels ? ", " + armLv[a] : ""))
                .on("pointerenter", function () { back.attr("opacity", 1); })
                .on("pointerleave", function () { back.attr("opacity", 0); })
                .on("focus", function () { back.attr("opacity", 1); })
                .on("blur", function () { back.attr("opacity", 0); })
                .on("click", function () { pickCell(g, a); })
                .on("keydown", function (ev) {
                  if (ev.key === "Enter" || ev.key === " ") {
                    ev.preventDefault(); pickCell(g, a);
                  }
                });

            st.rows.push({ g: g, a: a, fill: fill, men: men, lbl: txt,
                           len: len, total: cellN });
          })(a);
        }
      });
    }

    function cellText(agg, total, hit, a, has) {
      var p = "";
      if (agg.denominator === "population" && agg.denom) {
        var d = agg.denom[a];
        p = " (" + (d > 0 ? (total / d * 100).toFixed(1) : "0.0") + "%)";
      }
      return (has ? fmtN(hit) + " / " + fmtN(total) : fmtN(total)) + p;
    }

    // ---- histogram -------------------------------------------------------
    function drawHist() {
      gHist.selectAll("*").remove();
      st.hbars = [];
      if (!st.histAgg || !st.hv) return;
      var agg = st.histAgg, hv = st.hv, SC = st.SC, H = st.H;
      var nB = agg.nL, nA = agg.nA;
      var x0 = SC.l, w = SC.w, top = H.top, h = H.h;

      var maxV = 0;
      for (var b = 0; b < nB; b++) {
        for (var a = 0; a < nA; a++) {
          var v = aggValue(agg, agg.cells[b * nA + a], a);
          if (v > maxV) maxV = v;
        }
      }
      var ys = d3.scaleLinear().domain([0, maxV || 1]).range([top + h, top]);

      gHist.append("line").attr("x1", x0).attr("x2", x0 + w)
          .attr("y1", top + h).attr("y2", top + h).attr("stroke", PAL.rule);
      gTag.append("text").attr("x", x0).attr("y", top - 8).attr("fill", PAL.dim)
          .style("font-size", "10px").style("letter-spacing", "0.07em")
          .text("AGGREGATE \u2014 " + String(one(hv.label)).toUpperCase() +
                (one(hv.log) ? " (LOG10)" : "") + " \u00b7 " + nB + " BINS");

      var slot = w / nB, pad = Math.min(2, slot * 0.12);
      var colW = (slot - pad * 2) / nA;

      for (var b2 = 0; b2 < nB; b2++) {
        for (var a2 = 0; a2 < nA; a2++) {
          (function (b, a) {
            var cellN = agg.cells[b * nA + a];
            var bx = x0 + b * slot + pad + a * colW;
            var topY = ys(aggValue(agg, cellN, a));
            var fullH = top + h - topY;
            var colr = armColor(a);

            gHist.append("rect").attr("x", bx).attr("y", topY)
                .attr("width", Math.max(0.6, colW - 0.6)).attr("height", fullH)
                .attr("fill", colr).attr("fill-opacity", 0.34);
            var fill = gHist.append("rect").attr("x", bx).attr("y", top + h)
                .attr("width", Math.max(0.6, colW - 0.6)).attr("height", 0)
                .attr("fill", colr).attr("filter", "url(#lk-bloom-" + el.id + ")");

            gHist.append("rect").attr("x", bx).attr("y", top)
                .attr("width", Math.max(0.6, colW)).attr("height", h)
                .attr("fill", "transparent").style("cursor", "pointer")
                .attr("tabindex", 0).attr("role", "button")
                .attr("aria-label", "Select " + cellN + " rows in bin " + (b + 1))
                .on("click", function () { pickBin(b, a); })
                .on("keydown", function (ev) {
                  if (ev.key === "Enter" || ev.key === " ") {
                    ev.preventDefault(); pickBin(b, a);
                  }
                });

            st.hbars.push({ b: b, a: a, fill: fill, baseY: top + h,
                            fullH: fullH, total: cellN });
          })(b2, a2);
        }
      }

      var brk = agg.breaks, lg = one(hv.log);
      [0, Math.floor(nB / 2), nB].forEach(function (i) {
        var v = brk[i];
        if (v === undefined) return;
        gHist.append("text").attr("x", x0 + i * slot).attr("y", top + h + 13)
            .attr("text-anchor", i === 0 ? "start" : (i === nB ? "end" : "middle"))
            .attr("fill", PAL.dim).style("font-size", "9px")
            .text(fmt(lg ? Math.pow(10, v) : v));
      });
      var drop = one(hv.dropped) || 0;
      if (drop > 0) {
        gHist.append("text").attr("x", x0 + w).attr("y", top - 8)
            .attr("text-anchor", "end").attr("fill", PAL.zone)
            .style("font-size", "9px").text(drop + " rows not binned");
      }
    }

    // ---- selection -------------------------------------------------------
    function setMaskFromPredicate(pred, src) {
      var mask = st.mask, idx = st.selIdx, c = 0;
      mask.fill(0);
      for (var i = 0; i < st.n; i++) if (pred(i)) { mask[i] = 1; idx[c++] = i; }
      st.selCount = c; st.has = true; st.source = src;
    }
    function clearBrushes() {
      st.brushes.forEach(function (b) { gBrush.select("#" + b.id).call(b.brush.move, null); });
    }
    function clearSel() {
      st.has = false; st.selCount = 0; st.source = "none";
      if (st.mask) st.mask.fill(0);
      clearBrushes();
      gArcs.selectAll("path").remove();
      render(); pushShiny();
    }
    function pickCell(g, a) {
      var agg = st.barAgg, mem = agg.mem, ai = agg.armIndex;
      setMaskFromPredicate(function (i) {
        if (ai && ai[i] !== a) return false;
        var m = mem[i];
        for (var j = 0; j < m.length; j++) if (m[j] === g) return true;
        return false;
      }, agg.levels[g] + (st.bv.byLevels ? " \u00b7 " + arr(st.bv.byLevels)[a] : ""));
      clearBrushes(); render(); pushShiny();
    }
    function pickBin(b, a) {
      var agg = st.histAgg, mem = agg.mem, ai = agg.armIndex;
      setMaskFromPredicate(function (i) {
        if (ai && ai[i] !== a) return false;
        var m = mem[i];
        return m.length > 0 && m[0] === b;
      }, String(one(st.hv.label)) + " bin " + (b + 1) +
         (st.hv.byLevels ? " \u00b7 " + arr(st.hv.byLevels)[a] : ""));
      clearBrushes(); render(); pushShiny();
    }
    function pickTerm(g) {
      var agg = st.volAgg, mem = agg.mem, ai = agg.armIndex;
      setMaskFromPredicate(function (i) {
        if (ai && ai[i] < 0) return false;
        var m = mem[i];
        for (var j = 0; j < m.length; j++) if (m[j] === g) return true;
        return false;
      }, agg.levels[g]);
      clearBrushes(); render(); pushShiny();
    }
    function setDrill(g) {
      st.drillG = g;
      st.barAgg = aggFromBars(st.bv, g);
      computeLayout();
      drawBars();
      // Drilling changes the bar count, so the volcano band below it moves.
      drawVolcano();
      render();
    }
    function pushShiny() {
      if (!HTMLWidgets.shinyMode || !window.Shiny) return;
      var keys = null;
      if (st.has) {
        var kv = arr(st.x.cols[st.x.key]);
        keys = new Array(st.selCount);
        for (var i = 0; i < st.selCount; i++) keys[i] = kv[st.selIdx[i]];
      }
      Shiny.setInputValue(el.id + "_selected", keys, { priority: "event" });
    }

    // ---- threads ---------------------------------------------------------
    function drawThreads() {
      gArcs.selectAll("path").remove();
      if (!st.x.options.threads || reduce || !st.has || !st.barAgg || !st.pv) return 0;
      var agg = st.barAgg, ai = agg.armIndex, B = st.B, pitch = st.rowPitch;
      var pairs = [];
      for (var s = 0; s < st.selCount; s++) {
        var i = st.selIdx[s];
        if (st.px[i] < -1000) continue;
        var a = ai ? ai[i] : 0;
        if (a < 0) continue;
        var m = agg.mem[i];
        for (var j = 0; j < m.length; j++) pairs.push([i, m[j], a]);
      }
      var cap = one(st.x.options.threadCap) || 160;
      if (pairs.length > cap) {
        var step = pairs.length / cap, out = [];
        for (var t = 0; t < cap; t++) out.push(pairs[Math.floor(t * step)]);
        pairs = out;
      }
      var paths = gArcs.selectAll("path").data(pairs).enter().append("path")
          .attr("d", function (p) {
            var pxx = st.px[p[0]], pyy = st.py[p[0]];
            var qx = B.x0;
            var qy = B.top + p[1] * pitch + B.labH + p[2] * (B.subH + B.subGap) + B.subH / 2;
            var mx = (pxx + qx) / 2;
            return "M" + pxx + "," + pyy + "C" + mx + "," + pyy + " " +
                   mx + "," + qy + " " + qx + "," + qy;
          })
          .attr("fill", "none").attr("stroke", function (p) { return armColor(p[2]); })
          .attr("stroke-width", 0.7).attr("stroke-opacity", 0)
          .attr("filter", "url(#lk-soft-" + el.id + ")");
      paths.each(function () {
        var L = this.getTotalLength();
        d3.select(this).attr("stroke-dasharray", L + " " + L).attr("stroke-dashoffset", L);
      });
      paths.transition().duration(500).delay(function (d, i) { return i * 2.2; })
          .attr("stroke-dashoffset", 0).attr("stroke-opacity", 0.34)
        .transition().duration(880).delay(320).attr("stroke-opacity", 0.08);
      return pairs.length;
    }

    // These transitions carry the value, not just the animation: a bar's width
    // and a point's fill height are the data. requestAnimationFrame is
    // suspended while a tab is hidden, and d3 timers with it, so a figure
    // rendered in a background tab would sit at zero fill. Apply the value
    // directly whenever motion is suppressed or cannot run.
    function anim(sel, dur) {
      if (!dur || document.hidden) return sel;
      return sel.transition().duration(dur).ease(d3.easeCubicOut);
    }

    // ---- render ----------------------------------------------------------
    function render() {
      var t0 = performance.now();
      if (st.barAgg)  recomputeHits(st.barAgg);
      if (st.histAgg) recomputeHits(st.histAgg);
      if (st.volAgg)  recomputeHits(st.volAgg);

      if (st.useCanvas) paintCanvas();
      else if (st.ptSel) {
        var mask = st.mask, has = st.has;
        st.ptSel.attr("fill", function (i) {
              return !has ? PAL.data : (mask[i] ? PAL.select : PAL.mute);
            })
            .attr("fill-opacity", function (i) {
              return !has ? 0.5 : (mask[i] ? 0.95 : 0.18);
            });
      }

      var dur = reduce ? 0 : 540;

      if (st.barAgg) {
        for (var r = 0; r < st.rows.length; r++) {
          (function (row) {
            var hit = st.has ? st.barAgg.hits[row.g * st.barAgg.nA + row.a] : 0;
            var w = row.total > 0 && st.has ? (hit / row.total) * row.len : 0;
            anim(row.fill, dur).attr("width", w);
            anim(row.men, dur)
                .attr("x1", st.B.x0 + w).attr("x2", st.B.x0 + w)
                .attr("opacity", st.has && hit > 0 ? 0.9 : 0);
            row.lbl.text(cellText(st.barAgg, row.total, hit, row.a, st.has))
                .attr("fill", st.has && hit > 0 ? PAL.text : PAL.dim);
          })(st.rows[r]);
        }
      }

      if (st.histAgg && st.hbars) {
        for (var b = 0; b < st.hbars.length; b++) {
          (function (hb) {
            var hit = st.has ? st.histAgg.hits[hb.b * st.histAgg.nA + hb.a] : 0;
            var frac = hb.total > 0 && st.has ? hit / hb.total : 0;
            var hgt = frac * hb.fullH;
            anim(hb.fill, dur)
                .attr("y", hb.baseY - hgt).attr("height", hgt);
          })(st.hbars[b]);
        }
      }

      if (st.volAgg && st.vpts) {
        for (var v = 0; v < st.vpts.length; v++) {
          (function (vp) {
            var hit = st.has ? st.volAgg.hits[vp.t] : 0;
            var frac = vp.total > 0 && st.has ? hit / vp.total : 0;
            var hgt = frac * 2 * vp.r;
            anim(vp.clip, dur)
                .attr("y", vp.cy + vp.r - hgt).attr("height", hgt);
            if (vp.lab) {
              vp.lab.attr("fill", st.has && hit > 0 ? PAL.text : PAL.dim);
            }
          })(st.vpts[v]);
        }
      }

      drawThreads();

      if (st.tv && st.tbody) {
        var tv = st.tv, cap = one(tv.maxRows) || 400, cols = arr(tv.cols);
        var shown = st.has ? st.selCount : st.n;
        var html = "", cnt = 0;
        for (var i = 0; i < st.n && cnt < cap; i++) {
          if (st.has && i >= st.selCount) break;
          var ix = st.has ? st.selIdx[i] : i;
          html += "<tr>";
          for (var c = 0; c < cols.length; c++) {
            var v = arr(st.x.cols[cols[c]])[ix];
            if (typeof v === "number") v = (Math.round(v) === v) ? v : v.toFixed(2);
            html += '<td style="padding:5px 16px;border-bottom:1px solid ' + PAL.rule + '">' +
                    (v === null || v === undefined ? "" : v) + "</td>";
          }
          html += "</tr>"; cnt++;
        }
        st.tbody.node().innerHTML = html;
        st.tableNote.text(st.has
          ? shown + " rows selected" + (shown > cap ? ", first " + cap + " shown" : "")
          : "All " + st.n + " rows");
      }

      vSel.text(fmtN(st.has ? st.selCount : st.n) + " / " + fmtN(st.n))
          .style("color", PAL.select);
      vSrc.text(st.source);
      vMs.text((performance.now() - t0).toFixed(1) + " ms");
    }

    // ---- brushes, one per facet panel ------------------------------------
    function installBrushes() {
      gBrush.selectAll("*").remove();
      st.brushes = [];
      if (!st.pv) return;
      st.panels.forEach(function (p, ix) {
        var id = "lk-br-" + el.id + "-" + ix;
        var b = d3.brush()
            .extent([[p.x0, p.y0], [p.x0 + p.w, p.y0 + p.h]])
            .on("start", function () {
              st.brushes.forEach(function (o) {
                if (o.id !== id) gBrush.select("#" + o.id).call(o.brush.move, null);
              });
            })
            .on("end", function (ev) {
              if (!ev.selection) return;
              var s = ev.selection;
              var x0 = s[0][0], y0 = s[0][1], x1 = s[1][0], y1 = s[1][1];
              var px = st.px, py = st.py, fi = st.facets ? st.facets.index : null;
              setMaskFromPredicate(function (i) {
                if (fi && fi[i] !== p.f) return false;
                return px[i] >= x0 && px[i] <= x1 && py[i] >= y0 && py[i] <= y1;
              }, "brushed region" + (st.facets ? " \u00b7 " + panelLabel(p.f) : ""));
              render(); pushShiny();
            });
        var g = gBrush.append("g").attr("id", id).call(b);
        g.selectAll(".selection")
            .attr("fill", PAL.select).attr("fill-opacity", 0.07)
            .attr("stroke", PAL.select).attr("stroke-opacity", 0.6)
            .attr("stroke-dasharray", "3 3");
        st.brushes.push({ id: id, brush: b });
      });
    }

    // ---- volcano ---------------------------------------------------------
    function drawVolcano() {
      gVol.selectAll("*").remove();
      st.vpts = [];
      if (!st.vv || !st.volAgg || !st.V) return;
      var vv = st.vv, agg = st.volAgg, V = st.V;
      var nL = agg.nL, i;

      // -log10(p), with a perfectly separated term clamped rather than sent
      // to infinity.
      var ylog = new Array(nL), maxY = 1;
      for (i = 0; i < nL; i++) {
        var p = agg.p[i];
        var v = (p > 0) ? -Math.log10(p) : 6;
        if (!isFinite(v)) v = 6;
        ylog[i] = v;
        if (v > maxY) maxY = v;
      }
      var maxAbs = 1;
      for (i = 0; i < nL; i++) maxAbs = Math.max(maxAbs, Math.abs(agg.rd[i]));
      maxAbs = maxAbs * 1.18;

      var xs = d3.scaleLinear().domain([-maxAbs, maxAbs])
                 .range([V.x0, V.x0 + V.w]);
      var ys = d3.scaleLinear().domain([0, maxY * 1.15])
                 .range([V.top + V.h, V.top]);
      // Area, not radius, carries the subject count: a term seen in two
      // subjects must not look as commanding as one seen in fifty.
      var maxN = 1;
      for (i = 0; i < nL; i++) maxN = Math.max(maxN, agg.cells[i]);
      var rs = d3.scaleSqrt().domain([0, maxN]).range([2.4, 11]);

      gTag.append("text").attr("x", V.x0).attr("y", V.top - 26)
          .attr("fill", PAL.dim).style("font-size", "10px")
          .style("letter-spacing", "0.07em")
          .text("AGGREGATE — " + String(one(vv.label)).toUpperCase() +
                " · RISK DIFFERENCE");
      gVol.append("text").attr("x", V.x0).attr("y", V.top - 12)
          .attr("fill", PAL.dim).style("font-size", "9.5px")
          .text(String(one(vv.comp)) + " minus " + String(one(vv.ref)) +
                " · n=" + one(vv.nComp) + " vs " + one(vv.nRef) +
                (one(vv.dropped) > 0
                   ? " · " + one(vv.dropped) + " term(s) below n=" +
                     one(vv.minN) + " not shown" : ""));

      // frame and guides
      gVol.append("rect").attr("x", V.x0).attr("y", V.top)
          .attr("width", V.w).attr("height", V.h)
          .attr("fill", "none").attr("stroke", PAL.rule);
      var x0line = xs(0);
      gVol.append("line").attr("x1", x0line).attr("x2", x0line)
          .attr("y1", V.top).attr("y2", V.top + V.h)
          .attr("stroke", PAL.dim).attr("stroke-opacity", 0.5)
          .attr("stroke-dasharray", "3 3");
      var aLev = one(vv.alpha) || 0.05;
      var yA = ys(-Math.log10(aLev));
      if (yA > V.top && yA < V.top + V.h) {
        gVol.append("line").attr("x1", V.x0).attr("x2", V.x0 + V.w)
            .attr("y1", yA).attr("y2", yA)
            .attr("stroke", PAL.zone).attr("stroke-opacity", 0.55)
            .attr("stroke-dasharray", "4 4");
        gVol.append("text").attr("x", V.x0 + V.w - 3).attr("y", yA - 4)
            .attr("text-anchor", "end").attr("fill", PAL.zone)
            .style("font-size", "9px").text("p = " + aLev);
      }

      xs.ticks(6).forEach(function (t) {
        gVol.append("text").attr("x", xs(t)).attr("y", V.top + V.h + 13)
            .attr("text-anchor", "middle").attr("fill", PAL.dim)
            .style("font-size", "9px")
            .text((t > 0 ? "+" : "") + d3.format("~g")(t));
      });
      ys.ticks(4).forEach(function (t) {
        if (t === 0) return;
        gVol.append("text").attr("x", V.x0 - 7).attr("y", ys(t) + 3)
            .attr("text-anchor", "end").attr("fill", PAL.dim)
            .style("font-size", "9px").text(d3.format("~g")(t));
      });
      gVol.append("text").attr("x", V.x0 + V.w / 2).attr("y", V.top + V.h + 30)
          .attr("text-anchor", "middle").attr("fill", PAL.dim)
          .style("font-size", "9.5px")
          .text("RISK DIFFERENCE (PERCENTAGE POINTS)");
      gVol.append("text")
          .attr("transform", "translate(" + (V.x0 - 32) + "," +
                (V.top + V.h / 2) + ") rotate(-90)")
          .attr("text-anchor", "middle").attr("fill", PAL.dim)
          .style("font-size", "9.5px").text("-LOG10(P)");

      for (i = 0; i < nL; i++) {
        (function (t) {
          var cx = xs(agg.rd[t]), cy = ys(ylog[t]), r = rs(agg.cells[t]);
          var g = gVol.append("g");

          g.append("circle").attr("cx", cx).attr("cy", cy).attr("r", r)
              .attr("fill", PAL.data).attr("fill-opacity", 0.16)
              .attr("stroke", PAL.data).attr("stroke-opacity", 0.55);

          // The selected share fills the disc from the bottom up.
          var cid = "lkv-" + el.id + "-" + t;
          var clip = defs.append("clipPath").attr("id", cid).append("rect")
              .attr("x", cx - r - 1).attr("y", cy + r)
              .attr("width", 2 * r + 2).attr("height", 0);
          var fill = g.append("circle").attr("cx", cx).attr("cy", cy)
              .attr("r", r).attr("fill", PAL.select)
              .attr("clip-path", "url(#" + cid + ")");

          var hit = g.append("circle").attr("cx", cx).attr("cy", cy)
              .attr("r", Math.max(r, 7)).attr("fill", "transparent")
              .style("cursor", "pointer").attr("tabindex", 0)
              .attr("role", "button")
              .attr("aria-label", "Select " + agg.cells[t] + " subjects with " +
                    agg.levels[t])
              .on("click", function () { pickTerm(t); })
              .on("keydown", function (ev) {
                if (ev.key === "Enter" || ev.key === " ") {
                  ev.preventDefault(); pickTerm(t);
                }
              });
          hit.append("title").text(
            agg.levels[t] + "\n" +
            one(vv.comp) + ": " + agg.cComp[t] + "/" + one(vv.nComp) + "\n" +
            one(vv.ref) + ": " + agg.cRef[t] + "/" + one(vv.nRef) + "\n" +
            "risk difference: " + d3.format("+.1f")(agg.rd[t]) + " pts\n" +
            "p = " + d3.format(".3g")(agg.p[t]));

          st.vpts.push({ t: t, cx: cx, cy: cy, r: r, clip: clip,
                         fill: fill, lab: null, total: agg.cells[t] });
        })(i);
      }

      // Label the terms that separate the arms most sharply, in a second pass
      // so a label can be skipped when its box would collide with one already
      // placed or run outside the panel. Overlapping labels on a volcano are
      // worse than absent ones: they misattribute a term to a neighbouring
      // point.
      var byIx = {};
      st.vpts.forEach(function (p) { byIx[p.t] = p; });
      var order = d3.range(nL).sort(function (a, b) { return ylog[b] - ylog[a]; });
      var boxes = [];
      order.slice(0, 8).forEach(function (t) {
        var p = byIx[t];
        if (!p) return;
        var txt = gVol.append("text").attr("x", p.cx).attr("y", p.cy - p.r - 5)
            .attr("text-anchor", "middle").attr("fill", PAL.dim)
            .style("font-size", "9px").text(agg.levels[t]);
        var w;
        try { w = txt.node().getComputedTextLength(); } catch (e) { w = 0; }
        if (!w) w = String(agg.levels[t]).length * 5;
        var box = { x0: p.cx - w / 2 - 3, x1: p.cx + w / 2 + 3,
                    y0: p.cy - p.r - 15, y1: p.cy - p.r - 1 };
        var clash = box.x0 < V.x0 || box.x1 > V.x0 + V.w || box.y0 < V.top;
        for (var q = 0; !clash && q < boxes.length; q++) {
          var b = boxes[q];
          clash = !(box.x1 < b.x0 || box.x0 > b.x1 ||
                    box.y1 < b.y0 || box.y0 > b.y1);
        }
        if (clash) { txt.remove(); return; }
        boxes.push(box);
        p.lab = txt;
      });
    }

    function drawTable() {
      tableWrap.selectAll("*").remove();
      if (!st.tv) { tableWrap.style("display", "none"); return; }
      tableWrap.style("display", "block").style("border-top", "1px solid " + PAL.rule);
      st.tableNote = tableWrap.append("div")
          .style("padding", "12px 16px").style("color", PAL.dim).style("font-size", "11px");
      var sc = tableWrap.append("div").style("max-height", "230px").style("overflow-y", "auto");
      var tbl = sc.append("table").style("width", "100%")
          .style("border-collapse", "collapse").style("font-size", "12px");
      var thr = tbl.append("thead").append("tr");
      arr(st.tv.labels).forEach(function (lab) {
        thr.append("th").text(lab).style("position", "sticky").style("top", "0")
            .style("background", PAL.ground).style("text-align", "left")
            .style("font-weight", "500").style("font-size", "9.5px")
            .style("letter-spacing", "0.06em").style("text-transform", "uppercase")
            .style("color", PAL.dim).style("padding", "8px 16px")
            .style("border-bottom", "1px solid " + PAL.rule);
      });
      st.tbody = tbl.append("tbody");
    }

    return {
      renderValue: function (x) {
        st.x = x;
        st.n = one(x.n) || 0;
        st.has = false; st.selCount = 0; st.source = "none"; st.drillG = null;
        st.mask = new Uint8Array(st.n);
        st.selIdx = new Int32Array(st.n);

        var opt = x.options || {};
        if (opt.palette) {
          for (var k in opt.palette) {
            if (!Object.prototype.hasOwnProperty.call(opt.palette, k)) continue;
            if (k === "arms") ARM_COLS = arr(opt.palette.arms);
            else PAL[k] = one(opt.palette[k]);
          }
        }
        root.style("background", PAL.ground).style("color", PAL.text);

        var views = arr(x.views);
        st.pv = views.filter(function (v) { return v.type === "points"; })[0] || null;
        st.bv = views.filter(function (v) { return v.type === "bars"; })[0] || null;
        st.hv = views.filter(function (v) { return v.type === "hist"; })[0] || null;
        st.tv = views.filter(function (v) { return v.type === "table"; })[0] || null;
        st.vv = views.filter(function (v) { return v.type === "volcano"; })[0] || null;

        st.facets = (st.pv && st.pv.facetLevels) ? {
          col: one(st.pv.facet),
          levels: arr(st.pv.facetLevels),
          rowCol: one(st.pv.facetRow),
          rowLevels: st.pv.facetRowLevels ? arr(st.pv.facetRowLevels) : null,
          index: Int32Array.from(arr(st.pv.facetIndex))
        } : null;

        st.barAgg  = st.bv ? aggFromBars(st.bv, null) : null;
        st.histAgg = st.hv ? aggFromHist(st.hv) : null;
        st.volAgg  = st.vv ? aggFromVolcano(st.vv) : null;

        var mode = one(opt.pointRenderer) || "auto";
        var thr = one(opt.canvasThreshold) || 6000;
        st.useCanvas = mode === "canvas" || (mode === "auto" && st.n > thr);
        computeLayout();
        drawScatterFrame();
        // drawScatterFrame decides whether a context layer is worth drawing,
        // so the canvas visibility is settled after it, not before.
        canvas.style("display", (st.useCanvas || st.ghost) ? "block" : "none");
        paintGhosts();
        drawBars();
        drawHist();
        drawVolcano();
        drawTable();
        installBrushes();

        var lines = [];
        if (opt.caption)    lines.push(one(opt.caption));
        if (opt.provenance) lines.push(one(opt.provenance));
        footer.style("display", lines.length ? "block" : "none");
        footer.selectAll("div").remove();
        lines.forEach(function (t) { footer.append("div").text(t); });

        render();

        // The figure is content-sized: its height follows the layout and the
        // rendered width, neither of which R can know when it picks a height.
        // Letting the container hug the content avoids a dead band whenever
        // that estimate overshoots.
        el.style.height = "auto";
      },

      resize: function (w, h) {
        if (st.useCanvas) paintCanvas();
        else if (st.ghost) paintGhosts();
      }
    };
  }
});
