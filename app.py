"""Perixa Billing Pro - private billing system for Perixa Technologies. Flask + SQLite."""
import os, sys, json, sqlite3, secrets, csv, io, time, shutil, socket, ipaddress
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from functools import wraps
from flask import (Flask, g, request, session, jsonify, render_template, send_file,
                   send_from_directory, Response, has_request_context)
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
try:
    import segno
except ImportError:  # QR code is optional
    segno = None

BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("PERIXA_DATA", os.path.join(BASE, "data"))
UP = os.path.join(DATA, "uploads")
os.makedirs(UP, exist_ok=True)
DB = os.path.join(DATA, "perixa.db")

app = Flask(__name__)
_kf = os.path.join(DATA, "secret.key")
if not os.path.exists(_kf):
    open(_kf, "w").write(secrets.token_hex(32))
app.secret_key = open(_kf).read().strip()
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Strict",
                  PERMANENT_SESSION_LIFETIME=timedelta(hours=8), MAX_CONTENT_LENGTH=256 * 1024 * 1024)

# ---------------------------------------------------------------- database
MIGRATIONS = ["""
CREATE TABLE users(id INTEGER PRIMARY KEY, username TEXT UNIQUE, pw TEXT);
CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE counters(k TEXT PRIMARY KEY, v INTEGER);
CREATE TABLE customers(id INTEGER PRIMARY KEY, code TEXT UNIQUE, name TEXT NOT NULL, type TEXT, org TEXT, course TEXT,
  dept TEXT, phone TEXT, email TEXT, address TEXT, city TEXT, state TEXT, pin TEXT, gstin TEXT, notes TEXT, archived INTEGER DEFAULT 0);
CREATE TABLE catalogue(id INTEGER PRIMARY KEY, name TEXT NOT NULL, kind TEXT, category TEXT, description TEXT, stack TEXT,
  complexity TEXT, delivery_days INTEGER, price REAL DEFAULT 0, min_price REAL, tax_rate REAL DEFAULT 18, support_terms TEXT, active INTEGER DEFAULT 1);
CREATE TABLE presets(id INTEGER PRIMARY KEY, name TEXT NOT NULL, items TEXT DEFAULT '', active INTEGER DEFAULT 1);
CREATE TABLE coupons(id INTEGER PRIMARY KEY, code TEXT UNIQUE NOT NULL, kind TEXT DEFAULT 'percent', value REAL NOT NULL,
  starts TEXT, expires TEXT, min_amount REAL DEFAULT 0, max_discount REAL, usage_limit INTEGER, per_customer INTEGER,
  categories TEXT, item_ids TEXT, customer_ids TEXT, combine_manual INTEGER DEFAULT 0, active INTEGER DEFAULT 1);
CREATE TABLE deals(id INTEGER PRIMARY KEY, title TEXT NOT NULL, customer_id INTEGER REFERENCES customers(id), status TEXT DEFAULT 'Lead',
  requirements TEXT, scope TEXT, deliverables TEXT, original_quote REAL, negotiated REAL, discount REAL, advance REAL,
  schedule TEXT, starts TEXT, delivery TEXT, revisions TEXT, support TEXT, licensing TEXT, cancellation TEXT, notes TEXT);
CREATE TABLE docs(id INTEGER PRIMARY KEY, type TEXT NOT NULL, number TEXT, status TEXT DEFAULT 'draft',
  customer_id INTEGER REFERENCES customers(id), deal_id INTEGER, project TEXT, project_type TEXT, issue_date TEXT, due_date TEXT,
  valid_until TEXT, delivery TEXT, payment_terms TEXT, notes TEXT, terms TEXT, items TEXT, charges TEXT, disc_type TEXT, disc_val REAL,
  coupon TEXT, tax_mode TEXT, inclusive INTEGER, round_off INTEGER, subtotal REAL, disc_total REAL, coupon_disc REAL, tax REAL,
  charges_total REAL, round_amt REAL, net_value REAL, total REAL, converted_from INTEGER, snap TEXT, created TEXT);
CREATE UNIQUE INDEX docs_number ON docs(number);
CREATE TABLE payments(id INTEGER PRIMARY KEY, doc_id INTEGER NOT NULL REFERENCES docs(id), receipt TEXT, date TEXT, amount REAL,
  method TEXT, ref TEXT, notes TEXT, kind TEXT DEFAULT 'payment');
CREATE TABLE coupon_usage(id INTEGER PRIMARY KEY, coupon_id INTEGER, doc_id INTEGER, customer_id INTEGER, date TEXT, amount REAL, voided INTEGER DEFAULT 0);
CREATE TABLE expenses(id INTEGER PRIMARY KEY, date TEXT, category TEXT, vendor TEXT, amount REAL, notes TEXT, receipt TEXT);
CREATE TABLE audit(id INTEGER PRIMARY KEY, ts TEXT, user TEXT, action TEXT, detail TEXT);
""", """
ALTER TABLE catalogue ADD COLUMN tiers TEXT;
ALTER TABLE catalogue ADD COLUMN file TEXT;
""", """
ALTER TABLE presets ADD COLUMN price REAL DEFAULT 0;
ALTER TABLE presets ADD COLUMN tax_rate REAL DEFAULT 18;
ALTER TABLE presets ADD COLUMN includes TEXT;
"""]

DEFAULTS = dict(biz_name="Perixa Technologies", owner="", address="", phone="", email="", website="", gstin="", pan="",
                state="", logo="", signature="", inv_prefix="PTX-INV-", quo_prefix="PTX-QT-", pf_prefix="PTX-PF-",
                rcp_prefix="PTX-RC-", currency="₹", default_tax="18", due_days="7", pay_instr="",
                footer="Thank you for your business.", terms="", accent="#c9a227", show_logo="1", phone_access="0")


def connect(path=None):
    c = sqlite3.connect(path or DB, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA foreign_keys=ON")
    return c


def migrate(c):
    v = c.execute("PRAGMA user_version").fetchone()[0]
    for i in range(v, len(MIGRATIONS)):
        c.executescript("BEGIN;" + MIGRATIONS[i] + f"PRAGMA user_version={i + 1};COMMIT;")


def db():
    if "db" not in g:
        g.db = connect()
    return g.db


@app.teardown_appcontext
def _close(_):
    d = g.pop("db", None)
    if d:
        d.close()


@contextmanager
def tx(c):
    c.execute("BEGIN IMMEDIATE")
    try:
        yield
        c.execute("COMMIT")
    except BaseException:
        c.execute("ROLLBACK")
        raise


def settings(c):
    s = dict(DEFAULTS)
    s.update({r["k"]: r["v"] for r in c.execute("select k,v from settings")})
    return s


def audit(c, action, detail=""):
    who = session.get("u", "system") if has_request_context() else "system"
    c.execute("insert into audit(ts,user,action,detail) values(?,?,?,?)",
              (datetime.now().isoformat(" ", "seconds"), who, action, str(detail)[:500]))


def next_no(c, key):
    c.execute("insert into counters(k,v) values(?,1) on conflict(k) do update set v=v+1", (key,))
    return c.execute("select v from counters where k=?", (key,)).fetchone()[0]


today = lambda: date.today().isoformat()
csvl = lambda s: [x.strip() for x in (s or "").split(",") if x.strip()]

# ---------------------------------------------------------------- money
def D(x):
    try:
        d = Decimal(str(x if x not in (None, "") else 0))
    except Exception:
        raise ValueError("Invalid number")
    if not d.is_finite():
        raise ValueError("Invalid number")
    return d


q = lambda x: x.quantize(Decimal("0.01"), ROUND_HALF_UP)


def fl(o):
    if isinstance(o, Decimal): return float(o)
    if isinstance(o, dict): return {k: fl(v) for k, v in o.items()}
    if isinstance(o, list): return [fl(v) for v in o]
    return o


def alloc(total, parts):
    s, out, rem = sum(parts, Decimal(0)), [Decimal(0)] * len(parts), total
    if s <= 0 or total <= 0: return out
    last = max(i for i, p in enumerate(parts) if p > 0)
    for i, p in enumerate(parts):
        if p > 0:
            out[i] = rem if i == last else q(total * p / s)
            rem -= out[i]
    return out


def coupon_apply(c, code, cust, L, sub, md, doc_id):
    k = c.execute("select * from coupons where code=?", (code,)).fetchone()
    t = today()
    if not k: raise ValueError("Invalid coupon code")
    if not k["active"]: raise ValueError("This coupon is inactive")
    if k["starts"] and t < k["starts"]: raise ValueError("This coupon is not valid yet")
    if k["expires"] and t > k["expires"]: raise ValueError("This coupon has expired")
    if sub < D(k["min_amount"]): raise ValueError(f"Minimum invoice amount of {k['min_amount']:g} required for this coupon")
    ids, cats, cus = csvl(k["item_ids"]), [x.lower() for x in csvl(k["categories"])], csvl(k["customer_ids"])
    if cus and str(cust) not in cus: raise ValueError("This coupon is not valid for this customer")
    elig = [(not ids and not cats) or str(l["item_id"]) in ids or l["cat"].lower() in cats for l in L]
    if not any(elig): raise ValueError("No items on this invoice are eligible for this coupon")
    if md > 0 and not k["combine_manual"]: raise ValueError("This coupon cannot be combined with a manual discount")
    ex = doc_id or 0
    if k["usage_limit"] and c.execute("select count(*) from coupon_usage where coupon_id=? and voided=0 and doc_id!=?",
                                      (k["id"], ex)).fetchone()[0] >= k["usage_limit"]:
        raise ValueError("Coupon usage limit reached")
    if k["per_customer"]:
        if not cust: raise ValueError("Select a customer to use this coupon")
        if c.execute("select count(*) from coupon_usage where coupon_id=? and customer_id=? and voided=0 and doc_id!=?",
                     (k["id"], cust, ex)).fetchone()[0] >= k["per_customer"]:
            raise ValueError("Per-customer limit reached for this coupon")
    eb = sum((l["base"] for l, e in zip(L, elig) if e), Decimal(0))
    if sub > 0: eb = q(eb - md * eb / sub)
    v = D(k["value"])
    cd = q(eb * v / 100) if k["kind"] == "percent" else min(v, eb)
    if k["max_discount"]: cd = min(cd, D(k["max_discount"]))
    desc = f"{code}: {v:g}% off" if k["kind"] == "percent" else f"{code}: {v:g} off"
    return min(cd, eb), elig, desc, k["id"]


def calc(c, d, doc_id=None, strict=True):
    inc = bool(int(d.get("inclusive") or 0))
    mode = d.get("tax_mode") or "intra"
    if mode not in ("intra", "inter", "none"): raise ValueError("Bad tax mode")
    L = []
    for it in d.get("items") or []:
        name = (it.get("name") or "").strip()
        if not name: raise ValueError("Every line needs a name")
        qty, rate, disc, tr = D(it.get("qty", 1)), D(it.get("rate")), D(it.get("disc")), D(it.get("tax_rate"))
        if qty <= 0 or rate < 0 or not 0 <= disc <= 100 or not 0 <= tr <= 100:
            raise ValueError(f'Invalid values in line "{name}"')
        gross = q(qty * rate)
        net = gross - q(gross * disc / 100)
        L.append(dict(name=name, desc=str(it.get("desc") or "").strip(), qty=qty, rate=rate, disc=disc, tax_rate=tr, item_id=it.get("item_id") or None,
                      cat=it.get("cat") or "", gross=gross, base=q(net / (1 + tr / 100)) if inc else net))
    sub = sum((l["base"] for l in L), Decimal(0))
    dt, dv = d.get("disc_type") or "percent", D(d.get("disc_val"))
    if dv < 0 or (dt == "percent" and dv > 100): raise ValueError("Invalid discount")
    md = q(sub * dv / 100) if dt == "percent" else min(q(dv), sub)
    cd, elig, cinfo, cerr, cid = Decimal(0), [False] * len(L), "", "", None
    code = (d.get("coupon") or "").strip().upper()
    if code:
        try:
            cd, elig, cinfo, cid = coupon_apply(c, code, d.get("customer_id"), L, sub, md, doc_id)
        except ValueError as e:
            if strict: raise
            cerr, code = str(e), ""
    bases = [l["base"] for l in L]
    mdi, cdi = alloc(md, bases), alloc(cd, [b if e else Decimal(0) for b, e in zip(bases, elig)])
    tax = Decimal(0)
    for l, m, k in zip(L, mdi, cdi):
        l["taxable"] = l["base"] - m - k
        l["tax"] = q(l["taxable"] * l["tax_rate"] / 100) if mode != "none" else Decimal(0)
        tax += l["tax"]
    ch, chs = [], Decimal(0)
    for x in d.get("charges") or []:
        a, r = D(x.get("amount")), D(x.get("tax_rate"))
        if a < 0 or not 0 <= r <= 100: raise ValueError("Invalid additional charge")
        if a == 0: continue
        t = q(a * r / 100) if mode != "none" else Decimal(0)
        ch.append(dict(name=(x.get("name") or "Charge").strip(), amount=a, tax_rate=r, tax=t))
        chs += a
        tax += t
    raw = sub - md - cd + chs + tax
    tot = raw.quantize(Decimal(1), ROUND_HALF_UP) if int(d.get("round_off", 1) or 0) else raw
    cg = q(tax / 2) if mode == "intra" else Decimal(0)
    return fl(dict(lines=L, charges=ch, subtotal=sub, disc_total=md, coupon_disc=cd, tax=tax, cgst=cg,
                   sgst=tax - cg if mode == "intra" else 0, igst=tax if mode == "inter" else 0, charges_total=chs,
                   round_amt=tot - raw, net_value=sub - md - cd + chs, total=tot, coupon=code, coupon_id=cid,
                   coupon_info=cinfo, coupon_error=cerr))


def status_label(d, paid, refunded):
    st = d["status"]
    if d["type"] != "invoice" or st != "issued": return {"draft": "Draft", "void": "Cancelled", "sent": "Sent",
                                                           "converted": "Converted", "issued": "Issued"}.get(st, st)
    net = paid - refunded
    if refunded > 0 and net <= 0: return "Refunded"
    if net >= d["total"] - 0.005: return "Paid"
    if d["due_date"] and d["due_date"] < today(): return "Overdue"
    return "Partially Paid" if net > 0 else "Unpaid"


DOCSQL = ("select d.*, c.name cname, coalesce((select sum(amount) from payments where doc_id=d.id and kind='payment'),0) paid, "
          "coalesce((select sum(amount) from payments where doc_id=d.id and kind='refund'),0) refunded "
          "from docs d left join customers c on c.id=d.customer_id ")


def docdict(r):
    d = dict(r)
    d["items"], d["charges"] = json.loads(d["items"] or "[]"), json.loads(d["charges"] or "[]")
    d.pop("snap", None)
    if "paid" in d:
        d["net_paid"] = round(d["paid"] - d["refunded"], 2)
        d["balance"] = round(d["total"] - d["net_paid"], 2) if d["status"] == "issued" and d["type"] == "invoice" else 0
        d["label"] = status_label(d, d["paid"], d["refunded"])
    return d

# ---------------------------------------------------------------- auth / helpers
_fails = {}


def api(f):
    @wraps(f)
    def w(*a, **k):
        if "u" not in session: return jsonify(error="Login required"), 401
        if request.method != "GET" and request.headers.get("X-Requested-With") != "fetch":
            return jsonify(error="Bad request"), 400
        try:
            return f(*a, **k)
        except ValueError as e:
            return jsonify(error=str(e)), 400
        except sqlite3.IntegrityError as e:
            return jsonify(error="Duplicate or invalid data: " + str(e)), 400
    return w


@app.after_request
def _hdr(r):
    r.headers["X-Content-Type-Options"] = "nosniff"
    r.headers["X-Frame-Options"] = "DENY"
    r.headers["Cache-Control"] = "no-store" if request.path.startswith(("/api", "/doc", "/receipt")) else r.headers.get("Cache-Control", "no-cache")
    return r


@app.before_request
def _lan_gate():
    """Phones on the same private network may connect only when enabled in Settings > Phone."""
    ip = request.remote_addr or ""
    if ip in ("127.0.0.1", "::1"): return
    try: private = ipaddress.ip_address(ip).is_private
    except ValueError: private = False
    if not private: return "Forbidden", 403
    if settings(db())["phone_access"] != "1": return "Phone access is turned off on the PC (Settings > Phone).", 403


@app.get("/api/ping")
def ping():
    return jsonify(ok=1)


def lan_ips():
    out = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(("10.255.255.255", 1)); out.append(s.getsockname()[0]); s.close()
    except Exception: pass
    try: out += [i[4][0] for i in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)]
    except Exception: pass
    seen = []
    for i in out:
        if i not in seen and not i.startswith(("127.", "169.254", "0.")): seen.append(i)
    return seen


@app.get("/api/phone")
@api
def phone_info():
    on = settings(db())["phone_access"] == "1"
    port = int(os.environ.get("PERIXA_PORT", 5000))
    urls = [f"http://{i}:{port}" for i in lan_ips()] if on else []
    qr = segno.make(urls[0], error="m").svg_inline(scale=5, dark="#0b1f44", border=2) if urls and segno else ""
    return jsonify(enabled=on, urls=urls, qr=qr)


@app.route("/")
def index():
    if "u" not in session:
        return render_template("login.html", setup=not connect().execute("select 1 from users").fetchone())
    return render_template("index.html")


@app.route("/favicon.ico")
def fav():
    return send_from_directory(os.path.join(BASE, "static"), "favicon.ico")


@app.post("/api/login")
def login():
    j, ip = request.get_json(silent=True) or {}, request.remote_addr
    n, t = _fails.get(ip, (0, 0))
    if n >= 5 and time.time() - t < 300: return jsonify(error="Too many attempts. Wait 5 minutes."), 429
    c = db()
    if request.headers.get("X-Requested-With") != "fetch": return jsonify(error="Bad request"), 400
    if not c.execute("select 1 from users").fetchone():  # first-run setup, one admin only
        pw = j.get("password") or ""
        if len(pw) < 8 or not (j.get("username") or "").strip(): return jsonify(error="Username required, password min 8 characters"), 400
        c.execute("insert into users(username,pw) values(?,?)", (j["username"].strip(), generate_password_hash(pw)))
        audit(c, "setup", j["username"])
    u = c.execute("select * from users where username=?", ((j.get("username") or "").strip(),)).fetchone()
    if not u or not check_password_hash(u["pw"], j.get("password") or ""):
        _fails[ip] = (n + 1, time.time())
        return jsonify(error="Wrong username or password"), 401
    _fails.pop(ip, None)
    session.clear()
    session.permanent = True
    session["u"] = u["username"]
    audit(c, "login")
    return jsonify(ok=1)


@app.post("/api/logout")
def logout():
    session.clear()
    return jsonify(ok=1)


@app.post("/api/password")
@api
def password():
    j, c = request.get_json() or {}, db()
    u = c.execute("select * from users where username=?", (session["u"],)).fetchone()
    if not check_password_hash(u["pw"], j.get("old") or ""): raise ValueError("Current password is wrong")
    if len(j.get("new") or "") < 8: raise ValueError("New password must be at least 8 characters")
    c.execute("update users set pw=? where id=?", (generate_password_hash(j["new"]), u["id"]))
    audit(c, "password changed")
    return jsonify(ok=1)

# ---------------------------------------------------------------- generic CRUD
N = lambda s: s.split()
ENT = {
    "customers": dict(cols=N("code name type org course dept phone email address city state pin gstin notes"), req=["name"], num=[]),
    "catalogue": dict(cols=N("name kind category description stack complexity delivery_days price min_price tax_rate support_terms active file"),
                      req=["name"], num=N("delivery_days price min_price tax_rate active")),
    "presets": dict(cols=N("name price tax_rate includes active"), req=["name"], num=N("price tax_rate active")),
    "coupons": dict(cols=N("code kind value starts expires min_amount max_discount usage_limit per_customer categories item_ids customer_ids combine_manual active"),
                    req=["code", "value"], num=N("value min_amount max_discount usage_limit per_customer combine_manual active")),
    "expenses": dict(cols=N("date category vendor amount notes receipt"), req=["date", "amount"], num=["amount"]),
    "deals": dict(cols=N("title customer_id status requirements scope deliverables original_quote negotiated discount advance schedule starts delivery revisions support licensing cancellation notes"),
                  req=["title"], num=N("customer_id original_quote negotiated discount advance")),
}
DEAL_ST = ["Lead", "Quoted", "Negotiation", "Accepted", "In Progress", "Awaiting Payment", "Partially Paid", "Completed", "Cancelled", "Refunded"]


def clean(ent, j):
    E, out = ENT[ent], {}
    for col in E["cols"]:
        if col not in j: continue
        v = j[col]
        if col in E["num"]:
            try: v = None if v in ("", None) else float(v)
            except (TypeError, ValueError): raise ValueError(f"Invalid number for {col}")
            if v is not None and (v < 0 or v != v): raise ValueError(f"{col} cannot be negative")
        else:
            v = (str(v) if v is not None else "").strip()
        out[col] = v
    if ent == "coupons":
        if "code" in out: out["code"] = out["code"].upper().replace(" ", "")
        if out.get("kind", "percent") == "percent" and (out.get("value") or 0) > 100: raise ValueError("Percentage cannot exceed 100")
    if ent == "deals" and out.get("status", "Lead") not in DEAL_ST: raise ValueError("Bad deal status")
    return out


@app.route("/api/e/<ent>", methods=["GET", "POST"])
@app.route("/api/e/<ent>/<int:i>", methods=["PUT", "DELETE"])
@api
def crud(ent, i=None):
    if ent not in ENT: return jsonify(error="Not found"), 404
    c = db()
    if request.method == "GET":
        return jsonify([dict(r) for r in c.execute(f"select * from {ent} order by id desc")])
    if request.method == "DELETE":
        if ent == "customers":
            c.execute("update customers set archived=1-archived where id=?", (i,)); msg = "archive toggled"
        else:
            if ent == "coupons" and c.execute("select 1 from coupon_usage where coupon_id=?", (i,)).fetchone():
                raise ValueError("Coupon has been used - deactivate it instead")
            if ent == "deals" and c.execute("select 1 from docs where deal_id=?", (i,)).fetchone():
                raise ValueError("Deal has documents - set status to Cancelled instead")
            c.execute(f"delete from {ent} where id=?", (i,)); msg = "deleted"
        audit(c, f"{ent} {msg}", i)
        return jsonify(ok=1)
    d = clean(ent, request.get_json() or {})
    for r in ENT[ent]["req"]:
        if d.get(r) in (None, "") and (request.method == "POST" or r in d): raise ValueError(f"{r} is required")
    if request.method == "POST":
        if ent == "customers" and not d.get("code"): d["code"] = f"C{next_no(c, 'cust'):04d}"
        k = list(d)
        i = c.execute(f"insert into {ent}({','.join(k)}) values({','.join('?' * len(k))})", [d[x] for x in k]).lastrowid
        audit(c, f"{ent} created", i)
    else:
        if d: c.execute(f"update {ent} set {','.join(x + '=?' for x in d)} where id=?", [*d.values(), i])
        audit(c, f"{ent} updated", i)
    return jsonify(id=i)

# ---------------------------------------------------------------- documents
DOCCOLS = N("type customer_id deal_id project project_type issue_date due_date valid_until delivery payment_terms notes terms "
            "disc_type disc_val coupon tax_mode inclusive round_off")
PFX = dict(invoice="inv_prefix", quotation="quo_prefix", proforma="pf_prefix")


def totals_cols(r):
    return dict(items=json.dumps(r["lines"]), charges=json.dumps(r["charges"]), coupon=r["coupon"],
                **{k: r[k] for k in N("subtotal disc_total coupon_disc tax charges_total round_amt net_value total")})


def resolve_customer(c, d):
    """Customer typed on the bill: reuse an existing one (same name [+phone]) or create it; update details."""
    cu = d.get("customer") or {}
    name = (cu.get("name") or "").strip()
    cid = d.get("customer_id")
    if not cid and name:
        ph = (cu.get("phone") or "").strip()
        r = c.execute("select id from customers where lower(name)=lower(?) and archived=0 and (?='' or phone=?)", (name, ph, ph)).fetchone()
        cid = r["id"] if r else c.execute("insert into customers(code,name) values(?,?)", (f"C{next_no(c, 'cust'):04d}", name)).lastrowid
    if not cid: raise ValueError("Enter the customer name")
    v = {k: str(cu[k]).strip() for k in N("name org phone email address city state pin gstin") if k in cu}
    if v.get("name") == "": v.pop("name")
    if v: c.execute(f"update customers set {','.join(k + '=?' for k in v)} where id=?", [*v.values(), cid])
    return int(cid)


def save_doc(c, d, doc_id=None):
    typ = d.get("type") or "invoice"
    if typ not in PFX: raise ValueError("Bad document type")
    d["customer_id"] = resolve_customer(c, d)
    if not (d.get("items") or []): raise ValueError("Add at least one item")
    if doc_id:
        cur = c.execute("select status from docs where id=?", (doc_id,)).fetchone()
        if not cur: raise ValueError("Not found")
        if cur["status"] != "draft": raise ValueError("Issued documents cannot be edited. Duplicate it, or void it and re-issue.")
    r = calc(c, d, doc_id, strict=True)
    v = {k: d.get(k) for k in DOCCOLS}
    v.update(type=typ, customer_id=int(d["customer_id"]), deal_id=d.get("deal_id") or None, inclusive=int(d.get("inclusive") or 0),
             round_off=int(d.get("round_off", 1) or 0), disc_val=float(d.get("disc_val") or 0), disc_type=d.get("disc_type") or "percent",
             tax_mode=d.get("tax_mode") or "intra", issue_date=d.get("issue_date") or today(), **totals_cols(r))
    if doc_id:
        c.execute(f"update docs set {','.join(k + '=?' for k in v)} where id=?", [*v.values(), doc_id])
    else:
        v["created"] = datetime.now().isoformat(" ", "seconds")
        doc_id = c.execute(f"insert into docs({','.join(v)}) values({','.join('?' * len(v))})", list(v.values())).lastrowid
    audit(c, f"{typ} draft saved", doc_id)
    return doc_id


def do_issue(c, i):
    with tx(c):
        d = c.execute("select * from docs where id=?", (i,)).fetchone()
        if not d: raise ValueError("Not found")
        if d["status"] != "draft": raise ValueError("Already issued")
        data = dict(d)
        data["items"], data["charges"] = json.loads(d["items"]), json.loads(d["charges"])
        # recompute inside the transaction so coupon limits are validated atomically
        data["items"] = [dict(x, rate=x["rate"]) for x in data["items"]]
        r = calc(c, data, i, strict=True)
        S = settings(c)
        issue = d["issue_date"] or today()
        due = d["due_date"] or ((date.fromisoformat(issue) + timedelta(days=int(S["due_days"] or 0))).isoformat() if d["type"] == "invoice" else None)
        num = f"{S[PFX[d['type']]]}{next_no(c, d['type']):04d}"
        cust = dict(c.execute("select * from customers where id=?", (d["customer_id"],)).fetchone())
        snap = json.dumps(dict(cust=cust, biz=S))
        st = "issued" if d["type"] == "invoice" else "sent"
        t = totals_cols(r)
        c.execute(f"update docs set status=?, number=?, due_date=?, snap=?, {','.join(k + '=?' for k in t)} where id=?",
                  [st, num, due, snap, *t.values(), i])
        if d["type"] == "invoice" and r["coupon"]:
            c.execute("insert into coupon_usage(coupon_id,doc_id,customer_id,date,amount) values(?,?,?,?,?)",
                      (r["coupon_id"], i, d["customer_id"], today(), r["coupon_disc"]))
        audit(c, f"{d['type']} issued", f"{num} total {r['total']}")
    return num


@app.get("/api/docs")
@api
def docs_list():
    types = (request.args.get("types") or "invoice").split(",")
    rows = db().execute(DOCSQL + f"where d.type in ({','.join('?' * len(types))}) order by d.id desc", types).fetchall()
    out = []
    for r in rows:
        d = docdict(r); d.pop("items"); d.pop("charges"); out.append(d)
    return jsonify(out)


@app.get("/api/docs/<int:i>")
@api
def doc_get(i):
    c = db()
    r = c.execute(DOCSQL + "where d.id=?", (i,)).fetchone()
    if not r: return jsonify(error="Not found"), 404
    d = docdict(r)
    d["payments"] = [dict(p) for p in c.execute("select * from payments where doc_id=? order by id", (i,))]
    d["customer"] = dict(c.execute("select * from customers where id=?", (d["customer_id"],)).fetchone())
    return jsonify(d)


@app.post("/api/calc")
@api
def calc_api():
    return jsonify(calc(db(), request.get_json() or {}, (request.get_json() or {}).get("id"), strict=False))


@app.route("/api/docs", methods=["POST"])
@app.route("/api/docs/<int:i>", methods=["PUT"])
@api
def doc_save(i=None):
    c = db()
    with tx(c):
        return jsonify(id=save_doc(c, request.get_json() or {}, i))


@app.delete("/api/docs/<int:i>")
@api
def doc_delete(i):
    c = db()
    with tx(c):
        d = c.execute("select * from docs where id=?", (i,)).fetchone()
        if not d: raise ValueError("Not found")
        c.execute("delete from payments where doc_id=?", (i,))
        c.execute("delete from coupon_usage where doc_id=?", (i,))
        q_ = d["converted_from"]
        c.execute("delete from docs where id=?", (i,))
        if q_ and not c.execute("select 1 from docs where converted_from=?", (q_,)).fetchone():
            c.execute("update docs set status='sent' where id=? and status='converted'", (q_,))
        audit(c, f"{d['type']} DELETED", f"{d['number'] or 'draft #' + str(i)} status {d['status']} total {d['total']}")
    return jsonify(ok=1)


@app.post("/api/docs/<int:i>/issue")
@api
def doc_issue(i):
    return jsonify(number=do_issue(db(), i))


@app.post("/api/docs/<int:i>/void")
@api
def doc_void(i):
    c = db()
    with tx(c):
        d = c.execute(DOCSQL + "where d.id=?", (i,)).fetchone()
        if not d or d["status"] not in ("issued", "sent"): raise ValueError("Only issued documents can be voided")
        if round(d["paid"] - d["refunded"], 2) != 0: raise ValueError("Refund all payments before voiding this invoice")
        c.execute("update docs set status='void' where id=?", (i,))
        c.execute("update coupon_usage set voided=1 where doc_id=?", (i,))
        audit(c, "document voided", d["number"])
    return jsonify(ok=1)


def copy_as_draft(c, d, typ, **extra):
    v = {k: d[k] for k in DOCCOLS + ["items", "charges", "subtotal", "disc_total", "coupon_disc", "tax", "charges_total", "round_amt", "net_value", "total"]}
    v.update(type=typ, status="draft", issue_date=today(), due_date=None, valid_until=None, created=datetime.now().isoformat(" ", "seconds"), **extra)
    return c.execute(f"insert into docs({','.join(v)}) values({','.join('?' * len(v))})", list(v.values())).lastrowid


@app.post("/api/docs/<int:i>/duplicate")
@api
def doc_dup(i):
    c = db()
    d = c.execute("select * from docs where id=?", (i,)).fetchone()
    if not d: raise ValueError("Not found")
    n = copy_as_draft(c, d, d["type"])
    audit(c, "document duplicated", f"{i}->{n}")
    return jsonify(id=n)


@app.post("/api/docs/<int:i>/convert")
@api
def doc_convert(i):
    c = db()
    with tx(c):
        d = c.execute("select * from docs where id=?", (i,)).fetchone()
        if not d or d["type"] not in ("quotation", "proforma"): raise ValueError("Only quotations / pro forma invoices can be converted")
        if d["status"] != "sent": raise ValueError("Issue the quotation first (or it was already converted/cancelled)")
        n = copy_as_draft(c, d, "invoice", converted_from=i)
        c.execute("update docs set status='converted' where id=?", (i,))
        audit(c, "quotation converted", f"{d['number']} -> draft invoice {n}")
    return jsonify(id=n)


@app.post("/api/docs/<int:i>/payments")
@api
def pay_add(i):
    j, c = request.get_json() or {}, db()
    kind = j.get("kind") or "payment"
    if kind not in ("payment", "refund"): raise ValueError("Bad kind")
    amt = D(j.get("amount"))
    if amt <= 0: raise ValueError("Amount must be greater than zero")
    with tx(c):
        d = c.execute(DOCSQL + "where d.id=?", (i,)).fetchone()
        if not d or d["type"] != "invoice" or d["status"] != "issued": raise ValueError("Payments can only be recorded on issued invoices")
        paid, ref_ = D(d["paid"]), D(d["refunded"])
        if kind == "payment" and amt > D(d["total"]) - (paid - ref_): raise ValueError("Payment exceeds the outstanding balance")
        if kind == "refund" and amt > paid - ref_: raise ValueError("Refund exceeds net amount received")
        rc = f"{settings(c)['rcp_prefix']}{next_no(c, 'receipt'):04d}"
        pid = c.execute("insert into payments(doc_id,receipt,date,amount,method,ref,notes,kind) values(?,?,?,?,?,?,?,?)",
                        (i, rc, j.get("date") or today(), float(amt), j.get("method") or "cash", j.get("ref") or "", j.get("notes") or "", kind)).lastrowid
        audit(c, f"{kind} recorded", f"{d['number']} {amt} {rc}")
    return jsonify(id=pid, receipt=rc)


@app.get("/api/payments")
@api
def pay_list():
    return jsonify([dict(r) for r in db().execute(
        "select p.*, d.number, c.name cname from payments p join docs d on d.id=p.doc_id left join customers c on c.id=d.customer_id order by p.id desc")])


@app.get("/api/customer/<int:i>")
@api
def cust_detail(i):
    c = db()
    rows = [docdict(r) for r in c.execute(DOCSQL + "where d.customer_id=? order by d.id desc", (i,))]
    for d in rows: d.pop("items"); d.pop("charges")
    return jsonify(docs=rows, deals=[dict(r) for r in c.execute("select * from deals where customer_id=? order by id desc", (i,))],
                   payments=[dict(r) for r in c.execute("select p.*, d.number from payments p join docs d on d.id=p.doc_id where d.customer_id=? order by p.id desc", (i,))])

# ---------------------------------------------------------------- dashboard & reports
def invoices(c, f="", t=""):
    rows = [docdict(r) for r in c.execute(DOCSQL + "where d.type='invoice' and d.status='issued' order by d.issue_date")]
    return [d for d in rows if (not f or d["issue_date"] >= f) and (not t or d["issue_date"] <= t)]


@app.get("/api/dashboard")
@api
def dashboard():
    c, yr = db(), request.args.get("year") or str(date.today().year)
    inv = invoices(c)
    S = dict(sales=0, invoiced=0, received=0, outstanding=0, overdue=0, overdue_n=0)
    mon = [dict(m=i + 1, invoiced=0, received=0) for i in range(12)]
    cats = {}
    for d in inv:
        S["sales"] += d["net_value"]; S["invoiced"] += d["total"]; S["received"] += d["net_paid"]
        S["outstanding"] += max(d["balance"], 0)
        if d["label"] == "Overdue": S["overdue"] += d["balance"]; S["overdue_n"] += 1
        if d["issue_date"][:4] == yr: mon[int(d["issue_date"][5:7]) - 1]["invoiced"] += d["net_value"]
        for l in d["items"]: cats[l.get("cat") or "Uncategorised"] = cats.get(l.get("cat") or "Uncategorised", 0) + l["taxable"]
    pays = c.execute("select p.*, d.number, cu.name cname from payments p join docs d on d.id=p.doc_id left join customers cu on cu.id=d.customer_id order by p.id desc").fetchall()
    for p in pays:
        if p["date"][:4] == yr: mon[int(p["date"][5:7]) - 1]["received"] += p["amount"] * (1 if p["kind"] == "payment" else -1)
    exp = c.execute("select coalesce(sum(amount),0) from expenses").fetchone()[0]
    S.update(expenses=exp, profit=S["sales"] - exp,
             customers=c.execute("select count(*) from customers where archived=0").fetchone()[0],
             deals=c.execute("select count(*) from deals where status not in ('Completed','Cancelled','Refunded')").fetchone()[0])
    return jsonify(S={k: round(v, 2) for k, v in S.items()}, months=mon, cats=[[k, round(v, 2)] for k, v in sorted(cats.items(), key=lambda x: -x[1])],
                   recent=[dict(p) for p in pays[:8]], year=yr)


REPORTS = "sales collections receivables overdue customers category deliverables discounts coupons refunds expenses profit".split()


def report(c, kind, f, t):
    inr = lambda x: round(x, 2)
    inv = invoices(c, f, t)
    inp = lambda d: (not f or d >= f) and (not t or d <= t)
    if kind == "sales":
        return ["Invoice", "Date", "Customer", "Project", "Net value", "Tax", "Total", "Status"], [[d["number"], d["issue_date"], d["cname"], d["project"], d["net_value"], d["tax"], d["total"], d["label"]] for d in inv]
    if kind in ("receivables", "overdue"):
        rows = [d for d in inv if d["balance"] > 0 and (kind == "receivables" or d["label"] == "Overdue")]
        return ["Invoice", "Customer", "Due", "Total", "Paid", "Balance", "Status"], [[d["number"], d["cname"], d["due_date"], d["total"], d["net_paid"], d["balance"], d["label"]] for d in rows]
    if kind in ("collections", "refunds"):
        k = "payment" if kind == "collections" else "refund"
        rows = c.execute("select p.*, d.number, cu.name cname from payments p join docs d on d.id=p.doc_id left join customers cu on cu.id=d.customer_id where p.kind=? order by p.date", (k,)).fetchall()
        return ["Receipt", "Date", "Invoice", "Customer", "Method", "Reference", "Amount"], [[p["receipt"], p["date"], p["number"], p["cname"], p["method"], p["ref"], p["amount"]] for p in rows if inp(p["date"])]
    if kind == "customers":
        a = {}
        for d in inv:
            x = a.setdefault(d["cname"], [0, 0, 0, 0]); x[0] += 1; x[1] += d["total"]; x[2] += d["net_paid"]; x[3] += max(d["balance"], 0)
        return ["Customer", "Invoices", "Billed", "Paid", "Outstanding"], [[k, *map(inr, v)] for k, v in a.items()]
    if kind in ("category", "deliverables"):
        a = {}
        for d in inv:
            for l in d["items"]:
                key = (l.get("cat") or "Uncategorised") if kind == "category" else l["name"]
                x = a.setdefault(key, [0, 0]); x[0] += l["qty"]; x[1] += l["taxable"]
        return ["Category" if kind == "category" else "Item", "Qty", "Net sales"], [[k, *map(inr, v)] for k, v in sorted(a.items(), key=lambda x: -x[1][1])]
    if kind == "discounts":
        return ["Invoice", "Date", "Customer", "Manual discount", "Coupon", "Coupon discount"], [[d["number"], d["issue_date"], d["cname"], d["disc_total"], d["coupon"], d["coupon_disc"]] for d in inv if d["disc_total"] or d["coupon_disc"]]
    if kind == "coupons":
        rows = c.execute("select u.*, k.code, d.number, cu.name cname from coupon_usage u join coupons k on k.id=u.coupon_id join docs d on d.id=u.doc_id left join customers cu on cu.id=u.customer_id order by u.id").fetchall()
        return ["Coupon", "Date", "Invoice", "Customer", "Discount", "Voided"], [[u["code"], u["date"], u["number"], u["cname"], u["amount"], "yes" if u["voided"] else ""] for u in rows if inp(u["date"])]
    if kind == "expenses":
        rows = c.execute("select * from expenses order by date").fetchall()
        return ["Date", "Category", "Vendor", "Amount", "Notes"], [[e["date"], e["category"], e["vendor"], e["amount"], e["notes"]] for e in rows if inp(e["date"])]
    if kind == "profit":
        sales = sum(d["net_value"] for d in inv)
        exp = sum(e["amount"] for e in c.execute("select * from expenses") if inp(e["date"]))
        return ["Item", "Amount"], [["Net sales (invoiced, excl. GST)", inr(sales)], ["Expenses", inr(exp)], ["Estimated operating profit", inr(sales - exp)],
                                    ["Memo: GST collected (excluded from income)", inr(sum(d["tax"] for d in inv))]]
    raise ValueError("Unknown report")


@app.get("/api/report")
@api
def report_api():
    k = request.args.get("kind", "sales")
    cols, rows = report(db(), k, request.args.get("from", ""), request.args.get("to", ""))
    if request.args.get("csv"):
        s = io.StringIO(); w = csv.writer(s); w.writerow(cols); w.writerows(rows)
        return Response(s.getvalue(), mimetype="text/csv", headers={"Content-Disposition": f"attachment; filename={k}.csv"})
    return jsonify(cols=cols, rows=rows)

# ---------------------------------------------------------------- settings, uploads, backup, audit
@app.route("/api/settings", methods=["GET", "PUT"])
@api
def settings_api():
    c = db()
    if request.method == "PUT":
        for k, v in (request.get_json() or {}).items():
            if k in DEFAULTS:
                c.execute("insert into settings(k,v) values(?,?) on conflict(k) do update set v=excluded.v", (k, str(v)))
        audit(c, "settings updated")
    return jsonify(settings(c))


PROJECT_EXT = (".zip", ".rar", ".7z", ".tar", ".gz", ".pdf", ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx", ".txt", ".md", ".py", ".java",
               ".js", ".html", ".css", ".ipynb", ".sql", ".apk", ".jar", ".png", ".jpg", ".jpeg", ".webp")


@app.post("/api/upload")
@api
def upload():
    f = request.files.get("file")
    if not f: raise ValueError("No file")
    proj = request.args.get("kind") == "project"
    ext = os.path.splitext(f.filename)[1].lower()
    if ext not in (PROJECT_EXT if proj else (".png", ".jpg", ".jpeg", ".webp", ".pdf")):
        raise ValueError("This file type is not allowed")
    name = secrets.token_hex(4) + "_" + (secure_filename(f.filename) or "file" + ext) if proj else secrets.token_hex(8) + ext
    path = os.path.join(UP, name)
    f.save(path)
    if os.path.getsize(path) > (200 if proj else 3) * 1024 * 1024:
        os.remove(path)
        raise ValueError("File too large (max %d MB)" % (200 if proj else 3))
    return jsonify(name=name)


@app.get("/uploads/<name>")
def uploads(name):
    if "u" not in session: return "", 401
    img = name.lower().endswith((".png", ".jpg", ".jpeg", ".webp", ".pdf"))
    return send_from_directory(UP, name, as_attachment=not img, download_name=name[9:] if name[8:9] == "_" else name)


@app.get("/api/audit")
@api
def audit_list():
    return jsonify([dict(r) for r in db().execute("select * from audit order by id desc limit 400")])


@app.get("/api/backup")
@api
def backup():
    p = os.path.join(DATA, f"backup-{datetime.now():%Y%m%d-%H%M%S}.db")
    dst = sqlite3.connect(p); db().backup(dst); dst.close()
    audit(db(), "backup downloaded")
    return send_file(p, as_attachment=True, download_name=os.path.basename(p))


@app.post("/api/restore")
@api
def restore():
    f = request.files.get("file")
    if not f: raise ValueError("No file")
    tmp = os.path.join(DATA, "restore.tmp")
    f.save(tmp)
    try:
        t = connect(tmp)
        ok = t.execute("pragma integrity_check").fetchone()[0] == "ok"
        names = {r[0] for r in t.execute("select name from sqlite_master where type='table'")}
        if not ok or not {"docs", "customers", "settings", "users"} <= names: raise ValueError("Not a valid Perixa backup")
        migrate(t); t.close()
    except sqlite3.DatabaseError:
        raise ValueError("Not a valid Perixa backup")
    db().close(); g.pop("db", None)
    shutil.copy(DB, os.path.join(DATA, f"pre-restore-{datetime.now():%Y%m%d-%H%M%S}.db"))
    os.replace(tmp, DB)
    audit(db(), "database restored")
    return jsonify(ok=1)

# ---------------------------------------------------------------- printable documents
def inr_fmt(x):
    x = float(x or 0)
    i, f = f"{abs(x):.2f}".split(".")
    if len(i) > 3:
        h, r, parts = i[-3:], i[:-3], []
        while len(r) > 2: parts.insert(0, r[-2:]); r = r[:-2]
        if r: parts.insert(0, r)
        i = ",".join(parts + [h])
    return ("-" if x < 0 else "") + i + "." + f


app.jinja_env.filters["inr"] = inr_fmt


@app.get("/doc/<int:i>/print")
def doc_print(i):
    if "u" not in session: return "Login required", 401
    c = db()
    r = c.execute(DOCSQL + "where d.id=?", (i,)).fetchone()
    if not r: return "Not found", 404
    raw = c.execute("select snap from docs where id=?", (i,)).fetchone()["snap"]
    d = docdict(r)
    snap = json.loads(raw) if raw else None
    cust = snap["cust"] if snap else dict(c.execute("select * from customers where id=?", (d["customer_id"],)).fetchone())
    biz = snap["biz"] if snap else settings(c)
    dn = request.args.get("dn")
    title = "Delivery Note" if dn else {"invoice": "Invoice", "quotation": "Quotation", "proforma": "Pro Forma Invoice"}[d["type"]]
    pays = [dict(p) for p in c.execute("select * from payments where doc_id=? order by id", (i,))]
    return render_template("print.html", d=d, cust=cust, biz=biz, title=title, dn=dn, pays=pays, receipt=None)


@app.get("/receipt/<int:i>/print")
def receipt_print(i):
    if "u" not in session: return "Login required", 401
    c = db()
    p = c.execute("select * from payments where id=?", (i,)).fetchone()
    if not p: return "Not found", 404
    r = c.execute(DOCSQL + "where d.id=?", (p["doc_id"],)).fetchone()
    d, raw = docdict(r), c.execute("select snap from docs where id=?", (p["doc_id"],)).fetchone()["snap"]
    snap = json.loads(raw)
    return render_template("print.html", d=d, cust=snap["cust"], biz=snap["biz"], title="Payment Receipt" if p["kind"] == "payment" else "Refund Receipt",
                           dn=None, pays=[], receipt=dict(p))

# ---------------------------------------------------------------- init & sample data
def init():
    c = connect()
    migrate(c)
    c.close()


init()


def seed():
    with app.app_context():
        c = db()
        if c.execute("select 1 from customers").fetchone(): print("Data already exists - seed skipped"); return
        C = [("Aarav Kumar (SAMPLE)", "Student", "Sample Engineering College", "Tamil Nadu"), ("Meera Nair (SAMPLE)", "Student", "Sample Arts College", "Kerala"),
             ("Sample Tech Pvt Ltd", "Company", "Sample Tech Pvt Ltd", "Tamil Nadu")]
        for n, t, o, s in C:
            c.execute("insert into customers(code,name,type,org,state,city) values(?,?,?,?,?,?)", (f"C{next_no(c, 'cust'):04d}", n, t, o, s, "Chennai"))
        cat = [("Source Code", "deliverable", "Deliverable", 0, 18), ("Project Report", "deliverable", "Deliverable", 1500, 18), ("PPT", "deliverable", "Deliverable", 800, 18),
               ("Installation & Deployment", "service", "Service", 1000, 18), ("Video Demonstration", "deliverable", "Deliverable", 1200, 18),
               ("AI Chatbot Project", "project", "AI/ML", 6000, 18), ("Cyber Security Toolkit", "project", "Cybersecurity", 5000, 18),
               ("Flutter Mobile App", "project", "Web/Mobile", 7000, 18), ("IoT Hardware Kit", "hardware", "IoT", 4500, 18)]
        ids = {}
        for n, k, ca, p, tx_ in cat:
            ids[n] = c.execute("insert into catalogue(name,kind,category,price,tax_rate) values(?,?,?,?,?)", (n, k, ca, p, tx_)).lastrowid
        code, docs, full = "Complete source code\nExecutable / build files", "Abstract & synopsis\nProject report\nDocumentation", "PPT\nDiagrams\nDatabase & sample data\nInstallation & deployment\nDemo video\nViva questions & explanation"
        for n, p, inc in [("Source Code Only", 3000, code), ("Source Code + Documents", 4500, code + "\n" + docs), ("Full Software Kit", 7000, code + "\n" + docs + "\n" + full),
                          ("Documentation Only", 1500, docs), ("PPT Only", 800, "PPT\nDiagrams"), ("Complete Hardware Kit", 9000, "Hardware components & kit\nSource code & firmware\nProject report\nPPT\nDemo video")]:
            c.execute("insert into presets(name,price,tax_rate,includes) values(?,?,18,?)", (n, p, inc))
        c.execute("insert into coupons(code,kind,value,expires,min_amount,max_discount,usage_limit,per_customer) values('WELCOME10','percent',10,?,1000,2000,50,1)",
                  ((date.today() + timedelta(days=180)).isoformat(),))
        c.execute("insert into expenses(date,category,vendor,amount,notes) values(?,?,?,?,?)", (today(), "Hosting", "Sample Host", 1200, "Sample expense"))
        c.execute("insert into deals(title,customer_id,status,negotiated) values('Sample chatbot deal',1,'Quoted',6000)")
        d = dict(type="invoice", customer_id=1, project="AI Chatbot Project", tax_mode="intra", coupon="WELCOME10", disc_type="percent", disc_val=0,
                 items=[dict(name="AI Chatbot Project", qty=1, rate=6000, tax_rate=18, cat="AI/ML", item_id=ids["AI Chatbot Project"]),
                        dict(name="Project Report", qty=1, rate=1500, tax_rate=18, cat="Deliverable", item_id=ids["Project Report"])])
        i = save_doc(c, d)
        do_issue(c, i)
        print("Sample data created (fictional). Customers/invoice marked SAMPLE - delete from the app when ready.")


if __name__ == "__main__":
    if "seed" in sys.argv: seed(); sys.exit()
    print("Perixa Billing Pro -> http://127.0.0.1:%s  (phones: Settings > Phone)" % os.environ.get("PERIXA_PORT", 5000))
    app.run(os.environ.get("PERIXA_HOST", "0.0.0.0"), int(os.environ.get("PERIXA_PORT", 5000)), debug=False, threaded=True)
