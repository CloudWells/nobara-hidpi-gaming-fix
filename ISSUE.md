# X11 games get garbage refresh (19.92 Hz) on high-refresh HiDPI monitors — root cause + tested fix

**System:** Nobara 44 (GNOME Edition), kernel 7.2.0-200.nobara.fc44, GNOME Shell/mutter 50.4-1.fc44, xorg-x11-server-Xwayland 24.1.11-1.fc44, NVIDIA 595.91.07 open kernel module (RTX 5070 Ti), Wayland session.
**Monitors (all on the NVIDIA GPU via DisplayPort):** Samsung Odyssey G81SF 32" 3840×2160@240 at 166.67% scale (primary) + 2× Xiaomi Mi Monitor 27" 2560×1440@180 at 133.33% (one rotated 270°).
**`org.gnome.mutter experimental-features`:** `['scale-monitor-framebuffer', 'xwayland-native-scaling']` — the bug requires fractional scaling with Xwayland native scaling enabled.

## Bug

With fractional scaling + `xwayland-native-scaling`, mutter advertises scaled outputs to X11 clients (logical×2). For a 4K 240 Hz monitor at 166.67% that emulated mode is 4608×2592, and Xwayland synthesizes its RandR timings via full-blanking CVT (`hw/xwayland/xwayland-cvt.c`, all `xwayland_cvt()` call sites pass `reduced=FALSE`). Required pixel clock:

```
htotal × vtotal × refresh = 6528 × 2990 × 239.996 Hz = 4.684 GHz
```

RandR's `dotClock` is CARD32 (ceiling ≈ 4.295 GHz). The conversion

```c
modeinfo->dotClock = libxcvt_mode_info->dot_clock * 1000.0;   /* uint64 kHz → CARD32 Hz */
```

wraps: 4.684e9 − 2³² = 389 MHz. Observed on stock packages:

```
4608x2592 (0x499) 388.783MHz  ... total 6528 × 2990  → clock 19.92Hz
```

Sanity check: (388.783e6 + 2³²) / (6528×2990) = 239.96 Hz — exact. Every X11/Proton game on such a monitor sees 19.92 Hz: refresh selectors show "N/A", framerates cap at 60. Any 4K≥240 Hz panel at fractional scale reproduces this; lower-clock monitors (1440p@180) stay under the ceiling, masking the bug on most setups.

## Fix (tested)

Guard the CVT generation: if the clock would overflow CARD32, retry with reduced blanking; if even that overflows, fall back to zero-blanking synthetic timings that preserve the refresh value.

```diff
--- a/hw/xwayland/xwayland-cvt.c
+++ b/hw/xwayland/xwayland-cvt.c
@@ -39,6 +39,32 @@
     libxcvt_mode_info =
         libxcvt_gen_mode_info(hdisplay, vdisplay, vrefresh, reduced, interlaced);
 
+    /* RandR's dotClock is a CARD32 in Hz, a hard ceiling of ~4.295 GHz.
+     * A full-blanking CVT mode for a large, high-refresh mode (e.g. an
+     * emulated mode for a scaled 4K 240Hz output) can exceed it; the
+     * conversion below would then wrap around and advertise a garbage
+     * refresh rate (e.g. 19.92 Hz instead of 240 Hz) to X11 clients.
+     * Retry with reduced blanking; should even that overflow, fall back
+     * to synthetic zero-blanking timings preserving the refresh rate.
+     */
+    if (!reduced && libxcvt_mode_info->dot_clock > 0xffffffffull / 1000) {
+        free(libxcvt_mode_info);
+        libxcvt_mode_info =
+            libxcvt_gen_mode_info(hdisplay, vdisplay, vrefresh, TRUE, interlaced);
+    }
+
+    if (libxcvt_mode_info->dot_clock > 0xffffffffull / 1000) {
+        libxcvt_mode_info->hsync_start = hdisplay;
+        libxcvt_mode_info->hsync_end   = hdisplay;
+        libxcvt_mode_info->htotal      = hdisplay;
+        libxcvt_mode_info->vsync_start = vdisplay;
+        libxcvt_mode_info->vsync_end   = vdisplay;
+        libxcvt_mode_info->vtotal      = vdisplay;
+        libxcvt_mode_info->dot_clock   =
+            (uint64_t) ((double) hdisplay * vdisplay * vrefresh / 1000.0);
+    }
+
     modeinfo->width      = libxcvt_mode_info->hdisplay;
```

Result on the same machine, same 166.67% scale, rebuilt 24.1.11 package:

```
before:  4608x2592  388.783MHz  total 6528×2990  → 19.92 Hz
after:   4608x2592  3334.000MHz total 4768×2914  → 239.96 Hz   (reduced-blanking path)
```

Games immediately see the correct refresh at fractional scale. The patch is against `xwayland-24.1.11` and applies to the Nobara/Fedora spec as-is (mbox-formatted for `%autosetup -S git_am`). This belongs upstream in xorg/xserver too — I can file it there; carrying it downstream fixes Nobara gamers today.

## Related findings (for the record)

- **mutter physical layout mode** eliminates the whole emulation layer (X11 clients see true native modes; also fixes cursor breakage in exclusive-fullscreen games on scaled monitors). We experimentally lifted the two fractional-scale gates (`META_MONITOR_SCALES_CONSTRAINT_NO_FRAC` in `meta-monitor-manager-native.c`, the `G_APPROX_VALUE` check in `meta-monitor-config-manager.c`): validation then passes, but the renderer has no fractional-scale path in physical mode — UI draws at 1:1. So the gate masks missing renderer support rather than a policy choice; true "native for X11 + fractional UI" needs that renderer work in mutter.
- **Games starting on the wrong monitor** (known Proton issues #720/#7717): in practice engines gravitate to the topmost monitor of the virtual desktop. Workaround that fixed it here: arrange the layout so the primary gaming monitor is the only one touching y=0 (side monitors shifted down by a few logical px). Together with the dotClock fix this makes multi-monitor HiDPI gaming work out of the box.

## Repro

1. GNOME Wayland, 4K 240 Hz monitor at any fractional scale (150/166%).
2. `xrandr --verbose` inside Xwayland → emulated mode reports ~20 Hz on stock packages.
3. Any Proton game: refresh shows N/A or caps at 60.
