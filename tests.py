import os, tempfile, io
os.environ["PERIXA_DATA"] = tempfile.mkdtemp()
import app as A
from datetime import date, timedelta
c = A.app.test_client(); H = {"X-Requested-With": "fetch"}
def call(m, p, j=None, **k): return getattr(c, m)(p, json=j, headers=H, **k)
def ok(r, code=200): assert r.status_code == code, (r.status_code, r.get_data(as_text=True)[:300]); return r.get_json() if r.is_json else r

# access control
assert c.get("/api/e/customers").status_code == 401 and c.get("/doc/1/print").status_code == 401
assert call("post", "/api/login", {"username": "a", "password": "short"}).status_code == 400
ok(call("post", "/api/login", {"username": "deepak", "password": "longenough1"}))
assert c.get("/api/e/customers", headers=H).status_code == 200
assert c.post("/api/e/customers", json={"name": "x"}).status_code == 400  # CSRF header missing

# CRUD
cu = ok(call("post", "/api/e/customers", {"name": "Test Cust", "state": "Tamil Nadu"}))["id"]
cu2 = ok(call("post", "/api/e/customers", {"name": "Other"}))["id"]
assert ok(call("get", "/api/e/customers"))[-1]["code"] == "C0001"
it = ok(call("post", "/api/e/catalogue", {"name": "AI Project", "price": 5000, "tax_rate": 18, "category": "AI/ML"}))["id"]
ok(call("put", f"/api/e/catalogue/{it}", {"price": 5000}))
assert call("post", "/api/e/catalogue", {"name": "Bad", "price": -1}).status_code == 400
assert call("post", "/api/e/coupons", {"code": "X", "kind": "percent", "value": 150}).status_code == 400
k = ok(call("post", "/api/e/coupons", {"code": "save10", "kind": "percent", "value": 10, "min_amount": 1000, "usage_limit": 1, "active": 1}))["id"]
ok(call("put", "/api/settings", {"state": "Tamil Nadu"}))

base = dict(type="invoice", customer_id=cu, project="P", tax_mode="intra",
            items=[dict(name="AI Project", qty=1, rate=5000, tax_rate=18, item_id=it, cat="AI/ML")], disc_type="percent", disc_val=0)
# calculation: 5000 - 10% coupon = 4500 ; GST 18% = 810 ; total 5310
r = ok(call("post", "/api/calc", dict(base, coupon="SAVE10")))
assert r["coupon_disc"] == 500 and r["tax"] == 810 and r["cgst"] == 405 and r["total"] == 5310, r
r = ok(call("post", "/api/calc", dict(base, coupon="NOPE"))); assert "Invalid" in r["coupon_error"] and r["total"] == 5900
r = ok(call("post", "/api/calc", dict(base, coupon="SAVE10", disc_val=5))); assert "combined" in r["coupon_error"]
r = ok(call("post", "/api/calc", dict(base, tax_mode="inter"))); assert r["igst"] == 900 and r["cgst"] == 0
r = ok(call("post", "/api/calc", dict(base, inclusive=1))); assert r["total"] == 5000 and r["subtotal"] == 4237.29, r
r = ok(call("post", "/api/calc", dict(base, charges=[dict(name="Delivery", amount=100, tax_rate=18)]))); assert r["total"] == 6018
r = ok(call("post", "/api/calc", dict(base, tax_mode="none"))); assert r["total"] == 5000

# drafts don't consume coupon; issuing does; limit enforced; numbering
d1 = ok(call("post", "/api/docs", dict(base, coupon="SAVE10")))["id"]
d2 = ok(call("post", "/api/docs", dict(base, coupon="SAVE10")))["id"]
assert ok(call("get", f"/api/docs/{d1}"))["label"] == "Draft"
n1 = ok(call("post", f"/api/docs/{d1}/issue"))["number"]; assert n1.endswith("0001"), n1
assert call("post", f"/api/docs/{d2}/issue").status_code == 400  # usage limit reached
assert call("put", f"/api/docs/{d1}", base).status_code == 400  # issued is immutable
ok(call("put", f"/api/docs/{d2}", base))  # drop coupon
assert ok(call("post", f"/api/docs/{d2}/issue"))["number"].endswith("0002")
assert call("delete", f"/api/e/coupons/{k}").status_code == 400

# payments: partial, overpay, status, refund
inv = ok(call("get", f"/api/docs/{d1}")); assert inv["total"] == 5310 and inv["label"] == "Unpaid" and inv["due_date"]
ok(call("post", f"/api/docs/{d1}/payments", {"amount": 2000, "method": "upi"}))
inv = ok(call("get", f"/api/docs/{d1}")); assert inv["label"] == "Partially Paid" and inv["balance"] == 3310
assert call("post", f"/api/docs/{d1}/payments", {"amount": 9999}).status_code == 400
assert call("post", f"/api/docs/{d1}/void").status_code == 400  # has payments
ok(call("post", f"/api/docs/{d1}/payments", {"amount": 3310}))
assert ok(call("get", f"/api/docs/{d1}"))["label"] == "Paid"
ok(call("post", f"/api/docs/{d1}/payments", {"amount": 100, "kind": "refund"}))
pid = ok(call("get", "/api/payments"))[0]["id"]
assert b"Refund Receipt" in c.get(f"/receipt/{pid}/print").data

# overdue
dd = ok(call("post", "/api/docs", dict(base, issue_date=(date.today() - timedelta(days=30)).isoformat())))["id"]
ok(call("post", f"/api/docs/{dd}/issue"))
assert ok(call("get", f"/api/docs/{dd}"))["label"] == "Overdue"

# quotation -> invoice, no duplicate sale
q = ok(call("post", "/api/docs", dict(base, type="quotation")))["id"]
assert call("post", f"/api/docs/{q}/convert").status_code == 400  # must issue first
qn = ok(call("post", f"/api/docs/{q}/issue"))["number"]; assert "QT" in qn
ni = ok(call("post", f"/api/docs/{q}/convert"))["id"]
assert call("post", f"/api/docs/{q}/convert").status_code == 400
assert ok(call("get", f"/api/docs/{q}"))["label"] == "Converted"
dup = ok(call("post", f"/api/docs/{ni}/duplicate"))["id"]; assert dup != ni
ok(call("delete", f"/api/docs/{dup}"))

# void releases coupon usage
ok(call("post", f"/api/docs/{ni}/issue")); ok(call("post", f"/api/docs/{ni}/void"))
assert ok(call("get", f"/api/docs/{ni}"))["label"] == "Cancelled"

# print / pdf-ready page, dashboard, reports
html = c.get(f"/doc/{d1}/print").get_data(as_text=True); assert n1 in html and "Test Cust" in html and "CGST" in html
assert "Delivery Note" in c.get(f"/doc/{d1}/print?dn=1").get_data(as_text=True)
dash = ok(call("get", "/api/dashboard")); assert dash["S"]["invoiced"] > 0 and dash["S"]["overdue_n"] == 1
ok(call("post", "/api/e/expenses", {"date": "2026-01-01", "amount": 100}))
for kind in A.REPORTS:
    r = ok(call("get", f"/api/report?kind={kind}")); assert r["cols"]
assert ok(call("get", "/api/report?kind=sales&csv=1")).get_data(as_text=True).startswith("Invoice")

# backup / restore persistence
bk = ok(call("get", "/api/backup")).data
ok(call("post", "/api/e/customers", {"name": "Added after backup"}))
ok(call("post", "/api/restore", data={"file": (io.BytesIO(bk), "b.db")}, content_type="multipart/form-data"))
assert all(x["name"] != "Added after backup" for x in ok(call("get", "/api/e/customers")))
assert call("post", "/api/restore", data={"file": (io.BytesIO(b"junk"), "b.db")}, content_type="multipart/form-data").status_code == 400
# upload safety
assert call("post", "/api/upload", data={"file": (io.BytesIO(b"x"), "a.exe")}, content_type="multipart/form-data").status_code == 400
assert len(ok(call("get", "/api/audit"))) > 10
print("ALL TESTS PASSED")

# inline customer on the bill: creates once, reuses on same name, updates details
r1 = ok(call("post", "/api/docs", dict(type="invoice", customer={"name": "Walk In", "phone": "999", "state": "Kerala"}, items=[dict(name="X", qty=1, rate=100, tax_rate=0)])))["id"]
r2 = ok(call("post", "/api/docs", dict(type="invoice", customer={"name": "walk in", "phone": "999", "city": "Kochi"}, items=[dict(name="Y", qty=1, rate=50, tax_rate=0)])))["id"]
assert ok(call("get", f"/api/docs/{r1}"))["customer_id"] == ok(call("get", f"/api/docs/{r2}"))["customer_id"]
assert ok(call("get", f"/api/docs/{r2}"))["customer"]["city"] == "Kochi"
assert call("post", "/api/docs", dict(type="invoice", customer={}, items=[dict(name="Y", qty=1, rate=5)])).status_code == 400
print("INLINE CUSTOMER OK")

# delete any bill; quotation reverts; tiers validation; project upload
pk = ok(call("post", "/api/e/presets", {"name": "Full Kit", "price": 7000, "tax_rate": 18, "includes": "Source code\nReport\nPPT"}))["id"]
assert ok(call("get", "/api/e/presets"))[0]["includes"].startswith("Source")
pd = ok(call("post", "/api/docs", dict(base, items=[dict(name="Proj - Full Kit", desc="Source code\nReport\nPPT", qty=1, rate=7000, tax_rate=18)])))["id"]
ok(call("post", f"/api/docs/{pd}/issue")); assert "Report" in c.get(f"/doc/{pd}/print").get_data(as_text=True)
up = ok(call("post", "/api/upload?kind=project", data={"file": (io.BytesIO(b"PK"), "my proj.zip")}, content_type="multipart/form-data"))["name"]
assert up.endswith("my_proj.zip") and c.get("/uploads/" + up).status_code == 200
assert call("post", "/api/upload?kind=project", data={"file": (io.BytesIO(b"x"), "a.exe")}, content_type="multipart/form-data").status_code == 400
q2 = ok(call("post", "/api/docs", dict(base, type="quotation")))["id"]; ok(call("post", f"/api/docs/{q2}/issue"))
i2 = ok(call("post", f"/api/docs/{q2}/convert"))["id"]; ok(call("post", f"/api/docs/{i2}/issue"))
ok(call("post", f"/api/docs/{i2}/payments", {"amount": 100}))
ok(call("delete", f"/api/docs/{i2}"))
assert call("get", f"/api/docs/{i2}").status_code == 404
assert ok(call("get", f"/api/docs/{q2}"))["status"] == "sent"
print("PACKAGES/DELETE/UPLOAD OK")

# phone / LAN access gate
lan = {"REMOTE_ADDR": "192.168.1.50"}
assert c.get("/api/ping", environ_overrides=lan).status_code == 403          # off by default
ok(call("put", "/api/settings", {"phone_access": "1"}))
assert c.get("/api/ping", environ_overrides=lan).status_code == 200 and c.get("/", environ_overrides=lan).status_code == 200
assert c.get("/api/ping", environ_overrides={"REMOTE_ADDR": "8.8.8.8"}).status_code == 403   # never from public internet
assert "urls" in ok(call("get", "/api/phone"))
ok(call("put", "/api/settings", {"phone_access": "0"}))
assert c.get("/api/ping", environ_overrides=lan).status_code == 403
print("PHONE GATE OK")
