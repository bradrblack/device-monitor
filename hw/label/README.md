# Device Monitor: QR label and getting back to the portal

## Can one code join the Wi-Fi and open the portal?

Yes. The label's QR code is a standard Wi-Fi code for the board's own setup network.
That network is a captive portal, so when a phone joins it the phone opens the
setup page by itself: the "Log in to network" sheet on iPhone, or the "Sign in to
Wi-Fi network" notification on Android. So one scan gets you from the label to the
setup page.

Each board needs its own label. The setup network is `DeviceMonitor-XXXX`, where
XXXX is the last 4 characters of that board's MAC address, and a Wi-Fi QR code
has to name the exact network. The same label keeps working for the life of the
board, because the board opens that same network every time its portal opens.

## Making a label

You need the board's 4 characters. Any of these shows them:
- A new board (purple LED) shows up in your phone's Wi-Fi list as `DeviceMonitor-XXXX`.
- The serial log says `opening the "DeviceMonitor-XXXX" setup portal`.
- A board you haven't renamed has a web page at `devmon-xxxx.local` (the same 4 characters).

Then run:

    pip install qrcode reportlab pillow
    python3 make_label.py 1A2B                  # one board
    python3 make_label.py 1A2B --name washer    # a board you renamed "washer" in the portal
    python3 make_label.py 1A2B 3C4D 5E6F        # several boards: also makes labels-sheet.pdf

The label is 50 x 24 mm with 2 mm round corners, which fits the bottom of both
cases (slide-in 57.8 x 27.6 mm, PCB case 55.8 x 31 mm), and it can cover the bottom of the magnet-mount trays too. Print the PDF at 100% or
"Actual size", not "Fit to page". Plain paper with clear tape or glue works, and
so does sticker paper. `label-1A2B.pdf` and `.png` here are a sample for a board
called DeviceMonitor-1A2B; it won't join a real board.

## Getting back to the portal after first setup

**The everyday web page** (status, settings, alerts, firmware update): open
`http://devmon-xxxx.local/` on any phone or computer on your home Wi-Fi. Use your
device name instead if you renamed it, for example `http://washer.local/`. You
need the admin password to change anything.
If `.local` doesn't open (some Android phones and some routers don't support it),
look up the board's IP address in your router's list of devices, where it shows
under its device name, and open `http://<that IP>/`.

**The Wi-Fi setup portal** (to change the Wi-Fi network, the device name or the
admin password). The board keeps monitoring while the portal is open,
and the portal closes by itself after 5 minutes if nobody uses it.

1. Press the tab in the lid once. The LED flickers white for 5 seconds.
2. Press it again while it's still flickering. The LED now alternates purple.
3. Scan the label on the bottom and join `DeviceMonitor-XXXX`. The setup page opens.
   If it doesn't, open `http://192.168.4.1/` in the browser.
4. Change what you need and tap Save. The board restarts on the new settings.

Or, from the web page: tap **Change Wi-Fi network**, then do steps 3 and 4.

While the portal is open the board's own web page is off. It comes back when the
portal closes.
