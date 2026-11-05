# Perixa Billing Pro
Private billing system. Flask + SQLite, one dependency, no build step.

**Desktop app (like MedBill Pro):** on Windows with Python 3 + Node.js installed, double-click `build.bat`. It builds `release\Perixa Billing Pro Setup 1.0.0.exe` (installer with desktop shortcut). Data is stored in `%APPDATA%\Perixa Billing Pro\data`. For development: `npm install` then `npm start`.

**Run in browser instead:** `pip install -r requirements.txt` then `python app.py` -> http://127.0.0.1:5000 (Windows: double-click `run.bat`).
First visit asks you to create the single admin login (no public registration). Data: `data/perixa.db` (persists across restarts).
**Sample data:** `python app.py seed` (fictional). **Tests:** `python tests.py`.
**PDF:** open any invoice -> Print / PDF -> choose "Save as PDF" (A4 layout).
**Set first:** Business Settings (state, GSTIN, payment instructions, terms, logo).

Notes
- Money uses Python `Decimal`; discounts apply before tax; coupons are validated on the server and consume usage only when an invoice is *issued*.
- Issued invoices are locked: void (only when net payments are 0) or duplicate. Refunds are recorded separately.
- GST is configurable (CGST+SGST / IGST / none, inclusive or exclusive). It is a calculator, not a compliance check - verify with your CA.
- Troubleshooting: port busy -> change the port at the bottom of app.py; forgot password -> delete the row in `users` (sqlite3 data/perixa.db "delete from users") and re-run setup; locked after 5 bad logins -> wait 5 minutes.

## Using it
- **New Bill**: type the customer (pick an existing name to auto-fill), type items, Enter, set 'Paid now', Save & Issue.
- **Statement**: all bills with totals, filters, print and CSV.
- **Settings**: business, customers, items, packages, coupons, expenses, deals, backup, audit log.

- Bills can be deleted (Statement row or bill page). Packages (own menu): name, price, tax and what is included. Upload project files in Settings > Items or on New Bill.

## Phone (same Wi-Fi)
Settings > Phone > turn on "Allow phones". Scan the QR code on your phone (same Wi-Fi), sign in, then Chrome menu > Add to Home screen.
The phone uses the PC's data live, so bills and all details are always in sync. The PC must be on with the app open.
Allow "Private networks" if Windows Firewall asks. Phone access is limited to private Wi-Fi addresses, needs your login, and is off by default.

## Android app
See mobile/README.md (Flutter project + one-command APK build).
