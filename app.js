"use strict";
const $ = (s, e = document) => e.querySelector(s);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const inr = n => { n = +n || 0; const [i, f] = Math.abs(n).toFixed(2).split("."); let h = i.slice(-3), r = i.slice(0, -3); if (r) h = r.replace(/\B(?=(\d{2})+(?!\d))/g, ",") + "," + h; return (n < 0 ? "-" : "") + "₹" + h + "." + f };
const today = () => new Date().toISOString().slice(0, 10);
const toast = (m, e) => { const t = $("#toast"); t.textContent = m; t.className = e ? "e" : ""; t.style.display = "block"; clearTimeout(toast.t); toast.t = setTimeout(() => t.style.display = "none", 3500) };
async function api(p, method = "GET", body) {
  const o = { method, headers: { "X-Requested-With": "fetch" } };
  if (body instanceof FormData) o.body = body; else if (body) { o.headers["Content-Type"] = "application/json"; o.body = JSON.stringify(body) }
  const r = await fetch("/api/" + p, o);
  if (r.status === 401) return location.reload();
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || "Request failed");
  return j;
}
const tag = l => `<span class="tag ${esc(String(l).split(" ")[0])}">${esc(l)}</span>`;
let OUT = "#main";
const set = h => { $(OUT).innerHTML = h };
const NAV = [["bill", "New Bill"], ["statement", "Statement"], ["packages", "Packages"], ["dashboard", "Dashboard"], ["reports", "Reports"], ["settings", "Settings"]];
let SET = {}, LK = {};
const csvIds = s => (s || "").split(",").filter(Boolean);

// ------------------------------------------------------------ modal form
function form(title, fields, v, save, extra = "") {
  const dlg = document.createElement("dialog");
  const inp = f => {
    const val = v[f.k] ?? f.d ?? "", n = `name="${f.k}"`, o = typeof f.o === "function" ? f.o() : f.o || [];
    const opts = o.map(x => { const [a, b] = Array.isArray(x) ? x : [x, x]; return `<option value="${esc(a)}" ${String(a) === String(val) ? "selected" : ""}>${esc(b)}</option>` }).join("");
    if (f.t === "select") return `<select ${n}>${f.blank ? "<option value=''>-</option>" : ""}${opts}</select>`;
    if (f.t === "textarea") return `<textarea ${n} rows="3">${esc(val)}</textarea>`;
    if (f.t === "check") return `<input type="checkbox" ${n} ${+val ? "checked" : ""}>`;
    if (f.t === "multi") { const sel = csvIds(val); return `<div style="max-height:110px;overflow:auto;border:1px solid var(--bd);border-radius:6px;padding:4px">${o.map(([a, b]) => `<label style="margin:0;color:var(--tx)"><input type="checkbox" data-m="${f.k}" value="${esc(a)}" ${sel.includes(String(a)) ? "checked" : ""}> ${esc(b)}</label>`).join("")}</div>` }
    if (f.t === "file") return `<input type="file" data-file="${f.k}" accept="${f.up ? "" : ".png,.jpg,.jpeg,.webp,.pdf"}">${val ? `<small><a href="/uploads/${esc(val)}" target="_blank">current file</a></small>` : ""}<input type="hidden" ${n} value="${esc(val)}">`;
    return `<input ${n} type="${f.t || "text"}" ${f.t === "number" ? 'step="any" min="0"' : ""} value="${esc(val)}" ${f.req ? "required" : ""}>`;
  };
  dlg.innerHTML = `<form method="dialog"><h2>${esc(title)}</h2><div class="f">${fields.map(f => `<label class="${f.w ? "w" : ""}">${esc(f.l)}${f.req ? " *" : ""}${inp(f)}</label>`).join("")}</div>${extra}
  <div class="bar"><span class="sp"></span><button type="button" class="btn ghost" id="x">Cancel</button><button class="btn au">Save</button></div></form>`;
  document.body.append(dlg); dlg.showModal();
  $("#x", dlg).onclick = () => dlg.remove();
  dlg.querySelectorAll("[data-file]").forEach(i => i.onchange = () => { const n = $('[name="name"]', dlg); if (n && !n.value && i.files[0]) n.value = i.files[0].name.replace(/\.[^.]+$/, "") });
  dlg.onclose = () => dlg.remove();
  $("form", dlg).onsubmit = async e => {
    e.preventDefault();
    const out = {};
    try {
      for (const f of fields) {
        const el = $(`[name="${f.k}"]`, dlg);
        if (f.t === "check") out[f.k] = el.checked ? 1 : 0;
        else if (f.t === "multi") out[f.k] = [...dlg.querySelectorAll(`[data-m="${f.k}"]:checked`)].map(x => x.value).join(",");
        else if (f.t === "file") { const fi = $(`[data-file="${f.k}"]`, dlg).files[0]; if (fi) { const fd = new FormData(); fd.append("file", fi); out[f.k] = (await api("upload" + (f.up ? "?kind=" + f.up : ""), "POST", fd)).name } else out[f.k] = el.value }
        else out[f.k] = el.value;
      }
      await save(out); dlg.remove();
    } catch (er) { toast(er.message, 1) }
  };
  return dlg;
}

// ------------------------------------------------------------ generic list page
async function listPage(o) {
  const rows = await api("e/" + o.ent);
  set(`<div class="card"><h2>${o.title}</h2><div class="bar"><input id="q" placeholder="Search..."><button class="btn au" id="new">+ New</button></div><div class="sc"><table id="t"></table></div></div>`);
  const draw = () => {
    const q = $("#q").value.toLowerCase(), rs = rows.filter(r => !q || JSON.stringify(Object.values(r)).toLowerCase().includes(q));
    $("#t").innerHTML = `<tr>${o.cols.map(c => `<th>${c[0]}</th>`).join("")}<th></th></tr>` + rs.map(r => `<tr>${o.cols.map(c => `<td>${typeof c[1] === "function" ? c[1](r) : esc(r[c[1]])}</td>`).join("")}<td class="r" style="white-space:nowrap"><button class="btn sm ghost" data-e="${r.id}">Edit</button> <button class="btn sm ghost" data-d="${r.id}">${o.ent === "customers" ? (r.archived ? "Restore" : "Archive") : "Delete"}</button></td></tr>`).join("") || `<tr><td class="muted">Nothing yet</td></tr>`;
  };
  draw(); $("#q").oninput = draw;
  const edit = r => { const dlg = form((r ? "Edit " : "New ") + o.one, o.fields, r || o.defaults || {}, async v => { await api("e/" + o.ent + (r ? "/" + r.id : ""), r ? "PUT" : "POST", v); LK = {}; toast("Saved"); route() }); o.hook && o.hook(dlg) };
  $("#new").onclick = () => edit();
  $("#t").onclick = async e => {
    const b = e.target.closest("button"); if (!b) return;
    if (b.dataset.e) edit(rows.find(r => r.id == b.dataset.e));
    if (b.dataset.d && confirm("Are you sure?")) try { await api("e/" + o.ent + "/" + b.dataset.d, "DELETE"); LK = {}; route() } catch (er) { toast(er.message, 1) }
  };
}
async function lk(ent) { return LK[ent] ||= await api("e/" + ent) }
const YN = [[1, "Yes"], [0, "No"]];

// ------------------------------------------------------------ pages
const P = {};
P.dashboard = async () => {
  const d = await api("dashboard"), S = d.S;
  const cards = [["Total sales (excl. GST)", S.sales], ["Invoiced (incl. GST)", S.invoiced], ["Payments received", S.received], ["Outstanding", S.outstanding], [`Overdue (${S.overdue_n})`, S.overdue], ["Expenses", S.expenses], ["Est. profit", S.profit]];
  const bars = (labels, series, w = 520, h = 190) => {
    const mx = Math.max(1, ...series.flat()), bw = (w - 30) / labels.length;
    return `<svg viewBox="0 0 ${w} ${h}" width="100%">${labels.map((l, i) => series.map((s, j) => { const bh = s[i] / mx * (h - 35); const x = 25 + i * bw + j * bw / (series.length + .5) , wd = bw / (series.length + .5) - 2; return `<rect x="${x}" y="${h - 20 - bh}" width="${wd}" height="${bh}" fill="${j ? "#1f9d55" : "#c9a227"}"><title>${l}: ${inr(s[i])}</title></rect>` }).join("") + `<text x="${25 + i * bw}" y="${h - 6}">${esc(l)}</text>`).join("")}</svg>`;
  };
  const mn = "JFMAMJJASOND".split("");
  set(`<div class="grid">${cards.map(c => `<div class="stat"><small>${c[0]}</small><b>${inr(c[1])}</b></div>`).join("")}<div class="stat"><small>Customers</small><b>${S.customers}</b></div><div class="stat"><small>Active deals</small><b>${S.deals}</b></div></div>
  <div class="two"><div class="card"><h2>Monthly ${d.year} <small class="muted">gold = invoiced, green = received</small></h2>${bars(mn, [d.months.map(m => m.invoiced), d.months.map(m => m.received)])}</div>
  <div class="card"><h2>Sales by category</h2>${d.cats.length ? bars(d.cats.slice(0, 6).map(c => c[0].slice(0, 8)), [d.cats.slice(0, 6).map(c => c[1])], 300) : '<p class="muted">No invoices yet</p>'}</div></div>
  <div class="card"><h2>Recent transactions</h2><div class="sc"><table><tr><th>Date</th><th>Receipt</th><th>Invoice</th><th>Customer</th><th class="r">Amount</th></tr>${d.recent.map(p => `<tr><td>${esc(p.date)}</td><td>${esc(p.receipt)}</td><td>${esc(p.number)}</td><td>${esc(p.cname)}</td><td class="r">${p.kind === "refund" ? "-" : ""}${inr(p.amount)}</td></tr>`).join("") || '<tr><td class="muted">No payments yet</td></tr>'}</table></div></div>`);
};
P.customers = async () => {
  const f = [{ k: "name", l: "Name", req: 1 }, { k: "type", l: "Type", t: "select", o: ["Student", "Company", "Individual", "Institution"] }, { k: "org", l: "College / Company" }, { k: "course", l: "Course" }, { k: "dept", l: "Department" }, { k: "phone", l: "Phone" }, { k: "email", l: "Email", t: "email" }, { k: "address", l: "Billing address", t: "textarea", w: 1 }, { k: "city", l: "City" }, { k: "state", l: "State" }, { k: "pin", l: "PIN code" }, { k: "gstin", l: "GSTIN" }, { k: "notes", l: "Notes", t: "textarea", w: 1 }];
  await listPage({ ent: "customers", one: "customer", title: "Customers", fields: f, cols: [["ID", "code"], ["Name", r => `<a href="#/customer/${r.id}">${esc(r.name)}</a>${r.archived ? " " + tag("Archived") : ""}`], ["Type", "type"], ["College/Company", "org"], ["Phone", "phone"], ["Email", "email"]] });
};
P.customer = async id => {
  const [all, d] = await Promise.all([lk("customers"), api("customer/" + id)]), c = all.find(x => x.id == id);
  if (!c) return set("<p>Not found</p>");
  set(`<div class="card"><h2>${esc(c.name)} <small class="muted">${esc(c.code)}</small></h2><p>${esc(c.type)} · ${esc(c.org)} ${esc(c.course)} ${esc(c.dept)}<br>${esc(c.phone)} ${esc(c.email)}<br>${esc(c.address)} ${esc(c.city)} ${esc(c.state)} ${esc(c.pin)} ${c.gstin ? "GSTIN " + esc(c.gstin) : ""}</p><p class="muted">${esc(c.notes)}</p></div>
  <div class="card"><h2>Invoices & quotations</h2><div class="sc"><table><tr><th>No.</th><th>Type</th><th>Date</th><th>Project</th><th class="r">Total</th><th class="r">Balance</th><th>Status</th></tr>${d.docs.map(x => `<tr><td><a href="#/doc/${x.id}">${esc(x.number || "Draft #" + x.id)}</a></td><td>${x.type}</td><td>${x.issue_date}</td><td>${esc(x.project)}</td><td class="r">${inr(x.total)}</td><td class="r">${inr(x.balance)}</td><td>${tag(x.label)}</td></tr>`).join("")}</table></div></div>
  <div class="card"><h2>Payments</h2><table>${d.payments.map(p => `<tr><td>${p.date}</td><td>${esc(p.receipt)}</td><td>${esc(p.number)}</td><td>${p.kind}</td><td class="r">${inr(p.amount)}</td></tr>`).join("") || "<tr><td class=muted>None</td></tr>"}</table></div>
  <div class="card"><h2>Deals</h2><table>${d.deals.map(x => `<tr><td>${esc(x.title)}</td><td>${tag(x.status)}</td><td class="r">${inr(x.negotiated)}</td></tr>`).join("") || "<tr><td class=muted>None</td></tr>"}</table></div>`);
};
P.catalogue = async () => listPage({
  ent: "catalogue", one: "item", title: "Project Catalogue, Deliverables & Services", defaults: { tax_rate: 18, active: 1, kind: "project" },
  fields: [{ k: "name", l: "Name", req: 1 }, { k: "kind", l: "Kind", t: "select", o: [["project", "Project"], ["deliverable", "Deliverable"], ["service", "Service / Support"], ["hardware", "Hardware"], ["custom", "Custom"]] }, { k: "category", l: "Category", t: "select", o: ["AI/ML", "Cybersecurity", "Web/Mobile", "Python", "Java", "Flutter", "IoT", "Data Science", "Database", "Deliverable", "Service", "Custom"] }, { k: "stack", l: "Technology stack" }, { k: "complexity", l: "Complexity", t: "select", o: ["Basic", "Intermediate", "Advanced"] }, { k: "delivery_days", l: "Delivery (days)", t: "number" }, { k: "price", l: "Standard price", t: "number" }, { k: "min_price", l: "Minimum price", t: "number" }, { k: "tax_rate", l: "Tax %", t: "number" }, { k: "description", l: "Description", t: "textarea", w: 1 }, { k: "file", l: "Project / software file (zip, pdf, source...)", t: "file", up: "project", w: 1 }, { k: "support_terms", l: "Support terms", t: "textarea", w: 1 }, { k: "active", l: "Active", t: "check" }],
  cols: [["Name", "name"], ["Kind", "kind"], ["Category", "category"], ["Price", r => inr(r.price)], ["File", r => r.file ? `<a href="/uploads/${esc(r.file)}">download</a>` : ""], ["Tax%", "tax_rate"]]
});
P.packages = async () => {
  const STD = ["Complete source code", "Executable / build files", "Abstract & synopsis", "Project report", "Documentation", "PPT", "Research paper", "Diagrams", "Database & sample data", "Configuration files", "Installation & deployment", "Customization", "Demo video", "Viva questions & explanation", "Hardware components", "Complete hardware kit", "Maintenance & support"];
  await listPage({
    ent: "presets", one: "package", title: "Packages - price and what is included", defaults: { active: 1, tax_rate: SET.default_tax || 18 },
    fields: [{ k: "name", l: "Package name (e.g. Source Code Only, Full Kit)", req: 1, w: 1 }, { k: "price", l: "Package price", t: "number", req: 1 }, { k: "tax_rate", l: "Tax %", t: "number" }, { k: "includes", l: "What is included - one per line", t: "textarea", w: 1 }, { k: "active", l: "Active", t: "check" }],
    cols: [["Package", "name"], ["Price", r => inr(r.price)], ["Tax%", "tax_rate"], ["Included", r => esc((r.includes || "").split("\n").filter(x => x.trim()).join(" · "))], ["Status", r => tag(r.active ? "Active" : "Inactive")]],
    hook: dlg => { const ta = $("[name=includes]", dlg); ta.rows = 7; const box = document.createElement("div"); box.className = "w"; box.style.cssText = "margin:-4px 0 10px;grid-column:1/-1"; box.innerHTML = '<small class="muted">Tap to add:</small> ' + STD.map(x => `<button type="button" class="btn sm ghost" style="margin:2px">${esc(x)}</button>`).join(""); ta.closest("label").after(box); box.onclick = e => { const b = e.target.closest("button"); if (!b) return; const have = ta.value.split("\n").map(x => x.trim()); if (!have.includes(b.textContent)) ta.value = (ta.value.trim() ? ta.value.trim() + "\n" : "") + b.textContent } }
  });
};
P.coupons = async () => {
  const [cust, cat] = await Promise.all([lk("customers"), lk("catalogue")]);
  await listPage({
    ent: "coupons", one: "coupon", title: "Coupons & Offers", defaults: { kind: "percent", active: 1, min_amount: 0 },
    fields: [{ k: "code", l: "Code", req: 1 }, { k: "kind", l: "Type", t: "select", o: [["percent", "Percentage"], ["fixed", "Fixed amount"]] }, { k: "value", l: "Value", t: "number", req: 1 }, { k: "min_amount", l: "Minimum invoice amount", t: "number" }, { k: "max_discount", l: "Max discount cap", t: "number" }, { k: "starts", l: "Starts", t: "date" }, { k: "expires", l: "Expires", t: "date" }, { k: "usage_limit", l: "Total usage limit", t: "number" }, { k: "per_customer", l: "Per-customer limit", t: "number" }, { k: "categories", l: "Eligible categories (comma separated, blank = all)", w: 1 }, { k: "item_ids", l: "Eligible items (blank = all)", t: "multi", o: cat.map(c => [c.id, c.name]), w: 1 }, { k: "customer_ids", l: "Restrict to customers (blank = all)", t: "multi", o: cust.map(c => [c.id, c.name]), w: 1 }, { k: "combine_manual", l: "Can combine with manual discount", t: "check" }, { k: "active", l: "Active", t: "check" }],
    cols: [["Code", "code"], ["Offer", r => r.kind === "percent" ? r.value + "%" : inr(r.value)], ["Min", r => inr(r.min_amount)], ["Valid", r => esc((r.starts || "…") + " → " + (r.expires || "…"))], ["Limit", r => esc(r.usage_limit || "∞")], ["Status", r => tag(r.active ? "Active" : "Inactive")]]
  });
};
P.expenses = async () => listPage({
  ent: "expenses", one: "expense", title: "Expenses", defaults: { date: today() },
  fields: [{ k: "date", l: "Date", t: "date", req: 1 }, { k: "category", l: "Category", t: "select", o: ["Hardware", "Development", "Hosting", "Marketing", "Delivery", "Other"] }, { k: "vendor", l: "Vendor" }, { k: "amount", l: "Amount", t: "number", req: 1 }, { k: "notes", l: "Notes", w: 1 }, { k: "receipt", l: "Receipt attachment", t: "file", w: 1 }],
  cols: [["Date", "date"], ["Category", "category"], ["Vendor", "vendor"], ["Amount", r => inr(r.amount)], ["Notes", "notes"], ["Receipt", r => r.receipt ? `<a href="/uploads/${esc(r.receipt)}" target="_blank">view</a>` : ""]]
});
P.deals = async () => {
  const cust = await lk("customers"), n = Object.fromEntries(cust.map(c => [c.id, c.name]));
  const T = (k, l, t = "textarea") => ({ k, l, t, w: t === "textarea" ? 1 : 0 });
  await listPage({
    ent: "deals", one: "deal", title: "Deals & Project Agreements", defaults: { status: "Lead" },
    fields: [{ k: "title", l: "Deal / project", req: 1 }, { k: "customer_id", l: "Customer", t: "select", blank: 1, o: cust.map(c => [c.id, c.name]) }, { k: "status", l: "Status", t: "select", o: ["Lead", "Quoted", "Negotiation", "Accepted", "In Progress", "Awaiting Payment", "Partially Paid", "Completed", "Cancelled", "Refunded"] }, T("original_quote", "Original quote", "number"), T("negotiated", "Negotiated amount", "number"), T("discount", "Discount", "number"), T("advance", "Advance", "number"), T("starts", "Start date", "date"), T("delivery", "Delivery date", "date"), T("requirements", "Requirements"), T("scope", "Agreed scope"), T("deliverables", "Deliverables"), T("schedule", "Payment schedule"), T("revisions", "Revisions"), T("support", "Support period"), T("licensing", "Licensing / ownership"), T("cancellation", "Cancellation terms"), T("notes", "Internal notes")],
    cols: [["Deal", "title"], ["Customer", r => esc(n[r.customer_id])], ["Status", r => tag(r.status)], ["Quote", r => inr(r.original_quote)], ["Negotiated", r => inr(r.negotiated)], ["Balance", r => inr((r.negotiated || 0) - (r.advance || 0))], ["Delivery", "delivery"]]
  });
};

// statement
P.statement = async () => {
  const rows = await api("docs?types=invoice,quotation,proforma");
  set(`<div class="card"><h2>Statement</h2><div class="bar"><input id="q" placeholder="Customer, bill no, project..."><select id="ty"><option value="">All bills</option><option value="invoice">Invoices</option><option value="quotation">Quotations</option></select><select id="st"><option value="">Any status</option>${[...new Set(rows.map(r => r.label))].map(s => `<option>${s}</option>`).join("")}</select><input type="date" id="f"><input type="date" id="t"><a class="btn au" href="#/bill">+ New bill</a><button class="btn ghost" id="pr">Print</button><button class="btn ghost" id="cs">CSV</button></div><div class="grid" id="sum"></div><div class="sc"><table id="tb"></table></div></div>`);
  let cur = [];
  const draw = () => {
    const q = $("#q").value.toLowerCase(), ty = $("#ty").value, s = $("#st").value, f = $("#f").value, t = $("#t").value;
    cur = rows.filter(r => (!q || (r.number + " " + r.cname + " " + r.project).toLowerCase().includes(q)) && (!ty || (ty === "invoice") === (r.type === "invoice")) && (!s || r.label === s) && (!f || r.issue_date >= f) && (!t || r.issue_date <= t));
    const inv = cur.filter(r => r.type === "invoice" && r.status === "issued"), sum = k => inv.reduce((a, r) => a + r[k], 0);
    $("#sum").innerHTML = [["Billed", sum("total")], ["Received", sum("net_paid")], ["Balance due", sum("balance")]].map(c => `<div class="stat"><small>${c[0]}</small><b>${inr(c[1])}</b></div>`).join("");
    $("#tb").innerHTML = "<tr><th>No.</th><th>Date</th><th>Customer</th><th>Project</th><th class='r'>Total</th><th class='r'>Paid</th><th class='r'>Balance</th><th>Status</th><th></th></tr>" + cur.map(r => `<tr><td><a href="#/doc/${r.id}">${esc(r.number || "Draft #" + r.id)}</a></td><td>${r.issue_date}</td><td>${esc(r.cname)}</td><td>${esc(r.project)}</td><td class="r">${inr(r.total)}</td><td class="r">${r.type === "invoice" ? inr(r.net_paid) : ""}</td><td class="r">${r.type === "invoice" ? inr(r.balance) : ""}</td><td>${tag(r.label)}</td><td><button class="btn sm ghost" data-del="${r.id}" title="Delete">🗑</button></td></tr>`).join("") || "<tr><td class=muted>No bills yet</td></tr>";
  };
  draw(); document.querySelectorAll("#q,#ty,#st,#f,#t").forEach(e => e.oninput = draw);
  $("#tb").onclick = async e => { const b = e.target.closest("[data-del]"); if (!b) return; const r = rows.find(x => x.id == b.dataset.del); if (!confirm(`Permanently delete ${r.number || "draft #" + r.id} (${r.cname}, ${inr(r.total)})${r.paid ? " and its payments" : ""}? This cannot be undone.`)) return; try { await api("docs/" + r.id, "DELETE"); rows.splice(rows.indexOf(r), 1); draw(); toast("Deleted") } catch (er) { toast(er.message, 1) } };
  $("#pr").onclick = () => print();
  $("#cs").onclick = () => { const l = [["No", "Date", "Customer", "Project", "Total", "Paid", "Balance", "Status"], ...cur.map(r => [r.number, r.issue_date, r.cname, r.project, r.total, r.net_paid, r.balance, r.label])]; const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([l.map(x => x.map(v => `"${String(v ?? "").replace(/"/g, '""')}"`).join(",")).join("\n")], { type: "text/csv" })); a.download = "statement.csv"; a.click() };
};
P.invoices = P.quotations = P.statement;

// document view
P.doc = async id => {
  const d = await api("docs/" + id), isInv = d.type === "invoice", issued = d.status === "issued";
  const act = [];
  if (d.status === "draft") act.push(`<a class="btn" href="#/invoice/${d.id}">Edit</a>`, `<button class="btn au" data-a="issue">Issue</button>`);
  if (d.status === "sent") act.push(`<button class="btn au" data-a="convert">Convert to invoice</button>`);
  if (d.status === "issued" || d.status === "sent") act.push(`<button class="btn red" data-a="void">Void</button>`);
  act.push(`<button class="btn ghost" data-a="duplicate">Duplicate</button>`, `<button class="btn red" data-a="delete">Delete</button>`, `<a class="btn ghost" target="_blank" href="/doc/${d.id}/print">Print / PDF</a>`, `<a class="btn ghost" target="_blank" href="/doc/${d.id}/print?dn=1">Delivery note</a>`);
  const T = (a, b, neg) => +b || a === "Total" ? `<tr${a === "Total" ? ' class="g"' : ""}><td>${a}</td><td class="r">${neg ? "- " : ""}${inr(b)}</td></tr>` : "";
  set(`<div class="card"><h2>${esc(d.number || "Draft #" + d.id)} ${tag(d.label)}</h2><p><b>${esc(d.cname)}</b> · ${esc(d.project)} · ${d.issue_date}${d.due_date ? " · due " + d.due_date : ""}</p><div class="bar">${act.join("")}</div>
  <div class="sc"><table><tr><th>Item</th><th class="r">Qty</th><th class="r">Rate</th><th class="r">Disc%</th><th class="r">Tax%</th><th class="r">Amount</th></tr>${d.items.map(l => `<tr><td>${esc(l.name)}${l.desc ? `<br><small class="muted" style="white-space:pre-line">${esc(l.desc)}</small>` : ""}</td><td class="r">${l.qty}</td><td class="r">${inr(l.rate)}</td><td class="r">${l.disc}</td><td class="r">${l.tax_rate}</td><td class="r">${inr(l.gross)}</td></tr>`).join("")}${d.charges.map(l => `<tr><td>${esc(l.name)}</td><td></td><td></td><td></td><td class="r">${l.tax_rate}</td><td class="r">${inr(l.amount)}</td></tr>`).join("")}</table></div>
  <table class="tot" style="max-width:320px;margin-left:auto">${T("Subtotal", d.subtotal)}${T("Discount", d.disc_total, 1)}${T("Coupon " + (d.coupon || ""), d.coupon_disc, 1)}${T("Charges", d.charges_total)}${T(d.tax_mode === "inter" ? "IGST" : "CGST + SGST", d.tax)}${T("Round off", d.round_amt)}${T("Total", d.total)}${isInv && issued ? T("Paid (net)", d.net_paid) + T("Balance", d.balance) : ""}</table></div>
  ${isInv && issued ? `<div class="card"><h2>Payments</h2><table>${d.payments.map(p => `<tr><td>${p.date}</td><td>${esc(p.receipt)}</td><td>${esc(p.method)} ${esc(p.ref)}</td><td>${p.kind}</td><td class="r">${p.kind === "refund" ? "-" : ""}${inr(p.amount)}</td><td><a target="_blank" href="/receipt/${p.id}/print">Receipt</a></td></tr>`).join("") || "<tr><td class=muted>No payments yet</td></tr>"}</table>
  <form id="pf" class="bar" style="margin-top:12px"><input type="date" name="date" value="${today()}"><input name="amount" type="number" step="any" min="0" placeholder="Amount" value="${d.balance > 0 ? d.balance : ""}" required><select name="method"><option>cash</option><option>upi</option><option>bank transfer</option><option>card</option><option>other</option></select><input name="ref" placeholder="Reference"><select name="kind"><option value="payment">Payment</option><option value="refund">Refund</option></select><button class="btn au">Record</button></form></div>` : ""}`);
  document.querySelector("#main").onclick = async e => {
    const a = e.target.dataset.a; if (!a) return;
    try {
      if (a === "delete") { if (!confirm(d.status === "draft" ? "Delete this draft?" : "Permanently delete this bill" + (d.paid ? " and its " + d.payments.length + " payment record(s)" : "") + "? This cannot be undone.")) return; await api("docs/" + id, "DELETE"); return location.hash = "#/statement" }
      if (a === "void" && !confirm("Void this document? This cannot be undone.")) return;
      const r = await api(`docs/${id}/${a}`, "POST");
      if (a === "duplicate" || a === "convert") { toast("Draft created"); location.hash = "#/invoice/" + r.id } else { toast("Done"); route() }
    } catch (er) { toast(er.message, 1) }
  };
  const pf = $("#pf"); if (pf) pf.onsubmit = async e => { e.preventDefault(); try { await api(`docs/${id}/payments`, "POST", Object.fromEntries(new FormData(pf))); toast("Recorded"); route() } catch (er) { toast(er.message, 1) } };
};

// single-screen billing
P.bill = async (id, kind) => {
  const [cust, cat, pre] = await Promise.all([lk("customers"), lk("catalogue"), lk("presets")]);
  if (id === "quotation" || id === "proforma") { kind = id; id = "new" }
  let E;
  if (id && id !== "new") { E = await api("docs/" + id); if (E.status !== "draft") return location.hash = "#/doc/" + id; E.id = +E.id }
  else E = { type: kind || "invoice", issue_date: today(), items: [], charges: [], disc_type: "percent", disc_val: 0, tax_mode: "intra", inclusive: 0, round_off: 1, terms: SET.terms, customer_id: null, customer: {}, coupon: "", notes: "" };
  const C = E.customer ||= {};
  const sell = () => [...cat.filter(c => c.active).map(c => ({ name: c.name, price: c.price, c })), ...pre.filter(p => p.active).map(p => ({ name: p.name, price: p.price, desc: p.includes, c: { tax_rate: p.tax_rate, category: "Package" }, pkg: 1 }))];
  const listHtml = () => sell().map(s => `<option value="${esc(s.name)}">${s.pkg ? "Package " : ""}${inr(s.price)}</option>`).join("");
  const ci = (k, l, x = "") => `<label>${l}<input data-c="${k}" ${x} value="${esc(C[k])}"></label>`;
  const ki = (k, l, t = "text") => `<label>${l}<input data-k="${k}" type="${t}" value="${esc(E[k] ?? "")}"></label>`;
  set(`<div class="card"><div class="bar"><h2 style="margin:0">${E.id ? "Edit draft #" + E.id : "New Bill"}</h2><select data-k="type" style="max-width:170px"><option value="invoice" ${E.type === "invoice" ? "selected" : ""}>Invoice</option><option value="quotation" ${E.type === "quotation" ? "selected" : ""}>Quotation</option><option value="proforma" ${E.type === "proforma" ? "selected" : ""}>Pro forma</option></select><span class="sp"></span><input data-k="issue_date" type="date" style="max-width:160px" value="${esc(E.issue_date)}"></div>
  <div class="f">${ci("name", "Customer name *", 'list="cl" autocomplete="off" autofocus')}${ci("phone", "Phone")}${ci("email", "Email")}${ci("state", "State")}${ci("org", "College / Company")}${ci("gstin", "GSTIN")}<label class="w">Address<input data-c="address" value="${esc(C.address)}"></label>${ki("project", "Project / bill for")}</div>
  <datalist id="cl">${cust.filter(c => !c.archived).map(c => `<option value="${esc(c.name)}">${esc(c.phone || c.org || "")}</option>`).join("")}</datalist><small id="ch" class="muted"></small></div>
  <div class="card"><div class="bar"><input id="ai" list="il" placeholder="Add item…" autocomplete="off"><datalist id="il">${listHtml()}</datalist>
  <select id="ap" style="max-width:200px"><option value="">+ Package...</option>${pre.filter(p => p.active).map(p => `<option value="${p.id}">${esc(p.name)} - ${inr(p.price)}</option>`).join("")}</select><button class="btn ghost" id="ach">+ Charge</button><button class="btn ghost" id="up">⬆ Upload project</button></div><div class="sc"><table id="lines"></table></div></div>
  <div class="two"><div class="card"><div class="f"><label>Discount<select data-k="disc_type"><option value="percent" ${E.disc_type === "percent" ? "selected" : ""}>Percent %</option><option value="fixed" ${E.disc_type === "fixed" ? "selected" : ""}>Fixed ₹</option></select></label>${ki("disc_val", "Discount value", "number")}</div>
  <div class="bar"><input data-k="coupon" placeholder="Coupon code" value="${esc(E.coupon || "")}"><button class="btn au" id="apply">Apply</button></div><p id="cm"></p>${ki("notes", "Notes")}
  <details><summary class="muted">More options</summary><div class="f" style="margin-top:8px">${ki("due_date", "Due date", "date")}${ki("valid_until", "Quote valid until", "date")}${ki("delivery", "Delivery timeline")}${ki("payment_terms", "Payment terms")}${ki("project_type", "Project type")}
  <label>Tax<select data-k="tax_mode"><option value="intra" ${E.tax_mode === "intra" ? "selected" : ""}>CGST + SGST</option><option value="inter" ${E.tax_mode === "inter" ? "selected" : ""}>IGST</option><option value="none" ${E.tax_mode === "none" ? "selected" : ""}>No tax</option></select></label>
  <label>Prices<select data-k="inclusive"><option value="0" ${E.inclusive ? "" : "selected"}>Exclude tax</option><option value="1" ${E.inclusive ? "selected" : ""}>Include tax</option></select></label><label class="w">Terms & conditions<textarea data-k="terms" rows="3">${esc(E.terms)}</textarea></label></div></details></div>
  <div class="card"><div id="tot"></div><div class="f" id="pay" style="margin-top:10px"><label>Paid now<input id="pn" type="number" min="0" step="any" placeholder="0"></label><label>Method<select id="pm"><option>cash</option><option>upi</option><option>bank transfer</option><option>card</option></select></label></div>
  <div class="bar act"><b id="stot"></b><button class="btn au" id="issue">Save & Issue</button><button class="btn ghost" id="save">Save draft</button></div></div></div>`);
  let R, tm;
  const lineIn = (o, i, kind, f, w = 80, ex = "") => `<input style="width:${w}px" type="number" min="0" step="any" data-${kind}="${i}" data-f="${f}" value="${o[f] ?? 0}" ${ex}>`;
  const drawLines = () => {
    $("#lines").innerHTML = "<tr><th>Item</th><th>Qty</th><th>Rate</th><th>Disc%</th><th>Tax%</th><th class='r'>Amount</th><th></th></tr>" + E.items.map((l, i) => `<tr><td><input data-i="${i}" data-f="name" value="${esc(l.name)}"><textarea data-i="${i}" data-f="desc" rows="${(l.desc || "").split("\n").length > 1 ? 3 : 1}" placeholder="Includes / description (optional)" style="margin-top:3px;font-size:12px">${esc(l.desc || "")}</textarea></td><td>${lineIn(l, i, "i", "qty", 70)}</td><td>${lineIn(l, i, "i", "rate", 110)}</td><td>${lineIn(l, i, "i", "disc", 65)}</td><td>${lineIn(l, i, "i", "tax_rate", 65)}</td><td class="r" id="la${i}">${inr((l.qty || 0) * (l.rate || 0))}</td><td><button class="btn sm red" data-x="${i}">×</button></td></tr>`).join("") +
      E.charges.map((l, i) => `<tr><td><input data-c2="${i}" data-f="name" value="${esc(l.name)}"></td><td></td><td>${lineIn(l, i, "c2", "amount", 110)}</td><td></td><td>${lineIn(l, i, "c2", "tax_rate", 65)}</td><td></td><td><button class="btn sm red" data-xc="${i}">×</button></td></tr>`).join("");
  };
  const drawTot = () => {
    if (!R) return; const row = (a, b, n) => +b ? `<tr><td>${a}</td><td class="r">${n ? "- " : ""}${inr(b)}</td></tr>` : "";
    $("#tot").innerHTML = `<table class="tot">${row("Subtotal", R.subtotal)}${row("Discount", R.disc_total, 1)}${row("Coupon", R.coupon_disc, 1)}${row("Charges", R.charges_total)}${E.tax_mode === "intra" ? row("CGST", R.cgst) + row("SGST", R.sgst) : row("IGST", R.igst)}${row("Round off", R.round_amt)}<tr class="g"><td>Total</td><td class="r">${inr(R.total)}</td></tr></table>`;
    $("#stot").textContent = "Total " + inr(R.total);
    $("#cm").innerHTML = R.coupon_error ? `<span class="err">${esc(R.coupon_error)}</span>` : R.coupon_info ? `<span style="color:var(--ok)">Applied ${esc(R.coupon_info)} - saves ${inr(R.coupon_disc)}</span>` : "";
    R.lines.forEach((l, i) => { const e = $("#la" + i); if (e) e.textContent = inr(l.gross) });
  };
  const recalc = () => { clearTimeout(tm); tm = setTimeout(async () => { try { R = await api("calc", "POST", E); drawTot() } catch (er) { $("#tot").innerHTML = `<p class="err">${esc(er.message)}</p>` } }, 200) };
  const autoTax = () => { if (C.state && SET.state) { E.tax_mode = C.state.trim().toLowerCase() === SET.state.trim().toLowerCase() ? "intra" : "inter"; $("[data-k=tax_mode]").value = E.tax_mode } };
  const hint = () => { $("#ch").textContent = E.customer_id ? "✓ Existing customer - edits update their record" : C.name ? "New customer - will be saved automatically" : "" };
  const addCat = c => E.items.push({ name: c.name, qty: 1, rate: c.price, disc: 0, tax_rate: c.tax_rate, item_id: c.id, cat: c.category || "" });
  const addSell = s => E.items.push({ name: s.pkg && E.project ? E.project + " - " + s.name : s.name, desc: s.desc || "", qty: 1, rate: s.price, disc: 0, tax_rate: s.c.tax_rate, item_id: s.c.id, cat: s.c.category || "" });
  const addIt = () => { const v = $("#ai").value.trim(); if (!v) return; const c = sell().find(x => x.name.toLowerCase() === v.toLowerCase()); c ? addSell(c) : E.items.push({ name: v, qty: 1, rate: 0, disc: 0, tax_rate: +SET.default_tax || 0, cat: "" }); $("#ai").value = ""; drawLines(); recalc(); const r = document.querySelectorAll("#lines [data-f=rate]"); r.length && r[r.length - 1].focus() };
  $("#ai").onchange = addIt; $("#ai").onkeydown = e => { if (e.key === "Enter") { e.preventDefault(); addIt() } };
  $("#ap").onchange = e => { const p = sell().find(x => x.pkg && x.name === (pre.find(y => y.id == e.target.value) || {}).name); if (p) { addSell(p); drawLines(); recalc() } e.target.value = "" };
  $("#up").onclick = () => form("Upload project / software", [{ k: "file", l: "Project file *", t: "file", up: "project", w: 1 }, { k: "name", l: "Name", req: 1 }, { k: "price", l: "Price", t: "number" }, { k: "tax_rate", l: "Tax %", t: "number" }, { k: "category", l: "Category", t: "select", o: ["AI/ML", "Cybersecurity", "Web/Mobile", "Python", "Java", "Flutter", "IoT", "Data Science", "Database", "Custom"] }], { tax_rate: SET.default_tax || 18 },
    async v => { v.kind = "project"; v.active = 1; const r = await api("e/catalogue", "POST", v); const row = { ...v, id: r.id, price: +v.price || 0, tax_rate: +v.tax_rate || 0 }; cat.push(row); LK = {}; $("#il").innerHTML = listHtml(); addCat(row); drawLines(); recalc(); toast("Project saved and added to the bill") });
  $("#ach").onclick = () => { E.charges.push({ name: "Delivery fee", amount: 0, tax_rate: +SET.default_tax || 0 }); drawLines(); recalc() };
  $("#lines").oninput = e => { const t = e.target, f = t.dataset.f; if (!f) return; const o = t.dataset.i != null ? E.items[t.dataset.i] : E.charges[t.dataset.c2]; o[f] = f === "name" || f === "desc" ? t.value : t.value === "" ? 0 : +t.value; recalc() };
  $("#lines").onclick = e => { const b = e.target.closest("button"); if (!b) return; if (b.dataset.x != null) E.items.splice(b.dataset.x, 1); else if (b.dataset.xc != null) E.charges.splice(b.dataset.xc, 1); else return; drawLines(); recalc() };
  document.querySelectorAll("[data-c]").forEach(el => el.oninput = () => {
    const k = el.dataset.c; C[k] = el.value;
    if (k === "name") { const m = cust.find(c => !c.archived && c.name.toLowerCase() === el.value.trim().toLowerCase()); E.customer_id = m ? m.id : null; if (m) { Object.assign(C, m); document.querySelectorAll("[data-c]").forEach(x => x.value = C[x.dataset.c] || ""); autoTax() } }
    if (k === "state") autoTax(); hint(); recalc();
  });
  document.querySelectorAll("[data-k]").forEach(el => el.oninput = el.onchange = () => { const k = el.dataset.k; E[k] = k === "coupon" ? el.value.toUpperCase() : k === "inclusive" ? +el.value : el.value; if (k === "type") $("#pay").style.display = E.type === "invoice" ? "" : "none"; recalc() });
  $("#apply").onclick = recalc;
  const save = async issue => {
    try {
      const r = await api("docs" + (E.id ? "/" + E.id : ""), E.id ? "PUT" : "POST", E); E.id = r.id;
      if (issue) { await api(`docs/${r.id}/issue`, "POST"); const pn = +$("#pn").value; if (pn > 0 && E.type === "invoice") await api(`docs/${r.id}/payments`, "POST", { amount: pn, method: $("#pm").value }) }
      LK = {}; toast(issue ? "Bill issued" : "Draft saved"); location.hash = "#/doc/" + r.id;
    } catch (er) { toast(er.message, 1) }
  };
  $("#save").onclick = () => save(0); $("#issue").onclick = () => save(1);
  $("#pay").style.display = E.type === "invoice" ? "" : "none";
  hint(); drawLines(); recalc();
};
P.invoice = P.bill;

P.payments = async () => {
  const rows = await api("payments");
  set(`<div class="card"><h2>Payments & Receipts</h2><div class="sc"><table><tr><th>Receipt</th><th>Date</th><th>Invoice</th><th>Customer</th><th>Method</th><th>Type</th><th class="r">Amount</th><th></th></tr>${rows.map(p => `<tr><td>${esc(p.receipt)}</td><td>${p.date}</td><td><a href="#/doc/${p.doc_id}">${esc(p.number)}</a></td><td>${esc(p.cname)}</td><td>${esc(p.method)} ${esc(p.ref)}</td><td>${p.kind}</td><td class="r">${inr(p.amount)}</td><td><a target="_blank" href="/receipt/${p.id}/print">Print</a></td></tr>`).join("") || "<tr><td class=muted>No payments yet. Record them from an issued invoice.</td></tr>"}</table></div></div>`);
};
P.reports = async () => {
  const K = { sales: "Sales", collections: "Collections", receivables: "Receivables", overdue: "Overdue invoices", customers: "Customer history", category: "Category sales", deliverables: "Deliverable sales", discounts: "Discounts", coupons: "Coupon usage", refunds: "Refunds", expenses: "Expenses", profit: "Estimated operating profit" };
  set(`<div class="card"><h2>Reports</h2><div class="bar"><select id="k">${Object.entries(K).map(([a, b]) => `<option value="${a}">${b}</option>`).join("")}</select><input type="date" id="f"><input type="date" id="t"><button class="btn au" id="run">Run</button><a class="btn ghost" id="csv">CSV</a><button class="btn ghost" onclick="print()">PDF / Print</button></div><div class="sc" id="out"></div></div>`);
  const qs = () => `kind=${$("#k").value}&from=${$("#f").value}&to=${$("#t").value}`;
  const run = async () => { try { const r = await api("report?" + qs()); $("#csv").href = "/api/report?csv=1&" + qs(); $("#out").innerHTML = `<table><tr>${r.cols.map(c => `<th>${esc(c)}</th>`).join("")}</tr>${r.rows.map(x => `<tr>${x.map(v => `<td>${typeof v === "number" ? inr(v) : esc(v)}</td>`).join("")}</tr>`).join("") || "<tr><td class=muted>No data</td></tr>"}</table>` } catch (e) { toast(e.message, 1) } };
  $("#run").onclick = run; $("#k").onchange = run; run();
};
P.business = async () => {
  SET = await api("settings"); const s = SET;
  const F = [["biz_name", "Business name"], ["owner", "Owner"], ["phone", "Phone"], ["email", "Email"], ["website", "Website"], ["gstin", "GSTIN"], ["pan", "PAN"], ["state", "State (used to pick CGST/SGST vs IGST)"], ["currency", "Currency symbol"], ["default_tax", "Default tax %"], ["due_days", "Default payment due (days)"], ["inv_prefix", "Invoice prefix"], ["quo_prefix", "Quotation prefix"], ["pf_prefix", "Pro forma prefix"], ["rcp_prefix", "Receipt prefix"], ["accent", "Accent colour", "color"]];
  const T = [["address", "Address"], ["pay_instr", "Payment instructions (UPI / bank details)"], ["terms", "Default terms & conditions"], ["footer", "Document footer"]];
  set(`<div class="card"><h2>Business & Template Settings</h2><form id="sf"><div class="f">${F.map(([k, l, t]) => `<label>${l}<input name="${k}" type="${t || "text"}" value="${esc(s[k])}"></label>`).join("")}<label>Show logo on documents<select name="show_logo"><option value="1" ${s.show_logo == 1 ? "selected" : ""}>Yes</option><option value="0" ${s.show_logo == 1 ? "" : "selected"}>No</option></select></label>
  <label>Logo<input type="file" data-up="logo" accept=".png,.jpg,.jpeg,.webp"></label><label>Signature<input type="file" data-up="signature" accept=".png,.jpg,.jpeg,.webp"></label></div>${T.map(([k, l]) => `<label>${l}<textarea name="${k}" rows="3">${esc(s[k])}</textarea></label>`).join("")}<button class="btn au">Save settings</button></form></div>
  <div class="card"><h2>Change password</h2><form id="pw" class="bar"><input type="password" name="old" placeholder="Current" required><input type="password" name="new" placeholder="New (min 8)" required minlength="8"><button class="btn">Change</button></form></div>`);
  $("#sf").onsubmit = async e => {
    e.preventDefault(); const v = Object.fromEntries(new FormData(e.target)); delete v[""];
    try { for (const f of document.querySelectorAll("[data-up]")) if (f.files[0]) { const fd = new FormData(); fd.append("file", f.files[0]); v[f.dataset.up] = (await api("upload", "POST", fd)).name } SET = await api("settings", "PUT", v); toast("Saved") } catch (er) { toast(er.message, 1) }
  };
  $("#pw").onsubmit = async e => { e.preventDefault(); try { await api("password", "POST", Object.fromEntries(new FormData(e.target))); toast("Password changed"); e.target.reset() } catch (er) { toast(er.message, 1) } };
};
P.phone = async () => {
  const d = await api("phone");
  set(`<div class="card"><h2>Use Perixa Billing Pro on your phone</h2><label style="display:flex;gap:10px;align-items:center;color:var(--tx);font-size:14px"><input type="checkbox" id="pa" ${d.enabled ? "checked" : ""}> Allow phones on my Wi-Fi to open this app</label>
  ${d.enabled ? (d.urls.length ? `<div style="display:flex;gap:22px;flex-wrap:wrap;align-items:center;margin-top:12px"><div style="width:190px;background:#fff;padding:6px;border-radius:12px">${d.qr || ""}</div><div><p>1. Connect your phone to the <b>same Wi-Fi</b> as this PC.<br>2. Scan the code, or type this in Chrome:</p>${d.urls.map(u => `<p style="font-size:18px"><b>${esc(u)}</b></p>`).join("")}<p>3. Sign in with your normal username and password.<br>4. Chrome menu ⋮ → <b>Add to Home screen</b>.</p></div></div>` : '<p class="err">No Wi-Fi / network address found on this PC.</p>') : '<p class="muted">Turned off. Turn it on, then scan the code from your phone.</p>'}
  <p class="muted" style="margin-top:14px">Your bills, customers and packages stay on this PC. The phone reads and saves to the same data, so both are always in sync. The PC must be on with the app open. If Windows asks about network access, allow <b>Private networks</b>.</p></div>`);
  $("#pa").onchange = async e => { await api("settings", "PUT", { phone_access: e.target.checked ? "1" : "0" }); route() };
};
const TABS = [["business", "Business & Template"], ["phone", "📱 Phone"], ["customers", "Customers"], ["catalogue", "Items / Projects"], ["coupons", "Coupons"], ["expenses", "Expenses"], ["deals", "Deals"], ["backup", "Backup"], ["audit", "Audit Log"]];
P.settings = async (tab = "business") => {
  set(`<div class="bar">${TABS.map(([k, l]) => `<a class="btn ${k === tab ? "au" : "ghost"}" href="#/settings/${k}">${l}</a>`).join("")}</div><div id="sub"></div>`);
  OUT = "#sub"; try { await P[tab]() } finally { OUT = "#main" }
};
P.backup = async () => {
  set(`<div class="card"><h2>Backup / Restore</h2><p>Your data lives in <code>data/perixa.db</code> and survives restarts. Download a full backup regularly.</p><a class="btn au" href="/api/backup">Download backup</a>
  <hr><p>Restore from a backup file (a safety copy of the current database is kept automatically):</p><div class="bar"><input type="file" id="rf" accept=".db"><button class="btn red" id="rb">Restore</button></div>
  <hr><p>CSV exports: use the <a href="#/reports">Reports</a> page.</p></div>`);
  $("#rb").onclick = async () => { const f = $("#rf").files[0]; if (!f || !confirm("Replace ALL current data with this backup?")) return; const fd = new FormData(); fd.append("file", f); try { await api("restore", "POST", fd); toast("Restored"); LK = {}; location.hash = "#/dashboard" } catch (e) { toast(e.message, 1) } };
};
P.audit = async () => {
  const r = await api("audit");
  set(`<div class="card"><h2>Audit Log</h2><div class="sc"><table><tr><th>Time</th><th>User</th><th>Action</th><th>Detail</th></tr>${r.map(a => `<tr><td>${esc(a.ts)}</td><td>${esc(a.user)}</td><td>${esc(a.action)}</td><td>${esc(a.detail)}</td></tr>`).join("")}</table></div></div>`);
};

// ------------------------------------------------------------ router
async function route() {
  const [p, a, b] = (location.hash.slice(2) || "bill").split("/");
  document.querySelectorAll("#nav a,#bnav a").forEach(x => x.classList.toggle("on", x.getAttribute("href") === "#/" + p || (p === "invoice" && x.getAttribute("href") === "#/bill") || (p === "doc" && x.getAttribute("href") === "#/statement") || (/^(customer)$/.test(p) && x.getAttribute("href") === "#/settings") || (p === "dashboard" && false)));
  $("#nav").classList.remove("open"); $("#sync").textContent = "Live " + new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  try { if (!SET.biz_name) SET = await api("settings"); await (P[p] || P.bill)(a, b) } catch (e) { set(`<div class="card err">${esc(e.message)}</div>`) }
}
$("#nav").innerHTML = `<h3>PERIXA Billing Pro</h3>` + NAV.map(([h, l]) => `<a href="#/${h}">${l}</a>`).join("") + `<a href="#" id="lo">Sign out</a>`;
$("#lo").onclick = async e => { e.preventDefault(); await api("logout", "POST"); location.reload() };
$("#menu").onclick = () => $("#nav").classList.toggle("open");
$("#theme").onclick = () => { const d = document.documentElement.dataset.theme === "dark" ? "light" : "dark"; document.documentElement.dataset.theme = d; try { localStorage.t = d } catch { } };
try { document.documentElement.dataset.theme = localStorage.t || "light" } catch { }
const IC = { bill: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>', statement: '<path d="M5 6h14M5 12h14M5 18h9"/>', packages: '<path d="M4 8l8-4 8 4v8l-8 4-8-4z"/><path d="M4 8l8 4 8-4M12 12v8"/>', dashboard: '<path d="M5 20V10M12 20V4M19 20v-7"/>', more: '<path d="M5 12h.01M12 12h.01M19 12h.01" stroke-width="3.5"/>' };
$("#bnav").innerHTML = ["bill", "statement", "packages", "dashboard"].map(k => `<a href="#/${k}"><svg viewBox="0 0 24 24">${IC[k]}</svg>${NAV.find(n => n[0] === k)[1].replace("New ", "")}</a>`).join("") + `<a href="#" id="more"><svg viewBox="0 0 24 24">${IC.more}</svg>More</a>`;
$("#more").onclick = e => { e.preventDefault(); $("#nav").classList.toggle("open") };
$("#main").onclick = e => { if (!e.target.closest("[data-a]")) $("#nav").classList.remove("open") };
// phone: label table cells so CSS can turn rows into cards, keep sync indicator, refresh lists when returning to the app
function labelize() { document.querySelectorAll("#main table:not(.tot)").forEach(t => { const hr = t.querySelector("tr:has(th)"); if (!hr) return; const h = [...hr.children].map(x => x.textContent.trim()); t.classList.add("rt"); t.querySelectorAll("tr").forEach(r => [...r.children].forEach((c, i) => { if (c.tagName === "TD") c.dataset.l = h[i] || "" })) }) }
let lt; new MutationObserver(() => { cancelAnimationFrame(lt); lt = requestAnimationFrame(labelize) }).observe($("#main"), { childList: true, subtree: true });
const pingNow = async () => { let ok = false; try { const c = new AbortController(); setTimeout(() => c.abort(), 4000); ok = (await fetch("/api/ping", { signal: c.signal, cache: "no-store" })).ok } catch { } $("#dot").className = ok ? "" : "off"; $("#off").style.display = ok ? "none" : "block"; return ok };
setInterval(pingNow, 10000);
document.addEventListener("visibilitychange", async () => { if (document.visibilityState === "visible" && await pingNow() && /^#\/(statement|dashboard|packages)?$/.test(location.hash) && location.hash !== "") route() });
addEventListener("hashchange", route); route();
