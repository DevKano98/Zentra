import { useEffect, useState, useCallback } from 'react'
import { PhoneCall, ShieldOff, Users, AlertTriangle, RefreshCw } from 'lucide-react'
import StatCard from '../components/StatCard'
import CategoryChart from '../components/CategoryChart'
import { getStatistics } from '../services/api'

const urgencyColor = (u) =>
  u >= 9 ? 'text-rose-400 bg-rose-500/10' : u >= 7 ? 'text-amber-400 bg-amber-500/10' : 'text-emerald-400 bg-emerald-500/10'

const MOCK_STATS = {
  total_calls: 14872,
  scams_blocked: 3241,
  users_protected: 8904,
  avg_urgency: 6.4,
  calls_per_day: [
    { date: 'Mon', 'KYC Fraud': 120, 'Investment Scam': 80, 'Loan Fraud': 45, Other: 30 },
    { date: 'Tue', 'KYC Fraud': 98, 'Investment Scam': 110, 'Loan Fraud': 60, Other: 25 },
    { date: 'Wed', 'KYC Fraud': 145, 'Investment Scam': 95, 'Loan Fraud': 38, Other: 42 },
    { date: 'Thu', 'KYC Fraud': 200, 'Investment Scam': 130, 'Loan Fraud': 55, Other: 18 },
    { date: 'Fri', 'KYC Fraud': 178, 'Investment Scam': 88, 'Loan Fraud': 70, Other: 35 },
    { date: 'Sat', 'KYC Fraud': 90, 'Investment Scam': 60, 'Loan Fraud': 30, Other: 20 },
    { date: 'Sun', 'KYC Fraud': 75, 'Investment Scam': 45, 'Loan Fraud': 22, Other: 15 },
  ],
  category_distribution: [
    { name: 'KYC Fraud', value: 38 },
    { name: 'Investment Scam', value: 27 },
    { name: 'Loan Fraud', value: 15 },
    { name: 'Prize/Lottery', value: 10 },
    { name: 'Impersonation', value: 6 },
    { name: 'Other', value: 4 },
  ],
  recent_scams: Array.from({ length: 10 }, (_, i) => ({
    id: i + 1,
    datetime: new Date(Date.now() - i * 3600000).toISOString(),
    caller: `+91 XXXXX ${String(10000 + i * 137).slice(-5)}`,
    category: ['KYC Fraud', 'Investment Scam', 'Loan Fraud', 'Prize/Lottery'][i % 4],
    urgency: Math.floor(Math.random() * 4) + 6,
    duration: `${Math.floor(Math.random() * 8) + 1}m ${Math.floor(Math.random() * 60)}s`,
  })),
}



export default function OverviewPage() {
  const [data, setData] = useState(MOCK_STATS)
  const [loading, setLoading] = useState(false)
  const [lastRefresh, setLastRefresh] = useState(new Date())

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await getStatistics()
      setData(res.data)
    } catch {
      // use mock data
    } finally {
      setLoading(false)
      setLastRefresh(new Date())
    }
  }, [])

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 30000)
    return () => clearInterval(interval)
  }, [fetchData])

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-white text-2xl font-bold tracking-tight" style={{ fontFamily: "'DM Sans', sans-serif" }}>
            Overview
          </h1>
          <p className="text-[#4a5568] text-sm mt-0.5">Real-time scam intelligence dashboard</p>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-[#4a5568] text-xs">
            Updated {lastRefresh.toLocaleTimeString()}
          </span>
          <button
            onClick={fetchData}
            disabled={loading}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-[#111827] border border-[#1e2535] text-[#7dd3fc] text-sm hover:bg-[#1a2234] transition-colors disabled:opacity-50"
          >
            <RefreshCw size={14} className={loading ? 'animate-spin' : ''} />
            Refresh
          </button>
        </div>
      </div>

      {/* Stat Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <StatCard icon={PhoneCall} title="Total Calls" value={data.total_calls?.toLocaleString()} trend={12} trendLabel="vs last week" color="sky" />
        <StatCard icon={ShieldOff} title="Scams Blocked" value={data.scams_blocked?.toLocaleString()} trend={8} trendLabel="vs last week" color="rose" />
        <StatCard icon={Users} title="Users Protected" value={data.users_protected?.toLocaleString()} trend={5} trendLabel="vs last week" color="emerald" />
        <StatCard icon={AlertTriangle} title="Avg Urgency" value={data.avg_urgency?.toFixed(1)} trend={-3} trendLabel="lower is better" color="amber" />
      </div>

      {/* Charts Row — BarPanel + PiePanel via CategoryChart */}
      <CategoryChart
        callsPerDay={data.calls_per_day}
        categoryDistribution={data.category_distribution}
      />

      {/* Recent Scams Table */}
      <div className="bg-[#0d1117] border border-[#1e2535] rounded-xl overflow-hidden">
        <div className="px-5 py-4 border-b border-[#1e2535]">
          <h2 className="text-white font-semibold text-sm uppercase tracking-wider">Recent Scam Calls</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2535]">
                {['Time', 'Caller', 'Category', 'Urgency', 'Duration'].map((h) => (
                  <th key={h} className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {data.recent_scams?.map((row, i) => (
                <tr key={row.id} className={`border-b border-[#111827] hover:bg-[#111827]/50 transition-colors ${i % 2 === 0 ? '' : 'bg-[#0a0d14]/30'}`}>
                  <td className="px-5 py-3 text-[#6b7a99] font-mono text-xs">
                    {new Date(row.datetime).toLocaleTimeString()}
                  </td>
                  <td className="px-5 py-3 text-[#94a3b8] font-mono text-xs">{row.caller}</td>
                  <td className="px-5 py-3">
                    <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-sky-500/10 text-sky-400 border border-sky-500/20">
                      {row.category}
                    </span>
                  </td>
                  <td className="px-5 py-3">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-bold ${urgencyColor(row.urgency)}`}>
                      {row.urgency}/10
                    </span>
                  </td>
                  <td className="px-5 py-3 text-[#6b7a99] text-xs">{row.duration}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}