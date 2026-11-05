const { app, BrowserWindow, Menu, shell } = require('electron');
const { spawn } = require('child_process');
const path = require('path'), net = require('net'), http = require('http');
let srv, win;
if (!app.requestSingleInstanceLock()) app.quit();
const freePort = () => new Promise(r => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => r(p)); }); });
const tryPort = p => new Promise(r => { const s = net.createServer(); s.once('error', () => r(false)); s.listen(p, '0.0.0.0', () => s.close(() => r(true))); });
const pickPort = async () => (await tryPort(5057)) ? 5057 : freePort(); // fixed port so the phone address stays the same
const ready = (port, n = 80) => new Promise((ok, no) => { const t = () => http.get({ host: '127.0.0.1', port, path: '/favicon.ico' }, () => ok()).on('error', () => n-- > 0 ? setTimeout(t, 250) : no(new Error('Server did not start'))); t(); });
function startServer(port) {
  const env = { ...process.env, PERIXA_PORT: String(port), PERIXA_DATA: path.join(app.getPath('userData'), 'data') };
  srv = app.isPackaged ? spawn(path.join(process.resourcesPath, 'perixa-server.exe'), [], { env, windowsHide: true })
                       : spawn(process.platform === 'win32' ? 'python' : 'python3', ['app.py'], { env, cwd: __dirname, windowsHide: true });
  srv.on('error', e => { require('electron').dialog.showErrorBox('Perixa Billing Pro', 'Could not start the database engine: ' + e.message); app.quit(); });
}
app.whenReady().then(async () => {
  Menu.setApplicationMenu(null);
  const port = await pickPort(); startServer(port);
  try { await ready(port); } catch (e) { require('electron').dialog.showErrorBox('Perixa Billing Pro', e.message); return app.quit(); }
  win = new BrowserWindow({ width: 1366, height: 820, minWidth: 900, minHeight: 600, title: 'Perixa Billing Pro', icon: path.join(__dirname, 'static', 'app-icon.ico'), autoHideMenuBar: true, backgroundColor: '#0b1f44' });
  win.loadURL(`http://127.0.0.1:${port}/`);
  // invoices/receipts open in their own print window; anything external goes to the browser
  win.webContents.setWindowOpenHandler(({ url }) => url.startsWith(`http://127.0.0.1:${port}`)
    ? { action: 'allow', overrideBrowserWindowOptions: { width: 900, height: 900, autoHideMenuBar: true } } : (shell.openExternal(url), { action: 'deny' }));
});
app.on('second-instance', () => { if (win) { win.isMinimized() && win.restore(); win.focus(); } });
app.on('window-all-closed', () => app.quit());
app.on('quit', () => { try { srv && srv.kill(); } catch {} });
