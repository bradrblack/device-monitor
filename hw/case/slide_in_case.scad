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
//     come up through its mounting holes, and two small lid feet press on the
//     board round the holes, clear of its parts (as the solid H1 post on the PCB case).
//   - Ribbon antenna (40 x 11 mm) stuck flat to the lid's ceiling, in the strip
//     that the reset tab, the posts and the feet leave clear. Its 120 mm cable is
//     wound once round two fat posts under the lid, past the module.
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
//      its spot), wind its cable once round the two posts and plug it into the
//      SuperMini. Push the lid straight down until the four wedges click.
//
// Render (from this folder):
//   openscad -o slide_tray.stl -D 'part="tray"' slide_in_case.scad
//   openscad -o slide_lid.stl  -D 'part="lid"'  slide_in_case.scad    (flipped, ceiling on the bed)
//   part="both" (default) is a preview with stand-in parts, "fit" the tray with the
//   parts, "section" a cut through the SuperMini's centre line, "feet" the lid's
//   feet over the GY-346 and its parts. The "clash_*" parts
//   must have zero volume: run ./check_case.sh slide_in_case.scad after any change.
//
// Coordinates: x along the case from the USB end, y across, z up from the tray
// floor's top surface, all in the cavity ("inner") unless at_inner() is left off.

part = "both";
$fn = 40;
crush = 0.2;                 // lid feet press this far into the module (0 for the clash check)

// ======================= PARTS (measure yours) =======================
// ESP32-C3 SuperMini: 22.5 x 18 x 1.0 mm bare PCB (Brad, measured 2026-11-14).
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
gy_tails = 1.0;
// Two mounting holes along the edge opposite the pins, 15 mm apart, 3.0 mm across,
// centres 2.5 mm from that edge (Brad, measured 2026-11-14).
gy_hole_pitch = 15; gy_hole_d = 3.0; gy_hole_in = 2.5;   // centre to the module's rear edge
gy_pin_d = 2.4;
// Parts on top of the module, as boxes measured from Brad's photo (scaled by the
// 15 mm hole pitch, so good to about 0.3 mm). Photo view: pin row at the bottom,
// holes at the top. [dx0, dx1, dy0, dy1, height]: dx to the right of the left hole's
// centre, dy down from it toward the pins. They are in the clash check, so a lid
// foot that lands on one fails it.
gy_parts = [
  [-2.3, 0.4, 2.3, 6.0, 1.6],    // regulator (with its leads), below the left hole
  [3.2, 4.2, 0.3, 2.7, 1.3],     // 0805 right of the left hole
  [5.3, 9.6, 0.2, 1.8, 1.6],     // the big cap, top centre
  [10.7, 11.8, 0.3, 2.7, 1.3],   // 0805 left of the right hole
  [1.2, 12.9, 3.0, 6.0, 1.3]];   // row of 0603s and the ADXL chip

// External ribbon antenna for the SuperMini's u.FL (optional): 40 x 11 mm on a
// 120 mm cable (Brad, 2026-11-15).
antenna = true;
ant_l = 40; ant_w = 11; ant_t = 0.3;
// Cable posts (the cleat, as device_monitor_case.scad): two fat posts under the lid
// past the module. The cable is wound once round them, which leaves about 50 mm
// free to reach the u.FL connector. They make the case 9.6 mm longer; set
// cable_posts = false for the short case with a loose cable.
cable_posts = true;
cleat_d = 7;                 // fat, so the coax bends gently (about 4 mm radius)
cleat_flare = 0.8;           // flared foot, so the turns can't slip off
cleat_pitch = 10;            // between the two posts, across the case
cleat_z0 = 4;                // posts' lower end above the floor

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
// Lid feet: one pad round each mounting hole, on the clear board between the hole
// and the module's rear and side edges. On Brad's GY-346 (pins at the bottom, holes
// at the top) the nearest parts, from the hole centres, are: the regulator below
// the left hole from 2.3 mm down, a 0805 part 3.2 mm right of the left hole and
// one 3.2 mm left of the right hole, and the big cap from 5.3 mm right of the left
// hole. So a foot reaches 2.25 mm either side of its hole and only 1.5 mm
// toward the pin row (just past the hole's own edge).
foot_w = 4.5;                // across the module, centred on the hole
foot_fwd = 1.5;              // from the hole centre toward the pin row
foot_back = 2.25;            // from the hole centre toward the rear edge (stops 0.25 short of it)

// Reset tab: a tongue cut into the lid (keyhole outline) with a plunger under its
// round end. Press the lid there to press RESET.
tab_pad_d = 3.6;             // round end, over the button
tab_w = 3;                   // tongue width
tab_len = 12;                // button centre to the tongue's root (toward the back)
tab_t = 1.2;                 // tongue thickness (thinned from inside so it flexes): 6 layers at 0.2
tab_ramp = 2.5;              // the thinning ramps back to full lid thickness over this length at the root
tab_slot = 0.6;              // cut around it
tab_chamfer = 0.5;           // the cut widens to tab_slot + 2 x this at the lid's top face, so the
                             // first layers (squashed on the bed: the lid prints top down) don't close it
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

// Side vents (as device_monitor_case.scad): a row of round holes, the same size as
// the lid's, through each long wall and the lid skirt behind it. They sit between
// the snaps and skip the lid posts.
side_vents = true;
sv_drop = 2.6;               // hole centre below the ceiling
sv_skirt_extra = 0.6;        // the skirt's holes are this much wider, so the two line up

// Zip-tie slot through both long walls, under the module (optional)
strap = true;               // 4.8 mm zip tie (the slot fits between the front rail and the pin bosses)
strap_w = 4.8; strap_h = 2;
strap_slot_w = strap_w + 1; strap_slot_h = strap_h + 0.6;

vent_hole_d = 2.6;
vent_pitch = 4.2;            // along the case
vent_row = 3.6;              // between rows
vent_chamfer = 0.4;          // countersink on the top face, for the same reason as tab_chamfer
vents_over_antenna = true;   // drill the grid over the antenna too (Brad: looks, and it shows the antenna)
led_row = false;             // row of 2 mm holes over the SuperMini's LED edge (off: Brad, 2026-11-15)
led_hole_d = 2.0; led_pitch = 3;
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
ant_x0 = cable_posts ? 0.5 : (max(gy_x1 + 1.4, ant_l + 1.5) - ant_l) / 2;
cleat_x = max(ant_x0 + ant_l, gy_x1) + 0.5 + cleat_flare + cleat_d / 2;
in_l = cable_posts ? cleat_x + cleat_d / 2 + cleat_flare + 1.9 : max(gy_x1 + 1.4, ant_l + 1.5);
cleat_xy = cable_posts ? [for (s = [-1, 1]) [cleat_x, in_w / 2 + s * cleat_pitch / 2]] : [];
// Insertion: the board goes in flat behind the lip, so the lip must end at least
// a board length (plus a little) from the far wall.
strap_x = (gy_x0 + 2.0 + rail_w + gy_holes[0][0] - gy_hole_d / 2 - 1) / 2;
lip_x0 = pad_zone; lip_x1 = min(in_l - esp_l - 0.5, esp_x1 - 3.5);
usb_y = (esp_y0 + esp_y1) / 2;
usb_z0 = esp_top - usb_margin; usb_z1 = esp_top + usb_h + usb_margin;
btn_xy = [esp_x0 + btn_from_front, esp_y0 + btn_from_edge];
plunger_z0 = esp_top + btn_top + btn_gap;
sk_in0 = skirt_gap + skirt_t; sk_in1 = in_w - skirt_gap - skirt_t;   // skirts' inner faces
ant_y0 = btn_xy[1] + tab_pad_d / 2 + tab_slot + 0.3; ant_y1 = ant_y0 + ant_w;
snap_x = [6, cable_posts ? cleat_x - 0.5 : post_x1 + 5];
sv_z = in_h - sv_drop;
fx0 = gy_holes[0][0] - foot_fwd; fx1 = gy_holes[0][0] + foot_back;     // lid feet, along x
// side-vent positions: on the lid's vent pitch, clear of the snap pockets, the posts and the feet
sv_block = [[snap_x[0] - pad_w / 2, snap_x[0] + pad_w / 2], [snap_x[1] - pad_w / 2, snap_x[1] + pad_w / 2],
            [post_x0, post_x1], [fx0, fx1]];
sv_x = [for (x = [vent_pitch : vent_pitch : in_l - 3])
        if (len([for (b = sv_block) if (x > b[0] - vent_hole_d / 2 - 0.7 && x < b[1] + vent_hole_d / 2 + 0.7) 1]) == 0) x];
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
    if (side_vents) at_inner() for (x = sv_x) translate([x, -wall - 1, sv_z])
      rotate([-90, 0, 0]) cylinder(d = vent_hole_d, h = out_w + 2, $fn = 24);
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
    if (side_vents) for (x = sv_x) translate([x, y0 - 1, sv_z])
      rotate([-90, 0, 0]) cylinder(d = vent_hole_d + sv_skirt_extra, h = skirt_t + 2, $fn = 24);
  }
  for (x = snap_x) intersection() {
    detent_bump(x, side);
    translate([0, -5, skirt_z0]) cube([in_l, in_w + 10, in_h]);
  }
}

// A block hanging from the ceiling between x0..x1, reaching y_lo..y_hi at z_bot,
// but rooted only at y >= root_y (or <= root_y if flip): a 45 deg corbel steps it
// out under the antenna strip.
// root_hi (default y_hi) lets the root run on past y_hi, out to the skirt.
module corbel_block(x0, x1, y_lo, y_hi, z_bot, root_y, root_hi = undef) {
  rh = is_undef(root_hi) ? y_hi : root_hi;
  step = max(0, root_y - y_lo);
  assert(in_h - 0.6 - step > z_bot + 0.5, "corbel too deep for the cavity");
  hull() {
    box([x0, root_y, in_h - 0.6], [x1, rh, in_h + 0.01]);
    box([x0, y_lo, z_bot], [x1, y_hi, in_h - 0.6 - step]);
  }
}

// A cable post: fat shank hanging from the ceiling, with a flared foot (45 deg,
// printable upside down).
module cleat_post(p) translate([p[0], p[1], cleat_z0]) {
  cylinder(d = cleat_d + 2 * cleat_flare, h = 0.4);
  translate([0, 0, 0.4]) cylinder(d1 = cleat_d + 2 * cleat_flare, d2 = cleat_d, h = cleat_flare);
  cylinder(d = cleat_d, h = in_h - cleat_z0 + 0.01);
}

// =============== LID (modelled in place; flipped for printing) ===============
module lid() {
  difference() {
    union() {
      translate([0, 0, floor_t + in_h]) rbox(out_l, out_w, lid_t, corner_r);
      at_inner() {
        for (side = [0, 1]) skirt(side);
        for (c = cleat_xy) cleat_post(c);
        // posts behind the SuperMini's rear corners, down to just above the floor.
        // Post A is under the clear strip by the reset tab; post B is beside the
        // antenna, so it is rooted on its skirt and steps out under the antenna.
        box([post_x0, skirt_gap, 0.3], [post_x1, esp_y0 + post_over, in_h + 0.01]);
        corbel_block(post_x0, post_x1, esp_y1 - post_over, sk_in1 + skirt_t, 0.3, ant_y1 + 0.3);
        // feet clamping the module's rear half, either side of the antenna strip
        // over the holes; a bore clears the pin tip
        difference() {
          union() {
            box([fx0, max(sk_in0 + 0.3, gy_holes[0][1] - foot_w / 2), gy_top - crush], [fx1, gy_holes[0][1] + foot_w / 2, in_h + 0.01]);
            // the other foot is beside the antenna strip: rooted on its skirt, it
            // steps out under the antenna and narrows to the pad near the board
            corbel_block(fx0, fx1, gy_holes[1][1] - foot_w / 2, gy_holes[1][1] + foot_w / 2, gy_top - crush, ant_y1 + 0.3, sk_in1 + skirt_t);
          }
          for (h = gy_holes) translate([h[0], h[1], gy_top - 1]) cylinder(d = gy_hole_d - 0.2, h = 1.6);
        }
      }
    }
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
    }
    // antenna outline: a 0.2 mm recess in the ceiling to stick it into
    if (antenna) at_inner() box([ant_x0 - 0.3, ant_y0 - 0.1, in_h - 0.01], [ant_x0 + ant_l + 0.3, ant_y1 + 0.1, in_h + 0.2]);
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

// Vent holes: a square grid over the lid, kept clear of the reset tab, the roots
// of the posts and feet and the skirts. With vents_over_antenna false, it also
// skips the holes the antenna would cover.
module vents() at_inner() {
  m = vent_margin + vent_hole_d / 2;
  led_y = sk_in0 + 0.7 + led_hole_d / 2;
  keep_out = [
    [btn_xy[0] - tab_pad_d / 2 - tab_slot, btn_xy[1] - tab_pad_d / 2 - tab_slot, btn_xy[0] + tab_len + tab_slot, btn_xy[1] + tab_pad_d / 2 + tab_slot],
    // posts and feet, including the corbels that step out under the antenna strip
    [post_x0, 0, post_x1, esp_y0 + post_over], [post_x0, esp_y1 - post_over, post_x1, in_w],
    [fx0, 0, fx1, gy_holes[0][1] + foot_w / 2], [fx0, gy_holes[1][1] - foot_w / 2, fx1, in_w],
    for (c = cleat_xy) [c[0] - cleat_d / 2, c[1] - cleat_d / 2, c[0] + cleat_d / 2, c[1] + cleat_d / 2],
    if (led_row) [esp_x0, led_y - led_hole_d / 2, esp_x1, led_y + led_hole_d / 2],
    if (antenna && !vents_over_antenna) [ant_x0 - 0.3, ant_y0 - 0.1, ant_x0 + ant_l + 0.3, ant_y1 + 0.1]];
  rows = floor((sk_in1 - sk_in0 - 2 * m) / vent_row) + 1;
  y0 = (in_w - (rows - 1) * vent_row) / 2;
  // two blocks: over the SuperMini, and over the module between the posts and the
  // feet. A block's row is drilled only if every hole in it is clear, so the
  // pattern stays a tidy grid instead of a scatter around the keep-outs.
  blocks = [[for (x = [2.5 : vent_pitch : esp_x1 - 1]) x],
            [for (x = [post_x1 + m : vent_pitch : fx0 - m]) x]];
  for (b = blocks, jr = [0 : rows - 1]) {
    y = y0 + jr * vent_row;
    hits = [for (x = b, r = keep_out) if (x > r[0] - m && x < r[2] + m && y > r[1] - m && y < r[3] + m) 1];
    if (len(hits) == 0) for (x = b) translate([x, y, in_h - 1]) {
      cylinder(d = vent_hole_d, h = lid_t + 2, $fn = 24);
      translate([0, 0, 1 + lid_t - vent_chamfer]) cylinder(d1 = vent_hole_d, d2 = vent_hole_d + 2 * vent_chamfer + 0.02, h = vent_chamfer + 0.01, $fn = 24);
    }
  }
  // LED row: smaller holes along the SuperMini's RESET-side edge, where the LED is,
  // between the skirt and the reset tab.
  if (led_row) assert(led_y + led_hole_d / 2 + 0.7 <= btn_xy[1] - tab_pad_d / 2 - tab_slot - tab_chamfer, "LED row hits the reset tab");
  if (led_row) for (x = [esp_x0 + 1.5 : led_pitch : esp_x1 - 1]) translate([x, led_y, in_h - 1]) cylinder(d = led_hole_d, h = lid_t + 2, $fn = 20);
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
  // its parts, from gy_parts below
  color("gray") for (p = gy_parts) {
    h = gy_holes[0];
    box([h[0] - p[3], h[1] + p[0], gy_top], [h[0] - p[2], h[1] + p[1], gy_top + p[4]]);
  }
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
// The cable where it is wound round the posts: one lap, just under the ceiling.
module cable_dummy() if (antenna && cable_posts) color("black") at_inner() translate([0, 0, in_h - 2.2]) linear_extrude(1.2) difference() {
  hull() for (c = cleat_xy) translate(c) circle(d = cleat_d + 2.6);
  hull() for (c = cleat_xy) translate(c) circle(d = cleat_d + 0.2);
}
module tie_dummy() if (strap) color("black") at_inner()
  translate([strap_x - strap_w / 2, -wall - 0.5, 0.2]) cube([strap_w, out_w + 1, strap_h - 0.4]);
module everything_else() { esp_dummy(); gy_dummy(); wires_dummy(); antenna_dummy(); cable_dummy(); tie_dummy(); }

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
  else if (part == "fit") { tray(); esp_dummy(); gy_dummy(); wires_dummy(); tie_dummy(); }
  else if (part == "lid_inside")   // the lid as printed (inside up), with the antenna and the wound cable
    translate([0, out_w, floor_t + in_h + lid_t]) rotate([180, 0, 0]) { color("lightgray") lid(); antenna_dummy(); cable_dummy(); }
  else if (part == "feet") {   // the module from above, with the bottom 2 mm of the lid's feet over it
    gy_dummy();
    color("orangered", 0.8) intersection() { lid(); at_inner() box([gy_x0 + 0.5, -1, gy_top - 1], [in_l + 1, in_w + 1, gy_top + 2]); }
  }
  else if (part == "section") intersection() {
    union() { tray(); lid(); everything_else(); }
    translate([-5, wall + usb_y, -10]) cube([200, 50, 60]);
  }
  else { color("steelblue") tray(); color("white", 0.35) lid(); everything_else(); }
}
