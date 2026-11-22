#!/usr/bin/env python3
"""Print-ready QR label for the bottom of the Device Monitor case.

Each board's setup network is DeviceMonitor-XXXX, where XXXX is the last four hex
digits of its MAC, so each board needs its own label.

  python3 make_label.py 1A2B                    # board's default name devmon-1a2b
  python3 make_label.py 1A2B --name washer      # board renamed in the portal
  python3 make_label.py 1A2B 3C4D 5E6F          # several labels on one sheet

Writes label-XXXX.pdf (one label, true size) and label-XXXX.png (600 dpi) per board,
plus labels-sheet.pdf (Letter, all labels with cut marks) when given several.
Print the PDF at 100% / "Actual size". Needs: pip install qrcode reportlab pillow
"""
import argparse, re
import qrcode
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm
from reportlab.lib.pagesizes import letter
from PIL import Image, ImageDraw, ImageFont

W, H = 50.0, 24.0        # mm: fits the 55.8 x 27.6 slide-in case and the 55.8 x 31 PCB case
PAD = 1.6                # mm margin inside the label edge
R = 2.0                  # mm corner radius (the cases' corner_r)
QR_MM = H - 2 * PAD      # QR square, quiet zone included


def wifi_payload(ssid):
    esc = re.sub(r'([\;,:"])', r'\\\1', ssid)
    return f"WIFI:T:nopass;S:{esc};;"   # the setup network is open (no password)


def qr_matrix(data):
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=2)
    q.add_data(data)
    q.make(fit=True)
    return q.get_matrix()     # includes the 2-module quiet zone


def lines_for(code, name):
    return [
        ("b", 7.0, "Device Monitor"),
        ("r", 5.4, "Scan to set up Wi-Fi"),
        ("m", 5.0, f"DeviceMonitor-{code}"),
        ("r", 5.0, "Again later: press the lid"),
        ("r", 5.0, "tab twice (LED flickers)"),
        ("r", 5.0, "Web page:"),
        ("m", 5.0, f"{name}.local"),
    ]


FONTS = {"b": "Helvetica-Bold", "r": "Helvetica", "m": "Courier-Bold"}


def draw_pdf_label(c, x0, y0, code, name, outline=True):
    """Draw one label with its lower-left corner at (x0, y0) mm."""
    if outline:
        c.setLineWidth(0.25)
        c.setStrokeGray(0.6)
        c.roundRect(x0 * mm, y0 * mm, W * mm, H * mm, R * mm, stroke=1, fill=0)
    m = qr_matrix(wifi_payload(f"DeviceMonitor-{code}"))
    n = len(m)
    cell = QR_MM / n
    qx, qy = x0 + PAD, y0 + PAD
    c.setFillGray(0)
    for r, row in enumerate(m):
        for col, on in enumerate(row):
            if on:
                c.rect((qx + col * cell) * mm, (qy + (n - 1 - r) * cell) * mm,
                       cell * mm + 0.01, cell * mm + 0.01, stroke=0, fill=1)
    tx = qx + QR_MM + 0.8
    ls = lines_for(code, name)
    step = (H - 2 * PAD) / len(ls)
    y = y0 + H - PAD - step * 0.78
    for kind, size, text in ls:
        c.setFont(FONTS[kind], size)
        c.drawString(tx * mm, y * mm, text)
        y -= step


def png_label(code, name, path, dpi=600):
    px = lambda v: int(round(v / 25.4 * dpi))
    img = Image.new("RGB", (px(W), px(H)), "white")
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, px(W) - 1, px(H) - 1], radius=px(R), outline=(150, 150, 150), width=3)
    m = qr_matrix(wifi_payload(f"DeviceMonitor-{code}"))
    n = len(m)
    cell = QR_MM / n
    for r, row in enumerate(m):
        for col, on in enumerate(row):
            if on:
                x = PAD + col * cell; y = PAD + r * cell
                d.rectangle([px(x), px(y), px(x + cell) - 1, px(y + cell) - 1], fill="black")
    fontfile = {"b": "DejaVuSans-Bold.ttf", "r": "DejaVuSans.ttf", "m": "DejaVuSansMono-Bold.ttf"}
    ls = lines_for(code, name)
    step = (H - 2 * PAD) / len(ls)
    y = PAD + step * 0.22
    tx = PAD + QR_MM + 0.8
    for kind, size, text in ls:
        try:
            f = ImageFont.truetype(fontfile[kind], int(size / 72 * dpi * 0.93))
        except OSError:
            f = ImageFont.load_default()
        d.text((px(tx), px(y)), text, fill="black", font=f)
        y += step
    img.save(path, dpi=(dpi, dpi))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("codes", nargs="+", help="last 4 hex digits of each board's setup network, e.g. 1A2B")
    ap.add_argument("--name", help="device name if renamed in the portal (one board only)")
    a = ap.parse_args()
    codes = [c.upper() for c in a.codes]
    for c in codes:
        if not re.fullmatch(r"[0-9A-F]{4}", c):
            ap.error(f"{c}: expected 4 hex digits, as in DeviceMonitor-1A2B")
    if a.name and len(codes) > 1:
        ap.error("--name works with one board at a time")
    for c in codes:
        name = a.name or f"devmon-{c.lower()}"
        pdf = canvas.Canvas(f"label-{c}.pdf", pagesize=(W * mm, H * mm))
        pdf.setTitle(f"Device Monitor label {c}")
        draw_pdf_label(pdf, 0, 0, c, name)
        pdf.save()
        png_label(c, name, f"label-{c}.png")
        print(f"label-{c}.pdf, label-{c}.png  ({W:g} x {H:g} mm, network DeviceMonitor-{c}, web {name}.local)")
    if len(codes) > 1:
        pw, ph = letter
        pdf = canvas.Canvas("labels-sheet.pdf", pagesize=letter)
        cols, gap = 3, 6
        x_start = (pw / mm - (cols * W + (cols - 1) * gap)) / 2
        for i, c in enumerate(codes):
            if i and i % (cols * 9) == 0:
                pdf.showPage()
            k = i % (cols * 9)
            draw_pdf_label(pdf, x_start + (k % cols) * (W + gap), ph / mm - 20 - (k // cols + 1) * (H + gap), c, f"devmon-{c.lower()}")
        pdf.save()
        print("labels-sheet.pdf (Letter; print at 100%)")


if __name__ == "__main__":
    main()
