import { BrowserRouter, Routes, Route } from 'react-router-dom'
import L from 'leaflet'
import iconUrl from 'leaflet/dist/images/marker-icon.png'
import iconShadow from 'leaflet/dist/images/marker-shadow.png'

// Leaflet icon bug fix
delete L.Icon.Default.prototype._getIconUrl
L.Icon.Default.mergeOptions({ iconUrl, shadowUrl: iconShadow })

import Sidebar from './components/Sidebar'
import OverviewPage from './pages/OverviewPage'
import HeatmapPage from './pages/HeatmapPage'
import CallsPage from './pages/CallsPage'
import ScamDatabasePage from './pages/ScamDatabasePage'
import ReportsPage from './pages/ReportsPage'

export default function App() {
  return (
    <BrowserRouter>
      <div className="flex h-screen bg-[#070a0f] text-white overflow-hidden">
        <Sidebar />
        <main className="flex-1 overflow-y-auto">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 lg:py-8">
            <Routes>
              <Route path="/" element={<OverviewPage />} />
              <Route path="/heatmap" element={<HeatmapPage />} />
              <Route path="/calls" element={<CallsPage />} />
              <Route path="/scam-database" element={<ScamDatabasePage />} />
              <Route path="/reports" element={<ReportsPage />} />
            </Routes>
          </div>
        </main>
      </div>
    </BrowserRouter>
  )
}