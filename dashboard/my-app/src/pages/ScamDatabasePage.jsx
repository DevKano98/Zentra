import { useEffect, useState } from 'react'
import { getScamDatabase } from '../services/api'
import { Database, TrendingUp } from 'lucide-react'

const MOCK_DB = Array.from({ length: 42 }, (_, i) => ({
  id: i + 1,
  hash: `${['a3f', 'b7c', 'c9d', 'd2e', 'e5f', 'f8a'][i % 6]}${Math.random().toString(16).slice(2, 8)}`,
  report_count: Math.floor(Math.random() * 500) + 10,
  category: ['KYC Fraud', 'Investment Scam', 'Loan Fraud', 'Prize/Lottery', 'Impersonation'][i % 5],
  first_reported: new Date(Date.now() - Math.random() * 30 * 86400000).toISOString(),
})).sort((a, b) => b.report_count - a.report_count)

const CATEGORY_COLORS = {
  'KYC Fraud': 'text-sky-400 bg-sky-500/10 border-sky-500/20',
  'Investment Scam': 'text-violet-400 bg-violet-500/10 border-violet-500/20',
  'Loan Fraud': 'text-orange-400 bg-orange-500/10 border-orange-500/20',
  'Prize/Lottery': 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20',
  'Impersonation': 'text-pink-400 bg-pink-500/10 border-pink-500/20',
}

export default function ScamDatabasePage() {
  const [entries, setEntries] = useState(MOCK_DB)

  useEffect(() => {
    getScamDatabase().then((res) => { if (res.data?.entries) setEntries(res.data.entries) }).catch(() => {})
  }, [])

  const maxCount = entries[0]?.report_count || 1

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-white text-2xl font-bold tracking-tight" style={{ fontFamily: "'DM Sans', sans-serif" }}>Scam Database</h1>
          <p className="text-[#4a5568] text-sm mt-0.5">Known scam fingerprints ranked by report frequency</p>
        </div>
        <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-[#111827] border border-[#1e2535] text-xs text-[#6b7a99]">
          <Database size={14} className="text-sky-400" />
          {entries.length} entries
        </div>
      </div>

      <div className="bg-[#0d1117] border border-[#1e2535] rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2535]">
                <th className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider">Rank</th>
                <th className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider">Hash</th>
                <th className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider">Reports</th>
                <th className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider">Category</th>
                <th className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider">First Reported</th>
              </tr>
            </thead>
            <tbody>
              {entries.map((row, i) => (
                <tr key={row.id} className="border-b border-[#111827] hover:bg-[#111827]/50 transition-colors">
                  <td className="px-5 py-3">
                    <span className={`text-xs font-bold ${i < 3 ? 'text-amber-400' : 'text-[#4a5568]'}`}>
                      #{i + 1}
                    </span>
                  </td>
                  <td className="px-5 py-3">
                    <span className="font-mono text-xs text-sky-400 bg-sky-500/5 border border-sky-500/10 px-2 py-0.5 rounded">
                      {row.hash.slice(0, 8).toUpperCase()}
                    </span>
                  </td>
                  <td className="px-5 py-3">
                    <div className="flex items-center gap-3">
                      <div className="flex-1 bg-[#111827] rounded-full h-1.5 w-24">
                        <div
                          className="h-1.5 rounded-full bg-gradient-to-r from-sky-500 to-indigo-500"
                          style={{ width: `${(row.report_count / maxCount) * 100}%` }}
                        />
                      </div>
                      <span className="text-white text-xs font-semibold min-w-[2rem]">{row.report_count}</span>
                      {i < 5 && <TrendingUp size={12} className="text-rose-400" />}
                    </div>
                  </td>
                  <td className="px-5 py-3">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium border ${CATEGORY_COLORS[row.category] || 'text-slate-400 bg-slate-500/10 border-slate-500/20'}`}>
                      {row.category}
                    </span>
                  </td>
                  <td className="px-5 py-3 text-[#6b7a99] text-xs font-mono">
                    {new Date(row.first_reported).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}