const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('tally', {
  onUsage: cb => ipcRenderer.on('usage', (_e, data) => cb(data)),
  requestUsage: () => ipcRenderer.send('request-usage'),
  signIn: () => ipcRenderer.send('sign-in'),
  refresh: () => ipcRenderer.send('refresh'),
  openSite: () => ipcRenderer.send('open-site'),
  resize: h => ipcRenderer.send('resize', h),
  quit: () => ipcRenderer.send('quit'),
})
