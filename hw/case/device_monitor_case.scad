// Device Monitor case: tray + lid for the carrier in ../devmon_carrier.kicad_pcb
//
// Built from the two earlier cases by the same author:
//   - github.com/bradrblack/rf-ceiling-fan-remote  hw/case/fan_dongle_case.scad
//       standoff pins through the carrier's holes (no screws) and caps (hook posts)
//       hanging from the lid that clamp the board.
//   - The USB-C opening is split as on sump-master-2000: the tray's stub wall at
//     the USB end holds the lower half of the port and the lid's end wall the
//     upper half, so the board drops straight into the tray (the fan case's
//     port wholly in the lid meant levering the connector into it).
//   - github.com/bradrblack/sump-master-2000  hw/case/sump_case.scad
//       the closure: lid skirts slide down inside full-height tray walls, and a
//       rounded wedge on each skirt pocket clicks into a divot (seat) in the tray
//       wall. This replaces the fan case's friction fit / snap tabs.
//   - slide_in_case.scad (this folder): the lid top. A RESET tab cut into the lid
//     with a plunger under it, a grid of chamfered vent holes, and the ribbon
//     antenna stuck flat under the lid.
// The carrier is the sump-master-2000 carrier cut down to the ESP32-C3 SuperMini
// and the GY-346 (ADXL346) module. By default the optional bulk capacitor C1 is
// not fitted and the case is low (19 mm). Set cap_fitted = true for a board with
// C1: the case grows to 25 mm (tray_cap.stl / lid_cap.stl).
//
// Antenna and cable: the antenna sticks under the lid beside the reset tab. Its
// cable (about 120 mm) is wound three times round the fat post at the far end of
// the lid (H2's cap), which leaves about 50 mm free to reach the SuperMini's u.FL
// connector, enough to lay the open lid beside the tray. One post, not the slide-in
// case's two, so that C1's footprint stays clear (Brad, 2026-11-15).
//
// Closure: closing, each wedge rides down the tray wall with its 1 mm pocket
// flexed 0.4 mm and drops into its divot; closed, nothing is under load (0.1 mm
// clearance), so the fit doesn't creep loose. The 35 deg flanks let a firm pull
// open it again. No slits or free tabs to snap off.
//
// Assembly: stick the antenna into its outline under the lid and wind its cable
// three times round the post. Drop the carrier onto the tray's pins (its USB-C
// connector settles into the lower half of the port), plug the cable into the
// SuperMini, then push the lid straight down until the four wedges click.
// Opening: pull the tray and lid apart firmly.
//
// Render (from this folder):
//   openscad -o tray.stl -D 'part="tray"' device_monitor_case.scad
//   openscad -o lid.stl  -D 'part="lid"'  device_monitor_case.scad   (exported flipped, ceiling on the bed)
//   openscad -o tray_magnets.stl -D 'part="tray"' -D magnets=true device_monitor_case.scad   (magnet mount)
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
cap_fitted = false;          // true: C1 is on the board (taller case)

// ======================= CARRIER (from the KiCad board) =======================
// Keep these in step with hw/devmon_carrier.kicad_pcb (hw/tools/gen_carrier.py).
// Values below are the v1.0 board's (50.5 mm long since the GY-346 was measured at 14 x 21).
pcb_l = 50.5;                // board length (x)
pcb_w = 24.0;                // board width (y)
pcb_t = 1.6;

// Case-pin holes: [kicad x, kicad y, role]. All are 2.5 mm NPTH.
//   "pin"    tray standoff + locating pin only (nothing above: the ESP module covers H5/H6)
//   "hook"   tray standoff + pin, and a hollow cap (hook post) from the lid clamps the board
//   "short"  tray standoff + a pin that stops just below the board's top face (H1).
//            The lid's solid post presses on the board at press_kicad instead of on
//            the hole, because the antenna is above the hole.
holes = [
  [ 3.75,  8.0, "pin"],      // H5  under the ESP32, USB end: takes the USB plug's push
  [ 3.75, 16.0, "pin"],      // H6
  [24.4,  12.0, "short"],    // H1  between the ESP32 and the ADXL346 header
  [45.3,  17.5, "hook"],     // H2  far end (GY-346 edge x 40.83): its cap is the cable post
];
// Solid lid post: on the bare strip between the ESP (edge x 22.5) and J1 (x 26.83),
// toward the RESET side so it is clear of the antenna.
press_kicad = [24.4, 6.0];
cap_xy = [45.3, 6.0];        // C1 body centre (CP_Radial_D8.0 P2.5, leads at x 44.05 / 46.55)
cap_d = 8;                   // envelope: 470 uF/6.3 V is 6.3-8 x 11-12; 100 uF/10 V is 5 x 11
cap_h = 12.5;

// Parts, for the clash check and the preview (KiCad coordinates, heights above the
// board's top face). Keep in step with the PCB.
esp_xy   = [11.25, 12];      // U1 centre (SuperMini footprint origin)
esp_size = [22.5, 18];       // module board
esp_hdr  = 2.54;             // header spacer under the module
esp_pcb  = 1.2;              // module PCB thickness
esp_parts_h = 1.6;           // chip / LDO / buttons above the module PCB (buttons ~1.5-2: see btn_*)
gy_x0 = 28.1 - 1.27;         // GY-346 lies flat from its J1 header row toward +x (as on sm2k)
gy_size = [14, 21];          // GY-346 board (user-measured 2026-11-13)
gy_z  = 2.5;                 // module soldered on its own header, board 2.5 mm up
gy_parts_h = 1.6;            // tallest parts on top of the module (its big cap and regulator)
j1_xy = [28.1, 3.11];        // J1 pin 1, 1x8 down the board (y)

// External ribbon antenna (SuperMini v2's u.FL antenna, 40 x 11 mm, 120 mm cable: Brad,
// 2026-11-15): stuck flat under the lid, in the strip between the reset tab and the
// skirt on the far side from RESET. A 0.2 mm outline in the ceiling marks its spot.
antenna = true;
ant_w = 11; ant_l = 40; ant_t = 0.3;
ant_x0 = 0.4;                // from the USB end, so it stops short of the cable post

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
btn_top_above_esp = 2;       // tact switch top above the module PCB
// Reset tab (as slide_in_case.scad): a tongue cut into the lid (keyhole outline) with
// a plunger under its round end. Press the lid there to press RESET.
tab_pad_d = 3.6;             // round end, over the button
tab_w = 3;                   // tongue width
tab_len = 12;                // button centre to the tongue's root (toward the far end)
tab_t = 1.2;                 // tongue thickness (thinned from inside so it flexes): 6 layers at 0.2
tab_ramp = 2.5;              // the thinning ramps back to full lid thickness over this length at the root
tab_slot = 0.6;              // cut around it
tab_chamfer = 0.5;           // the cut widens to tab_slot + 2 x this at the lid's top face, so the
                             // first layers (squashed on the bed: the lid prints top down) don't close it
plunger_d = cap_fitted ? 3.2 : 2.4;   // stouter in the tall case, where it is 9 mm long
btn_gap = 0.5;               // plunger tip above the button at rest

// Magnet mount (optional, as slide_in_case.scad): four 10 x 3 mm neodymium disc
// magnets in pockets that open into the cavity, with 0.6 mm of floor under each.
// The skin sits between magnet and steel, so pulling the case off can't pull a
// magnet out: no glue. The floor grows from 2 to 3.8 mm (the case gets 1.8 mm
// taller); footprint and lid are unchanged. Press them in before the board goes in.
magnets = false;
mag_d = 10; mag_t = 3;
mag_hole_d = mag_d + 0.15;   // press fit; mag_d + 0.3 to glue them loose
mag_depth = mag_t + 0.2;     // magnet ends 0.2 below the floor's top
mag_skin = 0.6;
mag_chamfer = 0.4;           // lead-in round the pocket mouth
// Pocket centres in KiCad board coordinates: a 2 x 2 grid in the clear floor
// between the standoff bosses (H5/H6 at the USB end, H1 in the middle, H2 at the far
// end). The rear pair sits under the zip-tie slot, which only cuts the walls.
mag_kicad = [[12.0, 5.25], [12.0, 18.75], [36.7, 5.25], [36.7, 18.75]];

// ======================= SHELL =======================
wall     = 2;
floor_t  = !magnets ? 2 : mag_skin + mag_depth;
lid_t    = 2;
corner_r = 2;
fit      = 0.2;              // general FDM clearance
// Header pins below the carrier, solder included: Brad measured 4.3 mm on the ESP32
// rows (2026-11-22; 1.5 was assumed before). The J1 row is taken as the same. The
// standoffs leave 0.7 mm under them, so nothing needs trimming.
tail_len = 4.3;
standoff_h = tail_len + 0.7; // floor to the board's underside
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
solid_od = 3.4;              // press post: tight between the ESP's edge (x 22.5) and J1 (x 26.83)
// Cable post: H2's cap, fat so the coax bends gently round it (about 4 mm radius),
// with a flared foot so the turns can't slip off.
cleat_d = 7;
cleat_flare = 0.8;

// ======================= STRAP SLOT (optional) =======================
// One zip tie in through a side wall at floor level, across the floor under the
// GY-346 (board x 33-39 has no solder tails) and out the other side, e.g. round
// a pipe. Set strap = false for a plain case (stick it on with VHB tape).
// Pry slot: a notch in the top of the tray's end wall opposite the USB-C port, so a
// small flat screwdriver can go under the lid's edge there and lever it off.
pry_slot = true;
pry_w = 8;                   // across the case
pry_d = 1.2;                 // down from the wall's top
strap = true;
strap_kicad_x = 35.5;         // between J1's tails (x 28.1) and C1's leads / H2's boss (x 42.8+); jumpers at 30.85-32.15 are flat
strap_w = 5.5; strap_h = 2;
strap_slot_w = strap_w + 1;
strap_slot_h = strap_h + 0.6;   // stays under the board (standoff_h)

// ======================= LID TOP =======================
// Vent grid as on slide_in_case.scad; the holes are drilled over the antenna too.
vent_hole_d = 2.6;
vent_pitch = 4.2;            // along the case
vent_row = 3.6;              // between rows
vent_chamfer = 0.4;          // countersink on the top face (the lid prints top down)
vent_margin = 0.8;           // web left round the tab and the posts
// Side vents: a row of the same round holes through each long wall and the lid
// skirt behind it, between the two snaps.
side_vents = true;
sv_n = 5;
sv_drop = 2.6;               // hole centre below the ceiling
sv_skirt_extra = 0.6;        // the skirt's holes are this much wider, so the two line up
label = "";                  // text on the y = 0 wall ("" = none; it would cross the side vents)

// ======================= DERIVED =======================
pcb_top = standoff_h + pcb_t;
esp_top = pcb_top + esp_hdr + esp_pcb;                    // module PCB top
in_w = pcb_w + 2 * side_gap;
in_l = pcb_x0 + pcb_l + end_gap;
tallest = max(cap_fitted ? cap_h : 0, gy_z + 1.6 + gy_parts_h, esp_hdr + esp_pcb + usb_h);
in_h = ceil(pcb_top + tallest + top_gap);
out_l = in_l + 2 * wall; out_w = in_w + 2 * wall;
pcb_y0 = (in_w - pcb_w) / 2;
function bxy(p) = [pcb_x0 + p[0], pcb_y0 + (pcb_w - p[1])];

usb_y  = bxy([0, esp_xy[1]])[1];
usb_z0 = esp_top - usb_margin;
usb_z1 = esp_top + usb_h + usb_margin;
usb_zc = (usb_z0 + usb_z1) / 2;
stub_h = usb_zc;                 // tray's USB-end stub wall: up to the port's centre line (sump-master-2000)
btn_xy = bxy(btn_kicad);
plunger_z0 = esp_top + btn_top_above_esp + btn_gap;

// The skirts hang beside the board's long edges, so they only need to clear the
// edge strip of the board: start them just above it.
skirt_z0 = pcb_top + 1;
bump_zc  = skirt_z0 + 1.6;
skirt_snap_x = [round(in_l * 0.22), round(in_l * 0.78)];
sv_z = in_h - sv_drop;
sk_in0 = skirt_gap + skirt_t; sk_in1 = in_w - skirt_gap - skirt_t;   // skirts' inner faces
ant_y0 = sk_in0 + 0.3; ant_y1 = ant_y0 + ant_w;
press_xy = bxy(press_kicad);
cleat_xy = [for (h = holes) if (h[2] == "hook") bxy(h)];
cable_turns = 3;                      // turns of cable round the post
sv_x = [for (i = [0 : sv_n - 1]) in_l / 2 + (i - (sv_n - 1) / 2) * vent_pitch];
assert(ant_y1 + 0.3 <= btn_xy[1] - tab_pad_d / 2 - tab_slot - tab_chamfer, "antenna strip reaches the reset tab");
assert(ant_x0 + ant_l + 0.5 <= cleat_xy[0][0] - cleat_d / 2 - cleat_flare, "antenna reaches the cable post");
assert(sv_x[0] - vent_hole_d / 2 > skirt_snap_x[0] + pad_w / 2 && sv_x[sv_n - 1] + vent_hole_d / 2 < skirt_snap_x[1] - pad_w / 2, "side vents reach a snap pocket");

assert(usb_z1 < in_h - 1, "USB port reaches the ceiling");
mag_xy = magnets ? [for (m = mag_kicad) bxy(m)] : [];
for (m = mag_xy) {
  r = mag_hole_d / 2 + mag_chamfer;
  for (h = holes) assert(norm(m - bxy(h)) >= boss_d / 2 + r + 0.4, "a magnet pocket cuts a standoff boss");
  assert(m[0] - r >= 0 && m[0] + r <= in_l && m[1] - r >= 0.5 && m[1] + r <= in_w - 0.5, "a magnet pocket runs into a wall");
  for (n = mag_xy) if (n != m) assert(norm(m - n) >= mag_hole_d + 0.7, "magnet pockets overlap");
}
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
    usb_port_cutter(wall + 2);       // lower half of the port
    if (pry_slot) translate([out_l - wall - 1, out_w / 2 - pry_w / 2, floor_t + in_h - pry_d]) cube([wall + 2, pry_w, pry_d + 1]);
    // divots that the lid skirts' wedges click into
    at_inner() for (x = skirt_snap_x, side = [0, 1]) detent_seat(x, side);
    // strap slot through both long walls, at floor level
    if (strap) translate([wall + bxy([strap_kicad_x, 0])[0] - strap_slot_w / 2, -1, floor_t])
      cube([strap_slot_w, out_w + 2, strap_slot_h]);
    if (side_vents) at_inner() for (x = sv_x) translate([x, -wall - 1, sv_z])
      rotate([-90, 0, 0]) cylinder(d = vent_hole_d, h = out_w + 2, $fn = 24);
    // magnet pockets, each with a 45 deg lead-in
    at_inner() for (m = mag_xy) translate([m[0], m[1], 0]) {
      translate([0, 0, -mag_depth]) cylinder(d = mag_hole_d, h = mag_depth + 0.01, $fn = 64);
      translate([0, 0, -mag_chamfer]) cylinder(d1 = mag_hole_d, d2 = mag_hole_d + 2 * mag_chamfer + 0.02, h = mag_chamfer + 0.01, $fn = 64);
    }
    // label on the y = 0 long wall, above the divots
    if (label != "") translate([out_l / 2 + 2, 0.5, floor_t + (in_h + bump_zc + 2) / 2])
      rotate([90, 0, 0]) linear_extrude(1)
        text(label, size = 3.6, halign = "center", valign = "center", font = "Liberation Sans:style=Bold");
  }
  // standoffs and pins
  at_inner() for (h = holes) {
    p = bxy(h);
    translate([p[0], p[1], 0]) {
      pin_top = h[2] == "short" ? pcb_top - 0.9 : pcb_top + 1.2;   // short pin: nothing of the lid's over it
      cylinder(d = boss_d, h = standoff_h);
      cylinder(d = pin_d, h = pin_top);
      translate([0, 0, pin_top]) cylinder(d1 = pin_d, d2 = 1.4, h = 0.6);
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
    translate([0, y0, skirt_z0]) cube([in_l - 0.4, skirt_t, in_h - skirt_z0 + 0.01]);
    // joined to the lid's end wall above the tray's stub wall (no gap at the corner)
    translate([-0.5, y0, stub_h + fit]) cube([0.6, skirt_t, in_h - stub_h - fit + 0.01]);
    for (x = skirt_snap_x)
      translate([x - pad_w / 2, side ? y0 - 1 : y0 + pad_t, skirt_z0 - 1])
        cube([pad_w, skirt_t - pad_t + 1, in_h - skirt_z0 + 1]);
    if (side_vents) for (x = sv_x) translate([x, y0 - 1, sv_z])
      rotate([-90, 0, 0]) cylinder(d = vent_hole_d + sv_skirt_extra, h = skirt_t + 2, $fn = 24);
  }
  for (x = skirt_snap_x) intersection() {
    detent_bump(x, side);
    translate([0, -5, skirt_z0]) cube([in_l, in_w + 10, in_h]);
  }
}

// =============== LID (modelled in place; flipped for printing) ===============
// A cable post: fat shank from the ceiling to just above the board, with a flared
// foot (45 deg, printable upside down). bore > 0 makes it a cap over a tray pin.
module cleat_post(p, bore = 0) {
  z0 = pcb_top + hook_gap;
  translate([p[0], p[1], z0]) difference() {
    union() {
      cylinder(d = cleat_d + 2 * cleat_flare, h = 0.4);
      translate([0, 0, 0.4]) cylinder(d1 = cleat_d + 2 * cleat_flare, d2 = cleat_d, h = cleat_flare);
      cylinder(d = cleat_d, h = in_h - z0 + 0.01);
    }
    if (bore > 0) translate([0, 0, -1]) cylinder(d = bore, h = 3.5);
  }
}
module lid() {
  difference() {
    union() {
      translate([0, 0, floor_t + in_h]) rbox(out_l, out_w, lid_t, corner_r);
      at_inner() for (side = [0, 1]) skirt(side);
      // end wall at the USB end: full width, sits on the tray's stub wall, holds the port's upper half
      intersection() {
        rbox(out_l, out_w, floor_t + in_h + 0.01, corner_r);
        translate([-1, -1, floor_t + stub_h + fit]) cube([wall + 1, out_w + 2, 100]);
      }
      at_inner() {
        // cable post: H2's cap (over the tray pin)
        for (h = holes) if (h[2] == "hook") cleat_post(bxy(h), hook_bore_d);
        // solid post pressing on the board between the ESP and J1
        translate([press_xy[0], press_xy[1], pcb_top + hook_gap]) cylinder(d = solid_od, h = in_h - pcb_top - hook_gap + 0.01);
      }
    }
    usb_port_cutter(wall + 2);
    // reset tab: a U-shaped slot round the tongue (open at the root, where the
    // tongue stays joined to the lid), and the tongue thinned from inside, ramping
    // back to full thickness at the root so the bend isn't at a sharp step
    at_inner() {
      root_x = btn_xy[0] + tab_len;
      translate([0, 0, in_h - 1]) linear_extrude(lid_t + 2) tab_slot_2d();
      // 45 deg chamfer round the cut on the top face
      translate([0, 0, in_h + lid_t - tab_chamfer]) minkowski() {
        linear_extrude(0.01) tab_slot_2d();
        cylinder(r1 = 0, r2 = tab_chamfer + 0.01, h = tab_chamfer + 0.01, $fn = 12);
      }
      thin = lid_t - tab_t;
      translate([0, 0, in_h - 0.01]) linear_extrude(thin + 0.01) intersection() {
        tab_outline();
        translate([0, -50]) square([root_x - tab_ramp, 100]);
      }
      hull() {
        translate([root_x - tab_ramp - 0.01, btn_xy[1] - tab_w / 2, in_h - 0.01]) cube([0.01, tab_w, thin + 0.01]);
        translate([root_x - 0.01, btn_xy[1] - tab_w / 2, in_h - 0.01]) cube([0.01, tab_w, 0.01]);
      }
      // antenna outline: a 0.2 mm recess in the ceiling to stick it into
      if (antenna) translate([ant_x0 - 0.3, ant_y0 - 0.1, in_h - 0.01]) cube([ant_l + 0.6, ant_w + 0.2, 0.21]);
    }
    vents();
  }
  // plunger under the tab's round end
  at_inner() translate([btn_xy[0], btn_xy[1], plunger_z0]) cylinder(d = plunger_d, h = in_h + lid_t - tab_t - plunger_z0 + 0.01);
}
module tab_slot_2d() {
  root_x = btn_xy[0] + tab_len;
  difference() {
    offset(delta = tab_slot) tab_outline();
    tab_outline();
    translate([root_x, btn_xy[1] - tab_w / 2 - tab_slot - 1]) square([tab_slot + 1, tab_w + 2 * tab_slot + 2]);
  }
}
module tab_outline() {
  translate(btn_xy) circle(d = tab_pad_d);
  translate([btn_xy[0], btn_xy[1] - tab_w / 2]) square([tab_len, tab_w]);
}

// Vent holes: a square grid over the lid (airflow, and the onboard LED shows
// through), kept clear of the reset tab, the posts and the skirts. Two blocks:
// over the SuperMini, and over the module between the press post and the cable
// post. A block's row is drilled only if every hole in it is clear, so the pattern
// stays a tidy grid instead of a scatter around the keep-outs.
module vents() at_inner() {
  m = vent_margin + vent_hole_d / 2;
  cr = cleat_d / 2;
  keep_out = [
    [btn_xy[0] - tab_pad_d / 2 - tab_slot, btn_xy[1] - tab_pad_d / 2 - tab_slot, btn_xy[0] + tab_len + tab_slot, btn_xy[1] + tab_pad_d / 2 + tab_slot],
    [press_xy[0] - solid_od / 2, press_xy[1] - solid_od / 2, press_xy[0] + solid_od / 2, press_xy[1] + solid_od / 2],
    for (c = cleat_xy) [c[0] - cr, c[1] - cr, c[0] + cr, c[1] + cr]];
  rows = floor((sk_in1 - sk_in0 - 2 * m) / vent_row) + 1;
  y0 = (in_w - (rows - 1) * vent_row) / 2;
  esp_x1 = pcb_x0 + esp_xy[0] + esp_size[0] / 2;
  blocks = [[for (x = [2.5 : vent_pitch : esp_x1 - 1]) x],
            [for (x = [press_xy[0] + solid_od / 2 + m + 0.1 : vent_pitch : cleat_xy[0][0] - cr - m]) x]];
  for (b = blocks, jr = [0 : rows - 1]) {
    y = y0 + jr * vent_row;
    hits = [for (x = b, r = keep_out) if (x > r[0] - m && x < r[2] + m && y > r[1] - m && y < r[3] + m) 1];
    if (len(hits) == 0) for (x = b) translate([x, y, in_h - 1]) {
      cylinder(d = vent_hole_d, h = lid_t + 2, $fn = 24);
      translate([0, 0, 1 + lid_t - vent_chamfer]) cylinder(d1 = vent_hole_d, d2 = vent_hole_d + 2 * vent_chamfer + 0.02, h = vent_chamfer + 0.01, $fn = 24);
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
  if (cap_fitted) color("steelblue") translate(concat(bxy(cap_xy), [pcb_top])) cylinder(d = cap_d, h = cap_h);
  // its parts: anywhere on the module except the strip over its header
  color("gray") kbox([gy_x0 + 2.6, esp_xy[1] - gy_size[1] / 2 + 0.5], [gy_x0 + gy_size[0] - 0.5, esp_xy[1] + gy_size[1] / 2 - 0.5], gy_z + 1.6, gy_z + 1.6 + gy_parts_h);
}
// Solder tails under the board (ESP + J1 header pins): what the floor and strap must clear.
module tails_dummies() at_inner() color("gold") {
  for (ky = [esp_xy[1] - 7.62, esp_xy[1] + 7.62]) kbox([esp_xy[0] - 10.16, ky - 0.5], [esp_xy[0] + 10.16, ky + 0.5], -pcb_t - tail_len, -pcb_t);
  kbox([j1_xy[0] - 0.5, j1_xy[1] - 0.5], [j1_xy[0] + 0.5, j1_xy[1] + 7 * 2.54 + 0.5], -pcb_t - tail_len, -pcb_t);
  if (cap_fitted) for (dx = [-1.25, 1.25]) kbox([cap_xy[0] + dx - 0.5, cap_xy[1] - 0.5], [cap_xy[0] + dx + 0.5, cap_xy[1] + 0.5], -pcb_t - tail_len, -pcb_t);
}
module tie_dummy() if (strap) color("black")
  translate([wall + bxy([strap_kicad_x, 0])[0] - strap_w / 2, -0.5, floor_t + 0.2]) cube([strap_w, out_w + 1, strap_h - 0.4]);

module antenna_dummy() if (antenna) color("orange") at_inner()
  translate([ant_x0, ant_y0, in_h + 0.2 - ant_t]) cube([ant_l, ant_w, ant_t]);
// The cable where it is wound round the post: cable_turns turns, stacked under the ceiling.
module cable_dummy() if (antenna) color("black") at_inner() translate([0, 0, in_h - 1 - 1.2 * cable_turns]) linear_extrude(1.2 * cable_turns) difference() {
  hull() for (c = cleat_xy) translate(c) circle(d = cleat_d + 2.6);
  hull() for (c = cleat_xy) translate(c) circle(d = cleat_d + 0.2);
}
module magnet_dummy() color("silver") at_inner() for (m = mag_xy) translate([m[0], m[1], -mag_depth]) cylinder(d = mag_d, h = mag_t, $fn = 64);
module everything_else() { board_dummy(); parts_dummies(); tails_dummies(); tie_dummy(); antenna_dummy(); cable_dummy(); magnet_dummy(); }

echo(str("case outside ", out_l, " x ", out_w, " x ", floor_t + in_h + lid_t, " mm; cavity ", in_l, " x ", in_w, " x ", in_h));

if (part == "none") { }
else if (part == "tray") tray();
else if (part == "lid") translate([0, out_w, floor_t + in_h + lid_t]) rotate([180, 0, 0]) lid();
// each "clash_*" must render empty
else if (part == "clash_lid_tray") intersection() { tray(); lid(); }
else if (part == "clash_lid_parts") intersection() { lid(); everything_else(); }
else if (part == "clash_tray_parts") intersection() { tray(); everything_else(); }
else if (part == "closed") { color("steelblue") tray(); color("lightgray") lid(); }
else if (part == "fit") { tray(); board_dummy(); parts_dummies(); magnet_dummy(); }
else if (part == "magnets") { color("steelblue", 0.45) tray(); magnet_dummy(); }   // see-through tray with its magnets
else if (part == "section") intersection() {
  union() { tray(); lid(); board_dummy(); parts_dummies(); }
  translate([-5, wall + bxy(esp_xy)[1], -10]) cube([200, 50, 60]);
}
else if (part == "lid_inside") {   // the lid as printed (inside up), with the antenna and the wound cable
  translate([0, out_w, floor_t + in_h + lid_t]) rotate([180, 0, 0]) { color("lightgray") lid(); antenna_dummy(); cable_dummy(); }
}
else { color("steelblue") tray(); color("white", 0.4) lid(); color("green") board_dummy(); parts_dummies(); antenna_dummy(); cable_dummy(); }
