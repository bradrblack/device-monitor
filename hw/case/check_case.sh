#!/bin/sh
# Renders the clash checks in device_monitor_case.scad, with and without the bulk cap. Each intersection must have
# zero volume (faces that only touch, like the lid resting on the tray walls or the
# board on its standoffs, are fine). Needs openscad and python3.
cd "$(dirname "$0")"
fail=0
tmp=$(mktemp -d)
for cap in true false; do
EXTRA="-D has_cap=$cap"
for c in clash_lid_tray clash_lid_parts clash_tray_parts; do
  openscad --export-format asciistl -o "$tmp/$c.stl" -D "part=\"$c\"" $EXTRA device_monitor_case.scad >"$tmp/$c.log" 2>&1
  if grep -q "top level object is empty" "$tmp/$c.log"; then echo "has_cap=$cap $c: ok (empty)"; continue; fi
  r=$(python3 - "$tmp/$c.stl" <<'PY'
import re, sys
v = [tuple(map(float, m)) for m in re.findall(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)', open(sys.argv[1]).read())]
vol = sum(a[0]*(b[1]*c[2]-b[2]*c[1]) - a[1]*(b[0]*c[2]-b[2]*c[0]) + a[2]*(b[0]*c[1]-b[1]*c[0])
          for a, b, c in zip(v[0::3], v[1::3], v[2::3])) / 6
if abs(vol) < 1e-3: print("ok")
else:
    xs, ys, zs = (sorted(p[i] for p in v) for i in range(3))
    print("CLASH %.3f mm3 at x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % (abs(vol), xs[0], xs[-1], ys[0], ys[-1], zs[0], zs[-1]))
PY
)
  echo "has_cap=$cap $c: $r"
  [ "$r" = "ok" ] || fail=1
done
done
rm -rf "$tmp"
exit $fail
