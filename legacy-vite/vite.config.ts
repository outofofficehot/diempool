import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    allowedHosts: ['violet-dodos-melt.loca.lt', 'carefully-dod-san-named.trycloudflare.com'],
  },
  preview: {
    allowedHosts: ['carefully-dod-san-named.trycloudflare.com'],
  },
})
