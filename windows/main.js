const { app, BrowserWindow, Tray, Menu, nativeImage, ipcMain, shell, screen, nativeTheme } = require('electron')
const path = require('path')
const { execSync } = require('child_process')

const PARTITION = 'persist:claude'
const CLAUDE_URL = 'https://claude.ai/'
const POLL_MS = 3 * 60 * 1000
const FETCH_TIMEOUT_MS = 30 * 1000

let tray = null
let popover = null
let fetchWin = null
let loginWin = null
let iconWin = null
let pollTimer = null

// state: 'loading' | 'ok' | 'login' | 'error'
let latest = { state: 'loading', error: null, workspaces: [], updatedAt: null }

if (!app.requestSingleInstanceLock()) {
  app.quit()
}

// claude.ai (and Cloudflare) treat an Electron UA differently — present as plain Chrome
app.userAgentFallback = app.userAgentFallback
  .replace(/\sElectron\/[\d.]+/, '')
  .replace(/\stally\/[\d.]+/i, '')

// The same JS the Mac app injects: talk to claude.ai's own usage API with the
// session cookies already in the hidden window. No DOM scraping.
const FETCH_JS = `
(async () => {
  try {
    const orgResp = await fetch('/api/organizations', { credentials: 'include', headers: { Accept: 'application/json' } });
    if (orgResp.status === 401 || orgResp.status === 403) return { state: 'login' };
    if (!orgResp.ok) return { state: 'error', error: 'org list failed: HTTP ' + orgResp.status };
    const ct = orgResp.headers.get('content-type') || '';
    if (!ct.includes('json')) return { state: 'login' };
    const orgs = await orgResp.json();
    const out = [];
    for (const org of orgs) {
      try {
        const r = await fetch('/api/organizations/' + org.uuid + '/usage', { credentials: 'include', headers: { Accept: 'application/json' } });
        if (r.status === 403 || r.status === 404) continue; // org without usage access (e.g. API console org) — not an error, just skip
        if (!r.ok) { out.push({ uuid: org.uuid, name: org.name, error: 'usage fetch failed: HTTP ' + r.status }); continue; }
        out.push({
          uuid: org.uuid,
          name: org.name,
          capabilities: org.capabilities || [],
          raven_type: org.raven_type || null,
          usage: await r.json(),
        });
      } catch (e) { out.push({ uuid: org.uuid, name: org.name, error: String(e) }); }
    }
    return { state: 'ok', orgs: out };
  } catch (e) { return { state: 'error', error: String(e) }; }
})()
`

function metric(m) {
  if (!m || typeof m !== 'object' || m.utilization == null) return null
  return { pct: Math.max(0, Math.min(100, Number(m.utilization) || 0)), resetsAt: m.resets_at || null }
}

function parseOrg(o) {
  const u = o.usage || {}
  // Team/enterprise orgs carry the "raven" capability or a raven_type — plan-tier
  // agnostic, unlike matching claude_max/claude_pro (which broke once before)
  const isTeam = (o.capabilities || []).includes('raven') || !!o.raven_type
  const perModel = Object.entries(u)
    .filter(([k, v]) => k.startsWith('seven_day_') && v && typeof v === 'object' && v.utilization != null)
    .map(([k, v]) => ({ key: k, label: k.replace('seven_day_', '').replace(/_/g, ' '), ...metric(v) }))
  return {
    uuid: o.uuid,
    name: o.name,
    isTeam,
    session: metric(u.five_hour),
    weekly: metric(u.seven_day),
    perModel,
    extra: u.extra_usage && u.extra_usage.is_enabled
      ? { used: u.extra_usage.used_credits, limit: u.extra_usage.monthly_limit, currency: u.extra_usage.currency || 'USD' }
      : null,
    error: o.error || null,
  }
}

// The taskbar follows the "Windows mode" theme (SystemUsesLightTheme), which is
// separate from the app light/dark mode that nativeTheme reports on Windows
let taskbarLightCache = null
function taskbarIsLight() {
  if (taskbarLightCache !== null) return taskbarLightCache
  try {
    const out = execSync(
      'reg query HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize /v SystemUsesLightTheme',
      { encoding: 'utf8' }
    )
    taskbarLightCache = /0x1\s*$/m.test(out.trim())
  } catch {
    taskbarLightCache = false
  }
  return taskbarLightCache
}

function alertLevel(pct) {
  if (pct >= 80) return 'red'
  if (pct >= 60) return 'orange'
  return 'normal'
}

function shortCountdown(resetsAt) {
  if (!resetsAt) return ''
  const ms = new Date(resetsAt).getTime() - Date.now()
  if (isNaN(ms) || ms <= 0) return 'now'
  const mins = Math.floor(ms / 60000)
  const d = Math.floor(mins / 1440), h = Math.floor((mins % 1440) / 60), m = mins % 60
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

// ---------- windows ----------

function ensureFetchWin() {
  return new Promise((resolve, reject) => {
    if (fetchWin && !fetchWin.isDestroyed()) return resolve()
    fetchWin = new BrowserWindow({
      show: false,
      webPreferences: { partition: PARTITION, backgroundThrottling: false },
    })
    fetchWin.webContents.once('did-finish-load', () => resolve())
    fetchWin.webContents.once('did-fail-load', (_e, code, desc) => reject(new Error(`claude.ai load failed: ${desc} (${code})`)))
    fetchWin.loadURL(CLAUDE_URL).catch(reject)
  })
}

function ensureIconWin() {
  return new Promise((resolve, reject) => {
    if (iconWin && !iconWin.isDestroyed()) return resolve()
    iconWin = new BrowserWindow({ show: false, width: 64, height: 64 })
    iconWin.webContents.once('did-finish-load', () => resolve())
    iconWin.loadFile(path.join(__dirname, 'icon.html')).catch(reject)
  })
}

function showLoginWindow() {
  if (loginWin && !loginWin.isDestroyed()) { loginWin.focus(); return }
  loginWin = new BrowserWindow({
    width: 980,
    height: 760,
    title: 'Sign in to Claude — Tally',
    webPreferences: { partition: PARTITION },
  })
  loginWin.loadURL(CLAUDE_URL)
  loginWin.on('closed', () => { loginWin = null; poll() })
}

function createPopover() {
  popover = new BrowserWindow({
    width: 380,
    height: 320,
    show: false,
    frame: false,
    resizable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js') },
  })
  popover.loadFile(path.join(__dirname, 'popover.html'))
  popover.on('blur', () => { if (popover && !popover.isDestroyed()) popover.hide() })
}

function positionPopover() {
  if (!popover || popover.isDestroyed() || !tray) return
  const trayBounds = tray.getBounds()
  const display = screen.getDisplayNearestPoint({ x: trayBounds.x, y: trayBounds.y })
  const wa = display.workArea
  const [w, h] = popover.getSize()
  const x = Math.round(Math.min(Math.max(trayBounds.x + trayBounds.width / 2 - w / 2, wa.x + 8), wa.x + wa.width - w - 8))
  const y = trayBounds.y > wa.y + wa.height / 2 ? Math.round(trayBounds.y - h - 8) : Math.round(trayBounds.y + trayBounds.height + 8)
  popover.setPosition(x, y)
}

function togglePopover() {
  if (!popover || popover.isDestroyed()) createPopover()
  if (popover.isVisible()) { popover.hide(); return }
  positionPopover()
  popover.show()
  popover.focus()
  popover.webContents.send('usage', latest)
}

// ---------- tray ----------

async function updateTray() {
  await ensureIconWin()
  const sessions = latest.workspaces.filter(w => w.session).map(w => w.session.pct)
  const worst = sessions.length ? Math.max(...sessions) : 0
  const level = latest.state === 'ok' ? alertLevel(worst) : 'gray'
  const dataUrl = await iconWin.webContents.executeJavaScript(`drawIcon(${worst}, ${JSON.stringify(level)}, ${taskbarIsLight()})`)
  const img = nativeImage.createFromDataURL(dataUrl)
  tray.setImage(img)

  let tip = 'Tally'
  if (latest.state === 'login') tip = 'Tally — sign in required (right-click)'
  else if (latest.state === 'error') tip = `Tally — ${latest.error || 'error'}`
  else if (latest.workspaces.length) {
    tip = 'Tally — ' + latest.workspaces
      .map(w => `${w.name}: ${w.session ? Math.round(w.session.pct) + '%' : '?'}${w.session && w.session.resetsAt ? ' (' + shortCountdown(w.session.resetsAt) + ')' : ''}`)
      .join(' · ')
  }
  tray.setToolTip(tip.slice(0, 127))
}

function buildContextMenu() {
  return Menu.buildFromTemplate([
    { label: 'Sign in to Claude…', click: showLoginWindow },
    { label: 'Open claude.ai in browser', click: () => shell.openExternal('https://claude.ai/settings/usage') },
    { label: 'Refresh now', click: poll },
    { type: 'separator' },
    { label: 'Quit Tally', click: () => app.quit() },
  ])
}

// ---------- polling ----------

async function poll() {
  try {
    await ensureFetchWin()
    const raw = await Promise.race([
      fetchWin.webContents.executeJavaScript(FETCH_JS, true),
      new Promise((_r, rej) => setTimeout(() => rej(new Error('fetch timed out')), FETCH_TIMEOUT_MS)),
    ])
    if (raw.state === 'ok') {
      latest = { state: 'ok', error: null, workspaces: raw.orgs.map(parseOrg), updatedAt: Date.now() }
    } else if (raw.state === 'login') {
      latest = { state: 'login', error: null, workspaces: [], updatedAt: Date.now() }
    } else {
      // keep last-good numbers, surface the error
      latest = { ...latest, state: latest.workspaces.length ? 'ok' : 'error', error: raw.error || 'unknown error', updatedAt: Date.now() }
    }
  } catch (e) {
    latest = { ...latest, state: latest.workspaces.length ? 'ok' : 'error', error: String(e.message || e), updatedAt: Date.now() }
  }
  await updateTray().catch(() => {})
  if (popover && !popover.isDestroyed() && popover.isVisible()) popover.webContents.send('usage', latest)
}

// ---------- ipc ----------

ipcMain.on('request-usage', e => e.sender.send('usage', latest))
ipcMain.on('resize', (_e, h) => {
  if (!popover || popover.isDestroyed()) return
  const clamped = Math.max(160, Math.min(640, Math.round(h)))
  popover.setContentSize(380, clamped)
  positionPopover()
})
ipcMain.on('sign-in', () => { if (popover) popover.hide(); showLoginWindow() })
ipcMain.on('refresh', () => poll())
ipcMain.on('open-site', () => shell.openExternal('https://claude.ai/settings/usage'))
ipcMain.on('quit', () => app.quit())

// ---------- lifecycle ----------

app.whenReady().then(async () => {
  app.setAppUserModelId('com.2amideas.tally')
  tray = new Tray(nativeImage.createEmpty())
  tray.setContextMenu(buildContextMenu())
  tray.on('click', togglePopover)
  await updateTray().catch(() => {})
  createPopover()
  poll()
  pollTimer = setInterval(poll, POLL_MS)
  nativeTheme.on('updated', () => { taskbarLightCache = null; updateTray().catch(() => {}) })
})

// tray app: stay alive with no windows open
app.on('window-all-closed', () => {})
