// Device Monitor slide-in case: no carrier PCB. The ESP32-C3 SuperMini slides
// into wall grooves and the GY-346 (ADXL346) module sits on floor rails. They are
// joined by four wires soldered straight to the pads (3V3, GND, GPIO5 = SDA,
// GPIO6 = SCL), with no headers.
//
// Layout (x from the USB-C end):
//   - SuperMini, USB-C end first. Its long edges ride on side ledges, with a lip
//     over them further back (the "grooves"). USB-C pokes into a hole in the end wall.
//   - Two lid posts drop in behind the SuperMini's rear corners. Plugging a cable
//     in pushes the board back into them; pulling a cable out pulls the board
//     forward against the end wall. The wires run back between the posts.
//   - GY-346, its pin row facing the SuperMini, on two floor rails (one just behind
//     the pin row's solder tails, one under its rear edge). Two pins on the rear rail
//     come up through its mounting holes, and two lid feet press on the board around
//     the holes (as the solid H1 post on the PCB case).
//   - Ribbon antenna (about 40 x 11 mm) stuck flat to the lid's ceiling, in the
//     strip that the reset tab, the posts and the feet leave clear.
//
// Closure: the same lid as device_monitor_case.scad. Lid skirts slide down inside
// the tray's long walls, and a wedge on each skirt clicks into a divot in the wall.
//
// Assembly:
//   1. Solder the four wires: SuperMini 3V3, GND, 5, 6 to GY-346 VIN, GND, SDA, SCL.
//      About 35 mm each. The SuperMini pads are the first three on each edge at the
//      USB end, so the wires leave from the front of the board and run back over it.
//   2. Hold the SuperMini flat, USB-C forward, in the back half of the tray. Put its
//      front edge on the side ledges and slide it forward until the USB-C sits in
//      the end-wall hole. The module hangs off the wires meanwhile.
//   3. Drop the GY-346 onto its two pins, header pads toward the SuperMini, components up.
//   4. Stick the antenna to the ceiling inside the lid (the shallow outline marks
//      its spot). Push the lid straight down until the four wedges click.
//
// Render (from this folder):
//   openscad -o slide_tray.stl -D 'part="tray"' slide_in_case.scad
//   openscad -o slide_lid.stl  -D 'part="lid"'  slide_in_case.scad    (flipped, ceiling on the bed)
//   part="both" (default) is a preview with stand-in parts, "fit" the tray with the
//   parts, "section" a cut through the SuperMini's centre line. The "clash_*" parts
//   must have zero volume: run ./check_case.sh slide_in_case.scad after any change.
//
// Coordinates: x along the case from the USB end, y across, z up from the tray
// floor's top surface, all in the cavity ("inner") unless at_inner() is left off.

part = "both";
$fn = 40;
crush = 0.2;                 // lid feet press this far into the module (0 for the clash check)

// ======================= PARTS (measure yours) =======================
// ESP32-C3 SuperMini. 22.5 x 18 is Brad's tentative measurement (2026-11-14);
// esp_t is the bare PCB, ASSUMED 1.0 until measured.
esp_l = 22.5; esp_w = 18; esp_t = 1.0;
esp_tails = 1.0;             // solder under the board
usb_w = 9; usb_h = 3.2;      // USB-C receptacle on top, at the front edge
usb_overhang = 0.8;          // how far it sticks out past the board's front edge
usb_len = 7.5;
usb_margin = 0.4;
usb_port_w = usb_w + 1;
// RESET (not BOOT: the firmware's double-press reopens the Wi-Fi portal). On the
// SuperMini it is 9 mm from the USB end and 5 mm from one long edge (measured on sm2k).
btn_from_front = 9; btn_from_edge = 5;
btn_top = 2;                 // button top above the board
esp_parts_h = 1.6;           // chip and LDO above the board
// Pads used (from the USB end): 1st-3rd on each edge, 2.36 + 2.54 n from the front,
// 1.38 in from the edge. Nothing may overhang the board within pad_zone of the front.
pad_zone = 9.5;

// GY-346 module: 20.5-21 x 14-14.5 mm (Brad), so the pocket is sized 21 x 14.5. Pin row along a 21 mm edge, 1.27 in.
gy_l = 14.5; gy_w = 21; gy_t = 1.6;
gy_parts_h = 1.2;
gy_tails = 1.0;
// Two mounting holes along the edge opposite the pins, 15 mm apart (Brad). Diameter
// and edge distance are ESTIMATED from a product photo: measure and adjust.
gy_hole_pitch = 15; gy_hole_d = 3.0; gy_hole_in = 2.5;   // centre to the module's rear edge
gy_pin_d = 2.4;

// External ribbon antenna for the SuperMini's u.FL (optional).
antenna = true;
ant_l = 40; ant_w = 11; ant_t = 0.3;

// ======================= SHELL =======================
wall = 2; floor_t = 2; lid_t = 2; corner_r = 2;
fit = 0.2;                   // general FDM clearance
in_w = 23.6;                 // cavity width: the module's 21 plus room for the antenna strip beside the reset tab
in_h = 11;                   // cavity height: USB-C top is ~7.4, plus room to bend the wires

// SuperMini support
esp_z = 3.2;                 // board underside above the floor (clears rails and tails)
ledge_in = 0.8;              // ledges reach this far under the board's long edges (pad tails start 0.88 in)
guide_gap = 0.3;             // board edge to the side guides
lip_in = 0.6;                // lip reach over the board (rear part only, clear of the used pads)
lip_t = 1.2;
lip_gap = 0.3;               // lip above the board's top
front_gap = 0.2;             // board's front edge to the end wall

// Lid posts behind the SuperMini's rear corners
post_d = 3;                  // depth along x
post_over = 1.2;             // how far each covers the board's rear edge
post_gap = 0.3;              // board's rear edge to the posts

// GY-346 support
rail_h = 2.6;                // module underside above the floor (zip-tie slot runs under it)
rail_w = 1.5;
gy_gap = 0.3;
foot_l = 4.5;                // lid feet: square, centred on the module's holes

// Reset tab: a tongue cut into the lid (keyhole outline) with a plunger under its
// round end. Press the lid there to press RESET.
tab_pad_d = 3.6;             // round end, over the button
tab_w = 3;                   // tongue width
tab_len = 12;                // button centre to the tongue's root (toward the back)
tab_t = 1.0;                 // tongue thickness (thinned from inside so it flexes)
tab_slot = 0.6;              // cut around it
plunger_d = 2.4;
btn_gap = 0.5;               // plunger tip above the button at rest

// Skirts, wedges and divots (as device_monitor_case.scad / sump-master-2000)
skirt_t = 1.6; skirt_gap = 0.2;
skirt_z0 = 6.5;              // above the side guides
pad_w = 8; pad_t = 1;
detent = 0.4; detent_clr = 0.1;
bump_p = skirt_gap + detent;
bump_ang = 35; bump_flat = 0.4; bump_round = 0.2;
bump_w = pad_w - 2; seat_w = bump_w + 1;
bump_zc = skirt_z0 + 1.6;

// Zip-tie slot through both long walls, under the module (optional)
strap = true;               // 4.8 mm zip tie (the slot fits between the front rail and the pin bosses)
strap_w = 4.8; strap_h = 2;
strap_slot_w = strap_w + 1; strap_slot_h = strap_h + 0.6;

vent_hole_d = 2.6;
vent_pitch = 4.2;            // along the case
vent_row = 3.6;              // between rows (staggered by half a pitch)
led_hole_d = 2.0; led_pitch = 3;   // LED row along the RESET-side edge
vent_margin = 0.8;           // web left round the tab, posts and feet

// ======================= DERIVED =======================
esp_x0 = front_gap; esp_x1 = esp_x0 + esp_l;
esp_y0 = (in_w - esp_w) / 2; esp_y1 = esp_y0 + esp_w;
esp_top = esp_z + esp_t;
guide_top = esp_top + lip_gap + lip_t;
post_x0 = esp_x1 + post_gap; post_x1 = post_x0 + post_d;
gy_x0 = post_x1 + gy_gap; gy_x1 = gy_x0 + gy_l;
gy_y0 = (in_w - gy_w) / 2; gy_y1 = gy_y0 + gy_w;
gy_top = rail_h + gy_t;
gy_holes = [for (s = [-1, 1]) [gy_x1 - gy_hole_in, in_w / 2 + s * gy_hole_pitch / 2]];
in_l = max(gy_x1 + 1.4, ant_l + 1.5);
// Insertion: the board goes in flat behind the lip, so the lip must end at least
// a board length (plus a little) from the far wall.
strap_x = (gy_x0 + 2.0 + rail_w + gy_holes[0][0] - gy_hole_d / 2 - 1) / 2;
lip_x0 = pad_zone; lip_x1 = in_l - esp_l - 0.5;
usb_y = (esp_y0 + esp_y1) / 2;
usb_z0 = esp_top - usb_margin; usb_z1 = esp_top + usb_h + usb_margin;
btn_xy = [esp_x0 + btn_from_front, esp_y0 + btn_from_edge];
plunger_z0 = esp_top + btn_top + btn_gap;
sk_in0 = skirt_gap + skirt_t; sk_in1 = in_w - skirt_gap - skirt_t;   // skirts' inner faces
ant_y0 = btn_xy[1] + tab_pad_d / 2 + tab_slot + 0.3; ant_y1 = ant_y0 + ant_w;
ant_x0 = (in_l - ant_l) / 2;
snap_x = [6, post_x1 + 5];
out_l = in_l + 2 * wall; out_w = in_w + 2 * wall;

echo(str("slide-in case outside ", out_l, " x ", out_w, " x ", floor_t + in_h + lid_t,
         " mm; cavity ", in_l, " x ", in_w, " x ", in_h));
assert(lip_x1 - lip_x0 >= 4, "no room for the lip: the case is too short to slide the board in");
assert(ant_y1 + 0.3 <= sk_in1, "antenna strip doesn't fit between the reset tab and the skirt");
assert(esp_y0 + post_over < ant_y0, "post A would cover the antenna");
assert(usb_z1 < in_h - 1, "USB opening reaches the ceiling");
assert(guide_top + 0.5 <= skirt_z0, "skirts reach down onto the side guides");
assert(rail_h >= strap_slot_h, "zip tie doesn't fit under the module");
assert(!strap || strap_slot_w <= gy_holes[0][0] - gy_hole_d / 2 - 1 - (gy_x0 + 2.0 + rail_w), "zip-tie slot cuts a rail or a pin boss");

module rbox(l, w, h, r) {
  translate([r, r, 0]) linear_extrude(h) offset(r) square([l - 2 * r, w - 2 * r]);
}
module at_inner() { translate([wall, wall, floor_t]) children(); }
module box(a, b) translate(a) cube(b - a);   // corners a, b (cavity coordinates)

module usb_port_cutter() at_inner() {
  r = (usb_z1 - usb_z0) / 2;
  translate([-wall - 1, usb_y, (usb_z0 + usb_z1) / 2]) hull()
    for (s = [-1, 1]) translate([0, s * (usb_port_w / 2 - r), 0]) rotate([0, 90, 0]) cylinder(r = r, h = wall + 2);
}

// =============== TRAY ===============
module tray() {
  difference() {
    union() {
      difference() {
        rbox(out_l, out_w, floor_t + in_h, corner_r);
        at_inner() cube([in_l, in_w, in_h + 1]);
      }
      at_inner() {
        // SuperMini: side ledges under its long edges, guides beside them, and the
        // lip over them toward the rear (the two halves of each groove).
        for (side = [0, 1]) {
          e = side ? esp_y1 : esp_y0;          // board edge
          s = side ? 1 : -1;                   // outward
          wy = side ? in_w : 0;                // wall face
          box([0, min(wy, e - s * ledge_in), 0], [esp_x1, max(wy, e - s * ledge_in), esp_z]);
          box([0, min(wy, e + s * guide_gap), 0], [esp_x1, max(wy, e + s * guide_gap), guide_top]);
          box([lip_x0, min(wy, e - s * lip_in), esp_top + lip_gap], [lip_x1, max(wy, e - s * lip_in), guide_top]);
        }
        // GY-346: front rail just behind its pin row's tails, rear rail at its rear edge
        for (rx = [gy_x0 + 2.0, gy_holes[0][0] - rail_w / 2])
          box([rx, 0, 0], [rx + rail_w, in_w, rail_h]);
        // locating pins through the module's holes, on bosses joined to the rear rail.
        // They stop under the board's top face: the lid feet press around the holes.
        for (h = gy_holes) translate([h[0], h[1], 0]) {
          cylinder(d = gy_hole_d + 2, h = rail_h);
          cylinder(d = gy_pin_d, h = gy_top - 0.5);
          translate([0, 0, gy_top - 0.5]) cylinder(d1 = gy_pin_d, d2 = gy_pin_d - 0.6, h = 0.3);
        }
      }
    }
    usb_port_cutter();
    at_inner() for (x = snap_x, side = [0, 1]) detent_seat(x, side);
    if (strap) at_inner() translate([strap_x - strap_slot_w / 2, -wall - 1, 0])
      cube([strap_slot_w, out_w + 2, strap_slot_h]);
  }
}

// =============== WEDGES (copied from device_monitor_case.scad) ===============
module bump_profile(grow = 0) {
  run = bump_p / tan(bump_ang);
  offset(delta = grow) offset(r = bump_round) offset(delta = -bump_round)
    polygon([[-0.4, bump_zc - bump_flat / 2 - run - 0.4], [0, bump_zc - bump_flat / 2 - run],
             [bump_p, bump_zc - bump_flat / 2], [bump_p, bump_zc + bump_flat / 2],
             [0, bump_zc + bump_flat / 2 + run], [-0.4, bump_zc + bump_flat / 2 + run + 0.4]]);
}
module on_side(x, side, w) {
  translate([x - w / 2, 0, 0]) rotate([90, 0, 90]) linear_extrude(w)
    if (side) translate([in_w - skirt_gap, 0]) children(); else translate([skirt_gap, 0]) mirror([1, 0]) children();
}
module detent_bump(x, side) on_side(x, side, bump_w) intersection() {
  bump_profile();
  translate([-0.3, 0]) square([10, 100]);
}
module detent_seat(x, side) on_side(x, side, seat_w) bump_profile(detent_clr);

module skirt(side) {
  y0 = side ? sk_in1 : skirt_gap;
  difference() {
    translate([0.2, y0, skirt_z0]) cube([in_l - 0.4, skirt_t, in_h - skirt_z0 + 0.01]);
    for (x = snap_x)
      translate([x - pad_w / 2, side ? y0 - 1 : y0 + pad_t, skirt_z0 - 1])
        cube([pad_w, skirt_t - pad_t + 1, in_h - skirt_z0 + 1]);
  }
  for (x = snap_x) intersection() {
    detent_bump(x, side);
    translate([0, -5, skirt_z0]) cube([in_l, in_w + 10, in_h]);
  }
}

// A block hanging from the ceiling between x0..x1, reaching y_lo..y_hi at z_bot,
// but rooted only at y >= root_y (or <= root_y if flip): a 45 deg corbel steps it
// out under the antenna strip.
module corbel_block(x0, x1, y_lo, y_hi, z_bot, root_y) {
  step = max(0, root_y - y_lo);
  assert(in_h - 0.6 - step > z_bot + 0.5, "corbel too deep for the cavity");
  hull() {
    box([x0, root_y, in_h - 0.6], [x1, y_hi, in_h + 0.01]);
    box([x0, y_lo, z_bot], [x1, y_hi, in_h - 0.6 - step]);
  }
}

// =============== LID (modelled in place; flipped for printing) ===============
module lid() {
  difference() {
    union() {
      translate([0, 0, floor_t + in_h]) rbox(out_l, out_w, lid_t, corner_r);
      at_inner() {
        for (side = [0, 1]) skirt(side);
        // posts behind the SuperMini's rear corners, down to just above the floor.
        // Post A is under the clear strip by the reset tab; post B is beside the
        // antenna, so it is rooted on its skirt and steps out under the antenna.
        box([post_x0, skirt_gap, 0.3], [post_x1, esp_y0 + post_over, in_h + 0.01]);
        corbel_block(post_x0, post_x1, esp_y1 - post_over, sk_in1 + skirt_t, 0.3, ant_y1 + 0.3);
        // feet clamping the module's rear half, either side of the antenna strip
        // over the holes; a bore clears the pin tip
        difference() {
          union() {
            fx0 = gy_holes[0][0] - foot_l / 2; fx1 = gy_holes[0][0] + foot_l / 2;
            box([fx0, max(sk_in0 + 0.3, gy_holes[0][1] - foot_l / 2), gy_top - crush], [fx1, ant_y0 - 0.2, in_h + 0.01]);
            corbel_block(fx0, fx1, gy_holes[1][1] - foot_l / 2, sk_in1 + skirt_t, gy_top - crush, ant_y1 + 0.3);
          }
          for (h = gy_holes) translate([h[0], h[1], gy_top - 1]) cylinder(d = gy_hole_d - 0.2, h = 1.6);
        }
      }
    }
    // reset tab: slot round the tongue, and the tongue thinned from inside
    at_inner() {
      translate([0, 0, in_h - 1]) linear_extrude(lid_t + 2) difference() {
        offset(delta = tab_slot) tab_outline();
        tab_outline();
      }
      translate([0, 0, in_h - 0.01]) linear_extrude(lid_t - tab_t + 0.01) tab_outline();
    }
    // antenna outline: a 0.2 mm recess in the ceiling to stick it into
    if (antenna) at_inner() box([ant_x0 - 0.3, ant_y0 - 0.1, in_h - 0.01], [ant_x0 + ant_l + 0.3, ant_y1 + 0.1, in_h + 0.2]);
    vents();
  }
  // plunger under the tab's round end
  at_inner() translate([btn_xy[0], btn_xy[1], plunger_z0]) cylinder(d = plunger_d, h = in_h + lid_t - tab_t - plunger_z0 + 0.01);
}
module tab_outline() {
  translate(btn_xy) circle(d = tab_pad_d);
  translate([btn_xy[0], btn_xy[1] - tab_w / 2]) square([tab_len, tab_w]);
}

// Vent holes: a staggered grid over the whole lid (the onboard LED shows through),
// kept clear of the reset tab, the roots of the posts and feet, and the skirts.
// The middle rows open onto the antenna, which sticks to the webbing between them.
module vents() at_inner() {
  m = vent_margin + vent_hole_d / 2;
  led_y = sk_in0 + 0.7 + led_hole_d / 2;
  fx0 = gy_holes[0][0] - foot_l / 2; fx1 = gy_holes[0][0] + foot_l / 2;
  keep_out = [
    [btn_xy[0] - tab_pad_d / 2 - tab_slot, btn_xy[1] - tab_pad_d / 2 - tab_slot, btn_xy[0] + tab_len + tab_slot, btn_xy[1] + tab_pad_d / 2 + tab_slot],
    [post_x0, 0, post_x1, esp_y0 + post_over], [post_x0, ant_y1 + 0.3, post_x1, in_w],
    [fx0, 0, fx1, ant_y0 - 0.2], [fx0, ant_y1 + 0.3, fx1, in_w],
    [esp_x0, led_y - led_hole_d / 2, esp_x1, led_y + led_hole_d / 2]];
  rows = floor((sk_in1 - sk_in0 - 2 * m) / vent_row) + 1;
  y0 = (in_w - (rows - 1) * vent_row) / 2;
  for (j = [0 : rows - 1], x = [vent_pitch / 2 * (j % 2) + 2.5 : vent_pitch : in_l - 2.5]) {
    y = y0 + j * vent_row;
    hits = [for (r = keep_out) if (x > r[0] - m && x < r[2] + m && y > r[1] - m && y < r[3] + m) 1];
    if (len(hits) == 0) translate([x, y, in_h - 1]) cylinder(d = vent_hole_d, h = lid_t + 2, $fn = 24);
  }
  // LED row: smaller holes along the SuperMini's RESET-side edge, where the LED is,
  // between the skirt and the reset tab.
  assert(led_y + led_hole_d / 2 + 0.7 <= btn_xy[1] - tab_pad_d / 2 - tab_slot, "LED row hits the reset tab");
  for (x = [esp_x0 + 1.5 : led_pitch : esp_x1 - 1]) translate([x, led_y, in_h - 1]) cylinder(d = led_hole_d, h = lid_t + 2, $fn = 20);
}

// =============== stand-in parts (preview and clash check) ===============
module esp_dummy() at_inner() {
  color("royalblue") box([esp_x0, esp_y0, esp_z], [esp_x1, esp_y1, esp_top]);
  color("dimgray") box([esp_x0 + 11, esp_y0 + 4, esp_top], [esp_x1 - 1, esp_y1 - 4, esp_top + esp_parts_h]);
  color("gold") for (e = [esp_y0 + 1.38, esp_y1 - 1.38])
    box([esp_x0 + 1.5, e - 0.5, esp_z - esp_tails], [esp_x1 - 1.5, e + 0.5, esp_z]);
  color("white") for (by = [btn_xy[1], esp_y1 - btn_from_edge])
    box([btn_xy[0] - 1.5, by - 1.75, esp_top], [btn_xy[0] + 1.5, by + 1.75, esp_top + btn_top]);
  color("silver") translate([esp_x0 - usb_overhang, usb_y, esp_top + usb_h / 2]) hull()
    for (s = [-1, 1]) translate([0, s * (usb_w / 2 - usb_h / 2), 0]) rotate([0, 90, 0]) cylinder(d = usb_h, h = usb_len);
}
module gy_dummy() at_inner() {
  color("purple") difference() {
    box([gy_x0, gy_y0, rail_h], [gy_x1, gy_y1, gy_top]);
    for (h = gy_holes) translate([h[0], h[1], rail_h - 1]) cylinder(d = gy_hole_d, h = gy_t + 2);
  }
  color("gray") box([gy_x0 + 3, in_w / 2 - 3, gy_top], [gy_x0 + 7, in_w / 2 + 3, gy_top + gy_parts_h]);
  color("gold") box([gy_x0 + 0.77, gy_y0 + 1, rail_h - gy_tails], [gy_x0 + 1.77, gy_y1 - 1, rail_h]);
}
// The four wires: up from the pads, back over the board between the posts, down to the pins.
module wires_dummy() at_inner() color("red") for (y = [esp_y0 + 1.38 + 1, esp_y0 + 3.4, esp_y1 - 3.4, esp_y1 - 1.38 - 1])
  translate([0, y, 0]) {
    box([3.5, -0.4, esp_top + 0.5], [gy_x0 + 1.3, 0.4, esp_top + 1.3]);
    box([gy_x0 + 0.5, -0.4, gy_top + 0.2], [gy_x0 + 1.3, 0.4, esp_top + 1.3]);
  }
module antenna_dummy() if (antenna) at_inner() color("orange")
  box([ant_x0, ant_y0, in_h + 0.2 - ant_t], [ant_x0 + ant_l, ant_y1, in_h + 0.2]);
module tie_dummy() if (strap) color("black") at_inner()
  translate([strap_x - strap_w / 2, -wall - 0.5, 0.2]) cube([strap_w, out_w + 1, strap_h - 0.4]);
module everything_else() { esp_dummy(); gy_dummy(); wires_dummy(); antenna_dummy(); tie_dummy(); }

// Everything above is laid out with the RESET side at low y. Looking down on the
// SuperMini (USB-C to the left), RESET is on the far side, as on the carrier
// (KiCad (9, 8), see device_monitor_case.scad's bxy()), so the output is mirrored
// across the case's centre line.
module reset_side_up() translate([0, out_w, 0]) mirror([0, 1, 0]) children();

reset_side_up() {
  if (part == "none") { }
  else if (part == "tray") tray();
  else if (part == "lid") translate([0, out_w, floor_t + in_h + lid_t]) rotate([180, 0, 0]) lid();
  else if (part == "clash_lid_tray") intersection() { tray(); lid(); }
  else if (part == "clash_lid_parts") intersection() { lid(); everything_else(); }
  else if (part == "clash_tray_parts") intersection() { tray(); everything_else(); }
  else if (part == "closed") { color("steelblue") tray(); color("lightgray") lid(); }
  else if (part == "fit") { tray(); everything_else(); }
  else if (part == "section") intersection() {
    union() { tray(); lid(); everything_else(); }
    translate([-5, wall + usb_y, -10]) cube([200, 50, 60]);
  }
  else { color("steelblue") tray(); color("white", 0.35) lid(); everything_else(); }
}
