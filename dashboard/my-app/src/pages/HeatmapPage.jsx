import { useEffect, useState, useRef } from 'react'
import { Activity, Wifi, WifiOff } from 'lucide-react'
import ScamMap from '../components/ScamMap'
import { getScamHeatmap } from '../services/api'

const MOCK_POINTS = [
  [28.6139, 77.2090, 0.9],
  [19.0760, 72.8777, 0.85],
  [13.0827, 80.2707, 0.7],
  [22.5726, 88.3639, 0.75],
  [12.9716, 77.5946, 0.8],
  [17.3850, 78.4867, 0.65],
  [23.0225, 72.5714, 0.6],
  [18.5204, 73.8567, 0.7],
  [26.8467, 80.9462, 0.55],
  [25.5941, 85.1376, 0.5],
  [21.1458, 79.0882, 0.45],
  [30.7333, 76.7794, 0.6],
  [26.9124, 75.7873, 0.55],
  [22.3072, 73.1812, 0.4],
  [11.0168, 76.9558, 0.5],
]

export default function HeatmapPage() {
  const [points, setPoints] = useState(MOCK_POINTS)
  const [wsConnected, setWsConnected] = useState(false)
  const [totalPoints, setTotalPoints] = useState(MOCK_POINTS.length)
  const wsRef = useRef(null)

  useEffect(() => {
    getScamHeatmap()
      .then((res) => {
        if (res.data?.points?.length) {
          setPoints(res.data.points)
          setTotalPoints(res.data.points.length)
        }
      })
      .catch(() => {})
  }, [])

  useEffect(() => {
    const wsUrl =
      (import.meta.env.VITE_BACKEND_URL || 'http://localhost:8000')
        .replace(/^http/, 'ws') + '/ws/dashboard'
    try {
      const ws = new WebSocket(wsUrl)
      wsRef.current = ws
      ws.onopen  = () => setWsConnected(true)
      ws.onclose = () => setWsConnected(false)
      ws.onerror = () => setWsConnected(false)
      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          if (data.type === 'new_scam' && data.lat && data.lng) {
            setPoints((prev) => [...prev, [data.lat, data.lng, data.intensity || 0.8]])
            setTotalPoints((p) => p + 1)
          }
        } catch {}
      }
    } catch {}
    return () => wsRef.current?.close()
  }, [])

  return (
    <div className="flex flex-col h-full gap-4">
      <div className="flex items-center justify-between flex-shrink-0">
        <div>
          <h1 className="text-white text-2xl font-bold tracking-tight" style={{ fontFamily: "'DM Sans', sans-serif" }}>
            Scam Heatmap
          </h1>
          <p className="text-[#4a5568] text-sm mt-0.5">Geographic distribution of scam activity across India</p>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-[#111827] border border-[#1e2535] text-xs">
            <Activity size={13} className="text-sky-400" />
            <span className="text-[#94a3b8]">{totalPoints} hotspots</span>
          </div>
          <div className={`flex items-center gap-2 px-3 py-1.5 rounded-lg border text-xs
            ${wsConnected ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400' : 'bg-[#111827] border-[#1e2535] text-[#4a5568]'}`}>
            {wsConnected ? <Wifi size={13} /> : <WifiOff size={13} />}
            {wsConnected ? 'Live' : 'Offline'}
          </div>
        </div>
      </div>

      <div className="flex items-center gap-4 flex-shrink-0 bg-[#0d1117] border border-[#1e2535] rounded-lg px-4 py-2.5">
        <span className="text-[#4a5568] text-xs font-medium uppercase tracking-wider">Intensity:</span>
        {[['bg-blue-500', 'Low'], ['bg-orange-400', 'Medium'], ['bg-red-500', 'High']].map(([color, label]) => (
          <div key={label} className="flex items-center gap-1">
            <div className={`w-4 h-4 rounded-sm ${color}`} />
            <span className="text-xs text-[#6b7a99]">{label}</span>
          </div>
        ))}
      </div>

      {/* ↓ ScamMap replaces the inline MapContainer block */}
      <ScamMap
        points={points}
        center={[20.5937, 78.9629]}
        zoom={5}
        className="flex-1 min-h-[500px]"
      />
    </div>
  )
}