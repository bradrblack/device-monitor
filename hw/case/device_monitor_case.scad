// Device Monitor case: tray + lid for the carrier in ../devmon_carrier.kicad_pcb
//
// Built from the two earlier cases by the same author:
//   - github.com/bradrblack/rf-ceiling-fan-remote  hw/case/fan_dongle_case.scad
//       standoff pins through the carrier's holes (no screws), caps (hook posts)
//       hanging from the lid that clamp the board, the reset-button guide tube,
//       and the USB-C port passing through the LID's end wall (the tray's USB end
//       is only a low stub wall below the port).
//   - github.com/bradrblack/sump-master-2000  hw/case/sump_case.scad
//       the closure: lid skirts slide down inside full-height tray walls, and a
//       rounded wedge on each skirt pocket clicks into a divot (seat) in the tray
//       wall. This replaces the fan case's friction fit / snap tabs.
// The carrier is the sump-master-2000 carrier cut down to the ESP32-C3 SuperMini,
// the GY-346 (ADXL346) module and one bulk capacitor, so the case is much shorter.
//
// Closure: closing, each wedge rides down the tray wall with its 1 mm pocket
// flexed 0.4 mm and drops into its divot; closed, nothing is under load (0.1 mm
// clearance), so the fit doesn't creep loose. The 35 deg flanks let a firm pull
// open it again. No slits or free tabs to snap off.
//
// Assembly (as on the fan case, because the USB-C connector sits inside the
// lid's end wall and nothing rigid can be lowered over it):
//   1. Lay the lid on the table, ceiling down.
//   2. Put the carrier in parts side down: slide the USB-C connector into the
//      port in the lid's end wall, then let the board drop onto the lid's
//      locating pin (H1). The reset tube and the clamp posts now sit on it.
//   3. Turn the tray upside down and push it straight down over the lid until
//      the four wedges click. Its pins go through the other holes.
//   Opening: pull the tray and lid apart firmly (or flex the skirt pockets in
//   with a thumbnail through the vent holes).
//
// Render (from this folder):
//   openscad -o tray.stl -D 'part="tray"' device_monitor_case.scad
//   openscad -o lid.stl  -D 'part="lid"'  device_monitor_case.scad   (exported flipped, ceiling on the bed)
//   part="both" (default) is an assembled preview with stand-in parts, "closed" the
//   two printed parts only, "fit" the tray with the carrier and its parts, "section"
//   cuts it open along the board's centre line. The three "clash_*" parts must have
//   zero volume: run ./check_case.sh after any change.
//
// Coordinates: x along the case from the USB-C end, y across, z up from the
// tray floor's top surface. "Inner" = the cavity. Board positions are KiCad
// coordinates (x right, y down, origin at the board's top-left corner, USB edge
// at x = 0) and are converted with bxy().

part = "both";
$fn = 40;

// ======================= CARRIER (from the KiCad board) =======================
// Keep these in step with hw/devmon_carrier.kicad_pcb (hw/tools/gen_carrier.py).
// Values below are the v1.0 board's.
pcb_l = 47.0;                // board length (x)
pcb_w = 24.0;                // board width (y)
pcb_t = 1.6;

// Case-pin holes: [kicad x, kicad y, role]. All are 2.5 mm NPTH.
//   "pin"    tray standoff + locating pin only (nothing above: the ESP module covers H5/H6)
//   "hook"   tray standoff + pin, and a hollow cap (hook post) from the lid clamps the board
//   "lidpin" the pin hangs from the lid (a post down to the board with a pin through the
//            hole); the tray boss under it is bored for the pin's tip. It locates the board
//            in the lid during assembly step 2, and clamps it once closed.
holes = [
  [ 3.75,  8.0, "pin"],      // H5  under the ESP32, USB end: takes the USB plug's push
  [ 3.75, 16.0, "pin"],      // H6
  [24.4,  12.0, "lidpin"],   // H1  between the ESP32 and the ADXL346 header
  [41.5,  17.0, "hook"],     // H2  far end, beside the cap (nothing within 5.6 mm)
];

// Parts, for the clash check and the preview (KiCad coordinates, heights above the
// board's top face). Keep in step with the PCB.
esp_xy   = [11.25, 12];      // U1 centre (SuperMini footprint origin)
esp_size = [22.5, 18];       // module board
esp_hdr  = 2.54;             // header spacer under the module
esp_pcb  = 1.2;              // module PCB thickness
esp_parts_h = 1.6;           // chip / LDO / buttons above the module PCB (buttons ~1.5-2: see btn_*)
gy_x0 = 28.1 - 1.27;         // GY-346 lies flat from its J1 header row toward +x (as on sm2k)
gy_size = [9, 20];           // GY-346 board (user-measured on sm2k)
gy_z  = 2.5;                 // module soldered on its own header, board 2.5 mm up
gy_parts_h = 1.2;            // ADXL346 + regulator on top of the module
j1_xy = [28.1, 3.11];        // J1 pin 1, 1x8 down the board (y)
cap_xy = [41.5, 6.0];        // C1 body centre (CP_Radial_D8.0 P2.5, leads at x 40.25 / 42.75)
cap_d = 8;                   // envelope: 470 uF/6.3 V is 6.3-8 x 11-12; 100 uF/10 V is 5 x 11
cap_h = 12.5;

// ======================= ESP32-C3 SuperMini USB-C and RESET =======================
// Same module position, USB-C overhang and RESET spot as the fan and sump cases.
usb_h      = 3.2;            // connector height above the module PCB
usb_w      = 9;
usb_len    = 7.5;            // from 1 mm past the board edge
usb_margin = 0.4;
usb_port_w = usb_w + 1;      // opening: bare connector + 0.5 each side (fan case)
// RESET (not BOOT: the firmware's double-press reopens the WiFi portal):
// user-measured on sm2k, 9 mm from the module's USB end, 5 mm from its side.
btn_kicad = [9.0, 8.0];
btn_hole_d = 3;              // toothpick / paperclip
btn_tube_wall = 1;
btn_top_above_esp = 2;       // tact switch top above the module PCB
btn_gap = 1;                 // tube stops this far above the button

// ======================= SHELL =======================
wall     = 2;
floor_t  = 2;
lid_t    = 2;
corner_r = 2;
fit      = 0.2;              // general FDM clearance
standoff_h = 3;              // floor to the board's underside (solder tails)
pcb_x0   = 0.3;              // USB wall's inner face to the board's edge (fan case: near_end_clearance)
side_gap = 1.5;              // board's long edges to the tray walls
end_gap  = 1.0;              // board's far edge to the far wall
top_gap  = 1.0;              // tallest part to the ceiling

// ======================= SKIRTS, WEDGES AND DIVOTS (sump-master-2000) =======================
skirt_t    = 2;              // skirt thickness
skirt_gap  = 0.2;            // skirt to the tray wall
pad_w      = 8;              // thinned pocket width
pad_t      = 1;              // skirt thickness left at the pocket
detent     = 0.4;            // TUNE: how far the wedge reaches past the tray wall's face
detent_clr = 0.1;            // divot clearance around the wedge when closed (no preload)
bump_p     = skirt_gap + detent;
bump_ang   = 35;             // flank angle from the wall: lower = easier on and off
bump_flat  = 0.4;            // crest length (rounded)
bump_round = 0.2;
bump_w     = pad_w - 2;
seat_w     = bump_w + 1;

// ======================= PINS AND CAPS =======================
pin_d    = 2.2;              // through the 2.5 mm holes (clearance: all pins enter at once in step 3)
boss_d   = 5;
hook_od  = 4.5;              // hollow cap over a tray pin
hook_gap = 0.3;              // cap stops this far above the board
hook_bore_d = pin_d + 0.6;
lidpin_od = 3.4;             // H1 post: tight between the ESP's edge (x 22.5) and J1 (x 26.83)
lidpin_gap = 0.1;            // post's foot to the board
lidpin_below = 1.0;          // pin reaches this far below the board's underside
lidpin_bore_d = pin_d + 0.7; // bore in the tray boss under H1

// ======================= STRAP SLOT (optional) =======================
// One zip tie in through a side wall at floor level, across the floor under the
// GY-346 (board x 33-39 has no solder tails) and out the other side, e.g. round
// a pipe. Set strap = false for a plain case (stick it on with VHB tape).
strap = true;
strap_kicad_x = 35.5;         // between J1's tails (x 28.1) and H2's boss (x 39-44); jumpers at 30.85-32.15 are flat
strap_w = 5.5; strap_h = 2;
strap_slot_w = strap_w + 1;
strap_slot_h = strap_h + 0.6;   // stays under the board (standoff_h)

// ======================= LID TOP =======================
dot_spacing = 5;
dot_r = 1.8;
dot_depth = 0.35;
vent_hole_d = 3;
texture_margin = 5;
label = "DEVICE MONITOR";

// ======================= DERIVED =======================
pcb_top = standoff_h + pcb_t;
esp_top = pcb_top + esp_hdr + esp_pcb;                    // module PCB top
in_w = pcb_w + 2 * side_gap;
in_l = pcb_x0 + pcb_l + end_gap;
tallest = max(cap_h, gy_z + 1.6 + gy_parts_h, esp_hdr + esp_pcb + usb_h);
in_h = ceil(pcb_top + tallest + top_gap);
out_l = in_l + 2 * wall; out_w = in_w + 2 * wall;
pcb_y0 = (in_w - pcb_w) / 2;
function bxy(p) = [pcb_x0 + p[0], pcb_y0 + (pcb_w - p[1])];

usb_y  = bxy([0, esp_xy[1]])[1];
usb_z0 = esp_top - usb_margin;
usb_z1 = esp_top + usb_h + usb_margin;
usb_zc = (usb_z0 + usb_z1) / 2;
stub_h = usb_z0 - 1.2;           // tray's USB-end stub wall: stops below the port (fan case)
btn_xy = bxy(btn_kicad);
btn_tube_z0 = esp_top + btn_top_above_esp + btn_gap;

// The skirts hang beside the board's long edges, so they only need to clear the
// edge strip of the board: start them just above it.
skirt_z0 = pcb_top + 1;
bump_zc  = skirt_z0 + 1.6;
skirt_snap_x = [round(in_l * 0.22), round(in_l * 0.78)];

assert(usb_z0 - stub_h >= 1, "stub wall reaches the USB port");
assert(usb_z1 < in_h - 1, "USB port reaches the ceiling");
assert(skirt_gap + skirt_t < side_gap + 1.8, "skirts reach over the board's components");

module rbox(l, w, h, r) {
  translate([r, r, 0]) linear_extrude(h) offset(r) square([l - 2 * r, w - 2 * r]);
}
module at_inner() { translate([wall, wall, floor_t]) children(); }

// USB-C opening: a stadium (the connector's own outline), through the lid's end wall.
module usb_port_cutter(depth) {
  r = (usb_z1 - usb_z0) / 2;
  translate([-1, wall + usb_y, floor_t + usb_zc]) hull()
    for (s = [-1, 1]) translate([0, s * (usb_port_w / 2 - r), 0]) rotate([0, 90, 0]) cylinder(r = r, h = depth);
}

// =============== TRAY ===============
module tray() {
  difference() {
    rbox(out_l, out_w, floor_t + in_h, corner_r);
    at_inner() cube([in_l, in_w, in_h + 1]);
    // USB end: a low stub wall below the port; the lid's end wall drops onto it
    translate([-1, -1, floor_t + stub_h]) cube([wall + fit + 1, out_w + 2, 50]);
    // divots that the lid skirts' wedges click into
    at_inner() for (x = skirt_snap_x, side = [0, 1]) detent_seat(x, side);
    // strap slot through both long walls, at floor level
    if (strap) translate([wall + bxy([strap_kicad_x, 0])[0] - strap_slot_w / 2, -1, floor_t])
      cube([strap_slot_w, out_w + 2, strap_slot_h]);
    // label on the y = 0 long wall, above the divots
    translate([out_l / 2 + 2, 0.5, floor_t + (in_h + bump_zc + 2) / 2])
      rotate([90, 0, 0]) linear_extrude(1)
        text(label, size = 3.6, halign = "center", valign = "center", font = "Liberation Sans:style=Bold");
  }
  // standoffs and pins
  at_inner() for (h = holes) {
    p = bxy(h);
    translate([p[0], p[1], 0]) {
      if (h[2] == "lidpin") difference() {
        cylinder(d = boss_d, h = standoff_h);
        translate([0, 0, standoff_h - lidpin_below - 0.6]) cylinder(d = lidpin_bore_d, h = 5);
      } else {
        cylinder(d = boss_d, h = standoff_h);
        cylinder(d = pin_d, h = pcb_top + 1.2);
        translate([0, 0, pcb_top + 1.2]) cylinder(d1 = pin_d, d2 = 1.4, h = 0.6);
      }
    }
  }
}

// Wedge profile in the plane across a long wall: q = distance from the skirt's
// outer face toward the tray wall, z = height. Trapezoid with bump_ang flanks
// and a rounded crest. grow > 0 makes the divot.
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

// One lid skirt (cavity coordinates): unbroken along its length, thinned from the
// inside to a 1 mm pocket at each wedge so it flexes; the full skirt frames the
// pocket on both sides and at the ceiling.
module skirt(side) {
  y0 = side ? in_w - skirt_gap - skirt_t : skirt_gap;
  difference() {
    translate([1, y0, skirt_z0]) cube([in_l - 1.4, skirt_t, in_h - skirt_z0 + 0.01]);
    for (x = skirt_snap_x)
      translate([x - pad_w / 2, side ? y0 - 1 : y0 + pad_t, skirt_z0 - 1])
        cube([pad_w, skirt_t - pad_t + 1, in_h - skirt_z0 + 1]);
  }
  for (x = skirt_snap_x) intersection() {
    detent_bump(x, side);
    translate([0, -5, skirt_z0]) cube([in_l, in_w + 10, in_h]);
  }
}

// =============== LID (modelled in place; flipped for printing) ===============
module lid() {
  difference() {
    union() {
      translate([0, 0, floor_t + in_h]) rbox(out_l, out_w, lid_t, corner_r);
      at_inner() for (side = [0, 1]) skirt(side);
      // end wall at the USB end: full width, sits on the tray's stub wall, holds the port
      intersection() {
        rbox(out_l, out_w, floor_t + in_h + 0.01, corner_r);
        translate([-1, -1, floor_t + stub_h + fit]) cube([wall + 1, out_w + 2, 100]);
      }
      at_inner() for (h = holes) {
        p = bxy(h);
        if (h[2] == "hook")      // hollow cap over the tray pin
          translate([p[0], p[1], pcb_top + hook_gap]) difference() {
            cylinder(d = hook_od, h = in_h - pcb_top - hook_gap + 0.01);
            translate([0, 0, -1]) cylinder(d = hook_bore_d, h = 3.5);
          }
        if (h[2] == "lidpin") translate([p[0], p[1], 0]) {   // post + locating pin
          translate([0, 0, pcb_top + lidpin_gap]) cylinder(d = lidpin_od, h = in_h - pcb_top - lidpin_gap + 0.01);
          translate([0, 0, standoff_h - lidpin_below + 0.5]) cylinder(d = pin_d, h = pcb_t + lidpin_below);
          translate([0, 0, standoff_h - lidpin_below]) cylinder(d1 = 1.4, d2 = pin_d, h = 0.5 + 0.01);
        }
      }
      // reset guide tube, from the ceiling to just above the button
      at_inner() translate([btn_xy[0], btn_xy[1], btn_tube_z0])
        cylinder(d = btn_hole_d + 2 * btn_tube_wall, h = in_h - btn_tube_z0 + 0.01);
    }
    usb_port_cutter(wall + 2);
    at_inner() translate([btn_xy[0], btn_xy[1], btn_tube_z0 - 0.5]) cylinder(d = btn_hole_d, h = in_h + lid_t);
    lid_texture();
  }
}

// Lid top: a 5 mm grid centred on the lid. Two rows of 3 mm vent holes (airflow,
// and the onboard LED shows through them) with a row of dimples either side of the
// centre line (fan-case look). Holes and dimples keep clear of the reset bore and
// of the posts' roots. The rows stay inside the skirts.
module lid_texture() {
  top = floor_t + in_h + lid_t;
  n_cols = floor((out_l - 2 * texture_margin) / dot_spacing) + 1;
  u0 = (out_l - (n_cols - 1) * dot_spacing) / 2;
  yc = wall + bxy(esp_xy)[1];   // on the board's centre line
  o = [wall, wall];
  btn = o + btn_xy;
  posts = [for (h = holes) if (h[2] != "pin") o + bxy(h)];
  function near(p, list, r) = len([for (q = list) if (norm(p - q) < r) 1]) > 0;
  for (i = [0 : n_cols - 1]) {
    x = u0 + i * dot_spacing;
    for (k = [-1.5, -0.5, 0.5, 1.5]) {
      p = [x, yc + k * dot_spacing];
      if (norm(p - btn) > 4.6 && !near(p, posts, 4.2) && x > wall + 2.5 && x < out_l - wall - 2)
        if (abs(k) > 1) translate([p[0], p[1], top - lid_t - 1]) cylinder(d = vent_hole_d, h = lid_t + 2, $fn = 24);
        else translate([p[0], p[1], top + dot_r - dot_depth]) sphere(r = dot_r, $fn = 16);
    }
  }
}

// =============== stand-in parts (preview and clash check) ===============
// Each is a solid the case must not touch. The board has its holes, so the
// pins passing through them don't count.
module board_dummy() at_inner() difference() {
  translate([pcb_x0, pcb_y0, standoff_h]) cube([pcb_l, pcb_w, pcb_t]);
  for (h = holes) translate(concat(bxy(h), [standoff_h - 1])) cylinder(d = 2.5, h = pcb_t + 2);
}
// box from KiCad corners a, b (any order), z0..z1 above the board's top face
module kbox(a, b, z0, z1) {
  p = bxy(a); q = bxy(b);
  translate([min(p[0], q[0]), min(p[1], q[1]), pcb_top + z0]) cube([abs(q[0] - p[0]), abs(q[1] - p[1]), z1 - z0]);
}
module parts_dummies() at_inner() {
  ex0 = esp_xy[0] - esp_size[0] / 2; ey0 = esp_xy[1] - esp_size[1] / 2;
  color("royalblue") kbox([ex0, ey0], [ex0 + esp_size[0], ey0 + esp_size[1]], esp_hdr, esp_hdr + esp_pcb);
  color("dimgray") kbox([ex0 + 6, ey0 + 3], [ex0 + esp_size[0] - 1, ey0 + esp_size[1] - 3], esp_hdr + esp_pcb, esp_hdr + esp_pcb + esp_parts_h);
  // ESP header strips (two 1x8 rows, 15.24 apart) and the RESET/BOOT buttons
  color("black") for (ky = [esp_xy[1] - 7.62, esp_xy[1] + 7.62])
    kbox([esp_xy[0] - 10.16, ky - 1.27], [esp_xy[0] + 10.16, ky + 1.27], 0, esp_hdr);
  color("white") for (by = [btn_kicad[1], 2 * esp_xy[1] - btn_kicad[1]])
    kbox([btn_kicad[0] - 1.5, by - 1.75], [btn_kicad[0] + 1.5, by + 1.75], esp_hdr + esp_pcb, esp_hdr + esp_pcb + btn_top_above_esp);
  // USB-C receptacle: a stadium in section (rounded ends, r = half its height)
  color("silver") translate(concat(bxy([-1, esp_xy[1]]), [esp_top + usb_h / 2])) hull()
    for (s = [-1, 1]) translate([0, s * (usb_w / 2 - usb_h / 2), 0]) rotate([0, 90, 0]) cylinder(d = usb_h, h = usb_len);
  // GY-346 on its header
  color("black") kbox([j1_xy[0] - 1.27, j1_xy[1] - 1.27], [j1_xy[0] + 1.27, j1_xy[1] + 7 * 2.54 + 1.27], 0, gy_z);
  color("purple") kbox([gy_x0, esp_xy[1] - gy_size[1] / 2], [gy_x0 + gy_size[0], esp_xy[1] + gy_size[1] / 2], gy_z, gy_z + 1.6);
  color("gray") kbox([gy_x0 + 3, esp_xy[1] - 3], [gy_x0 + 7, esp_xy[1] + 3], gy_z + 1.6, gy_z + 1.6 + gy_parts_h);
  // bulk cap
  color("steelblue") translate(concat(bxy(cap_xy), [pcb_top])) cylinder(d = cap_d, h = cap_h);
}
// Solder tails under the board (ESP + J1 header pins, cap leads): what the floor and strap must clear.
module tails_dummies() at_inner() color("gold") {
  for (ky = [esp_xy[1] - 7.62, esp_xy[1] + 7.62]) kbox([esp_xy[0] - 10.16, ky - 0.5], [esp_xy[0] + 10.16, ky + 0.5], -pcb_t - 1.5, -pcb_t);
  kbox([j1_xy[0] - 0.5, j1_xy[1] - 0.5], [j1_xy[0] + 0.5, j1_xy[1] + 7 * 2.54 + 0.5], -pcb_t - 1.5, -pcb_t);
  for (dx = [-1.25, 1.25]) kbox([cap_xy[0] + dx - 0.5, cap_xy[1] - 0.5], [cap_xy[0] + dx + 0.5, cap_xy[1] + 0.5], -pcb_t - 1.5, -pcb_t);
}
module tie_dummy() if (strap) color("black")
  translate([wall + bxy([strap_kicad_x, 0])[0] - strap_w / 2, -0.5, floor_t + 0.2]) cube([strap_w, out_w + 1, strap_h - 0.4]);

module everything_else() { board_dummy(); parts_dummies(); tails_dummies(); tie_dummy(); }

echo(str("case outside ", out_l, " x ", out_w, " x ", floor_t + in_h + lid_t, " mm; cavity ", in_l, " x ", in_w, " x ", in_h));

if (part == "none") { }
else if (part == "tray") tray();
else if (part == "lid") translate([0, out_w, floor_t + in_h + lid_t]) rotate([180, 0, 0]) lid();
// each "clash_*" must render empty
else if (part == "clash_lid_tray") intersection() { tray(); lid(); }
else if (part == "clash_lid_parts") intersection() { lid(); everything_else(); }
else if (part == "clash_tray_parts") intersection() { tray(); everything_else(); }
else if (part == "closed") { color("steelblue") tray(); color("lightgray") lid(); }
else if (part == "fit") { tray(); board_dummy(); parts_dummies(); }
else if (part == "section") intersection() {
  union() { tray(); lid(); board_dummy(); parts_dummies(); }
  translate([-5, wall + bxy(esp_xy)[1], -10]) cube([200, 50, 60]);
}
else { color("steelblue") tray(); color("white", 0.4) lid(); color("green") board_dummy(); parts_dummies(); }
