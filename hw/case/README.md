# Device Monitor case

<img src="case-closed.png" alt="Closed case" width="420"/> <img src="case-fit.png" alt="Carrier in the tray" width="420"/>

A two-part printed case (tray + lid) for the device monitor carrier PCB
(`../devmon_carrier.kicad_pcb`: ESP32-C3 SuperMini, GY-346 / ADXL346 module and one
bulk capacitor). Outside it is **52.3 x 31 x 23 mm**.

| File | What it is |
|---|---|
| `device_monitor_case.scad` | The OpenSCAD source. Everything is a parameter at the top. |
| `tray.stl`, `lid.stl` | Ready to print. The lid is exported upside down (ceiling on the bed). |
| `check_case.sh` | Renders the clash checks: lid against tray, and each against the board and its parts. Run it after any change. |
| `case-*.png` | Renders: closed, carrier in the tray, the lid from inside, a section. |

It is built from the author's two earlier cases:

- From the **RF ceiling fan remote** case
  ([fan_dongle_case.scad](https://github.com/bradrblack/rf-ceiling-fan-remote/blob/main/hw/case/fan_dongle_case.scad)):
  no screws. Printed standoffs with pins go through the carrier's holes, and caps
  (hook posts) hang from the lid to clamp the board. A guide tube hangs over the
  RESET button for a paperclip. The USB-C connector passes through the lid's end
  wall, and the tray's USB end is only a low stub wall below it. The USB and RESET
  positions are the same as on that case (same SuperMini footprint and position).
- From **Sump Master 2000**
  ([sump_case.scad](https://github.com/bradrblack/sump-master-2000/blob/main/hw/case/sump_case.scad)):
  the wedge-and-divot closure in place of a friction fit. The lid has two skirts that
  slide down inside the tray's walls. Each skirt is thinned to 1 mm at two pockets, and
  a rounded wedge on each pocket clicks into a divot in the tray wall. Closed,
  nothing is under load (0.1 mm clearance), so the fit doesn't creep loose.

<img src="case-section.png" alt="Section along the board" width="600"/>

## How the board is held

| Hole (KiCad x, y) | Tray | Lid |
|---|---|---|
| H5 (3.75, 8), H6 (3.75, 16) | standoff + pin | nothing (the ESP module is above them); these take the USB plug's push |
| H1 (24.4, 12) | standoff, bored for the pin's tip | 3.4 mm post down to the board with a locating pin through the hole |
| H2 (41.5, 17) | standoff + pin | hollow 4.5 mm cap over the pin, 0.3 mm above the board |

The board sits on 3 mm standoffs, so its solder tails clear the floor. The lid's
H1 pin holds the board in place while you assemble it (below). Once closed, the H1 post
and H2 cap clamp the board against its standoffs, so the accelerometer is coupled to the
case.

## Printing

- PLA or PETG, 0.2 mm layers, 3 walls, no supports.
- **Tray:** floor on the bed. **Lid:** as exported, ceiling on the bed, skirts and posts
  pointing up.
- Test the fit before using the case: the wedge (`detent`, 0.4 mm) and the pins
  (`pin_d`, 2.2 mm in 2.5 mm holes) are the values to adjust. If the lid clicks too
  hard, lower `detent` to 0.3. If it falls off, raise it to 0.5.
- A light-coloured lid lets the onboard status LED show through the vent holes.

## Assembly

The USB-C connector sits inside the lid's end wall, so the board goes into the lid
first (as on the fan case):

1. Lay the lid on the table, ceiling down.
2. Hold the carrier parts side down, tilted slightly, and slide the USB-C connector into
   the port in the lid's end wall. Then lower the far end so the H1 hole drops over the
   lid's pin. The board now rests on the H1 post, with the H2 cap just above it.
3. Turn the tray upside down and push it straight down over the lid until all four
   wedges click. Its pins go through H5, H6 and H2.

To open it, pull the tray and lid apart firmly. The 35-degree wedge flanks let go
without tools.

**Reset:** push a paperclip or toothpick straight down through the hole near the USB end.
It lands on the SuperMini's RESET button (pressing it twice reopens the Wi-Fi setup
portal; see the main README).

## Mounting

The underside is flat, so it couples well to whatever it sits on. Use VHB tape on a
washer, dryer or AC cabinet. For a pipe, such as a sump pump discharge, thread one zip tie
(up to 5.5 x 2 mm) through the slot at floor level. It crosses the floor under the
carrier, where the board has no solder tails, and comes out the other side. Set
`strap = false` for a case without the slot.

## Changing it

The board numbers (`pcb_l`, `holes`, part positions and heights) are copied from
`../tools/gen_carrier.py`. If the board changes, update them and run:

```
./check_case.sh                    # each line must say ok
openscad --export-format binstl -o tray.stl -D 'part="tray"' device_monitor_case.scad
openscad --export-format binstl -o lid.stl  -D 'part="lid"'  device_monitor_case.scad
```

The cavity height follows the tallest part. The 12.5 mm capacitor sets it now. A
shorter capacitor (`cap_h`) makes the whole case shorter. `part="section"` and
`part="fit"` are useful previews.
