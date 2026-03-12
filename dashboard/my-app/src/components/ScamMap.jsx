import { useEffect, useRef } from 'react'
import { MapContainer, TileLayer, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import 'leaflet.heat'

/**
 * Inner layer — must be rendered inside a MapContainer.
 * Re-draws whenever `points` changes.
 */
function HeatmapLayer({ points, options = {} }) {
  const map = useMap()
  const heatRef = useRef(null)

  useEffect(() => {
    if (!map || !points?.length) return

    if (heatRef.current) {
      map.removeLayer(heatRef.current)
    }

    heatRef.current = L.heatLayer(points, {
      radius: 25,
      blur: 15,
      maxZoom: 17,
      gradient: { 0.4: 'blue', 0.7: 'orange', 1.0: 'red' },
      ...options,
    }).addTo(map)

    return () => {
      if (heatRef.current) {
        map.removeLayer(heatRef.current)
      }
    }
  }, [map, points, options])

  return null
}

/**
 * ScamMap — self-contained Leaflet heatmap.
 *
 * Props:
 *   points       [lat, lng, intensity][]   required
 *   center       [lat, lng]                default: India centre
 *   zoom         number                    default: 5
 *   className    string                    extra classes for the wrapper div
 *   heatOptions  object                    forwarded to L.heatLayer()
 */
export default function ScamMap({
  points = [],
  center = [20.5937, 78.9629],
  zoom = 5,
  className = '',
  heatOptions = {},
}) {
  return (
    <div className={`rounded-xl overflow-hidden border border-[#1e2535] ${className}`}>
      <MapContainer
        center={center}
        zoom={zoom}
        style={{ height: '100%', width: '100%', background: '#0a0d14' }}
        zoomControl
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <HeatmapLayer points={points} options={heatOptions} />
      </MapContainer>
    </div>
  )
}