# Perixa Billing - Android app (Flutter / Dart)

Native companion for the PC app. It talks to Perixa Billing Pro on your PC over the same Wi-Fi, so bills, customers and packages are always in sync.

## Get the APK (pick one)
**A. Local (Windows/Linux/Mac with Flutter installed, `flutter doctor` green, plus Python):**
`build_apk.bat`  (or: `python tools/setup_android.py` then `flutter build apk --release`)
APK: `build/app/outputs/flutter-apk/app-release.apk`

**B. GitHub (no setup on your PC):** create a GitHub repo containing the contents of this `mobile` folder, push to `main`.
Actions > "Build APK" runs automatically (or "Run workflow") > download the `Perixa-Billing-APK` artifact.

## Install on the phone
Copy `app-release.apk` to the phone, open it, allow "Install unknown apps" for your file manager/browser.

## Connect
1. PC: Perixa Billing Pro > Settings > Phone > turn on "Allow phones".
2. Phone on the same Wi-Fi > open the app > type the PC address shown there (e.g. 192.168.1.5:5057) + your login.

## What it does
New Bill (customer typed inline with auto-fill, items, packages, discount, coupon, charges, tax, paid-now) - Statement with filters - Bill details with payments / refunds / void / delete / duplicate / convert - Share or print a PDF (A4, built on the phone) - Packages (price + inclusions) - Dashboard.
Editing drafts, Settings, Items/Projects, Coupons, Expenses and Reports stay on the PC.
