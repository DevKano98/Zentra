import { TrendingUp, TrendingDown, Minus } from 'lucide-react'

export default function StatCard({ icon: Icon, title, value, trend, trendLabel, color = 'sky' }) {
  const colorMap = {
    sky: { bg: 'bg-sky-500/10', border: 'border-sky-500/20', icon: 'text-sky-400', glow: 'shadow-sky-500/10' },
    emerald: { bg: 'bg-emerald-500/10', border: 'border-emerald-500/20', icon: 'text-emerald-400', glow: 'shadow-emerald-500/10' },
    violet: { bg: 'bg-violet-500/10', border: 'border-violet-500/20', icon: 'text-violet-400', glow: 'shadow-violet-500/10' },
    rose: { bg: 'bg-rose-500/10', border: 'border-rose-500/20', icon: 'text-rose-400', glow: 'shadow-rose-500/10' },
    amber: { bg: 'bg-amber-500/10', border: 'border-amber-500/20', icon: 'text-amber-400', glow: 'shadow-amber-500/10' },
  }
  const c = colorMap[color] || colorMap.sky

  const TrendIcon = trend > 0 ? TrendingUp : trend < 0 ? TrendingDown : Minus
  const trendColor = trend > 0 ? 'text-emerald-400' : trend < 0 ? 'text-rose-400' : 'text-slate-400'

  return (
    <div className={`relative bg-[#0d1117] border ${c.border} rounded-xl p-5 shadow-lg ${c.glow} overflow-hidden`}>
      {/* Background glow */}
      <div className={`absolute top-0 right-0 w-32 h-32 ${c.bg} rounded-full blur-3xl -translate-y-1/2 translate-x-1/2`} />

      <div className="relative">
        <div className="flex items-center justify-between mb-3">
          <div className={`w-9 h-9 rounded-lg ${c.bg} border ${c.border} flex items-center justify-center`}>
            <Icon size={18} className={c.icon} />
          </div>
          {trend !== undefined && (
            <div className={`flex items-center gap-1 text-xs font-medium ${trendColor}`}>
              <TrendIcon size={13} />
              <span>{Math.abs(trend)}%</span>
            </div>
          )}
        </div>

        <div className="mt-2">
          <p className="text-[#6b7a99] text-xs font-medium uppercase tracking-wider mb-1">{title}</p>
          <p className="text-white text-2xl font-bold tracking-tight" style={{ fontFamily: "'DM Sans', sans-serif" }}>
            {value ?? '—'}
          </p>
          {trendLabel && (
            <p className="text-[#4a5568] text-xs mt-1">{trendLabel}</p>
          )}
        </div>
      </div>
    </div>
  )
}