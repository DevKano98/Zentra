import { useEffect, useState, useCallback } from 'react'
import { getCallLog } from '../services/api'
import { ChevronDown, ChevronUp, Filter, AlertOctagon, ChevronLeft, ChevronRight } from 'lucide-react'

const CATEGORIES = ['All', 'KYC Fraud', 'Investment Scam', 'Loan Fraud', 'Prize/Lottery', 'Impersonation', 'Tech Support', 'Other']

const MOCK_CALLS = Array.from({ length: 87 }, (_, i) => ({
  id: i + 1,
  datetime: new Date(Date.now() - i * 1800000).toISOString(),
  caller: `+91 XXXXX ${String(10000 + i * 137).slice(-5)}`,
  category: CATEGORIES[1 + (i % 7)],
  urgency: Math.floor(Math.random() * 10) + 1,
  duration: `${Math.floor(Math.random() * 12) + 1}m ${Math.floor(Math.random() * 60)}s`,
  is_scam: Math.random() > 0.3,
  transcript: `[AI Analysis Transcript]\n\nCaller opened with urgency, claiming to be from ${['HDFC Bank', 'SBI', 'UIDAI', 'Income Tax Dept'][i % 4]}. \nKey red flags detected:\n• Requesting OTP/CVV/PIN\n• Threatening account suspension\n• Unusual callback number\n• High-pressure tactics\n\nScam confidence: ${Math.floor(Math.random() * 30) + 70}%\nRecommendation: BLOCK & REPORT`,
}))

const urgencyColor = (u) =>
  u >= 9 ? 'text-rose-400 bg-rose-500/10 border-rose-500/20'
  : u >= 7 ? 'text-amber-400 bg-amber-500/10 border-amber-500/20'
  : 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20'

const PAGE_SIZE = 20

export default function CallsPage() {
  const [calls, setCalls] = useState(MOCK_CALLS)
  const [category, setCategory] = useState('All')
  const [scamOnly, setScamOnly] = useState(false)
  const [expandedId, setExpandedId] = useState(null)
  const [page, setPage] = useState(1)

  useEffect(() => {
    getCallLog().then((res) => { if (res.data?.calls) setCalls(res.data.calls) }).catch(() => {})
  }, [])

  const filtered = calls
    .filter((c) => category === 'All' || c.category === category)
    .filter((c) => !scamOnly || c.is_scam)

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE)
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE)

  const handleCatChange = (cat) => { setCategory(cat); setPage(1) }
  const handleScamToggle = () => { setScamOnly((v) => !v); setPage(1) }

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-white text-2xl font-bold tracking-tight" style={{ fontFamily: "'DM Sans', sans-serif" }}>Call Log</h1>
        <p className="text-[#4a5568] text-sm mt-0.5">Browse and analyze intercepted calls</p>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3 bg-[#0d1117] border border-[#1e2535] rounded-xl px-4 py-3">
        <Filter size={14} className="text-[#4a5568]" />
        <div className="flex flex-wrap gap-2">
          {CATEGORIES.map((cat) => (
            <button
              key={cat}
              onClick={() => handleCatChange(cat)}
              className={`px-3 py-1 rounded-full text-xs font-medium transition-all ${category === cat ? 'bg-sky-500/20 text-sky-400 border border-sky-500/30' : 'text-[#6b7a99] hover:text-[#94a3b8] border border-transparent hover:border-[#1e2535]'}`}
            >
              {cat}
            </button>
          ))}
        </div>
        <div className="ml-auto flex items-center gap-2">
          <button
            onClick={handleScamToggle}
            className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium border transition-all ${scamOnly ? 'bg-rose-500/10 text-rose-400 border-rose-500/20' : 'text-[#6b7a99] border-[#1e2535] hover:text-[#94a3b8]'}`}
          >
            <AlertOctagon size={13} />
            Scams Only
          </button>
          <span className="text-[#4a5568] text-xs">{filtered.length} results</span>
        </div>
      </div>

      {/* Table */}
      <div className="bg-[#0d1117] border border-[#1e2535] rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2535]">
                {['Date & Time', 'Caller', 'Category', 'Urgency', 'Duration', 'Status', ''].map((h) => (
                  <th key={h} className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider whitespace-nowrap">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {paginated.map((row) => (
                <>
                  <tr
                    key={row.id}
                    className="border-b border-[#111827] hover:bg-[#111827]/50 transition-colors cursor-pointer"
                    onClick={() => setExpandedId(expandedId === row.id ? null : row.id)}
                  >
                    <td className="px-5 py-3 text-[#6b7a99] font-mono text-xs whitespace-nowrap">
                      {new Date(row.datetime).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                    </td>
                    <td className="px-5 py-3 text-[#94a3b8] font-mono text-xs">{row.caller}</td>
                    <td className="px-5 py-3">
                      <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-sky-500/10 text-sky-400 border border-sky-500/20 whitespace-nowrap">
                        {row.category}
                      </span>
                    </td>
                    <td className="px-5 py-3">
                      <span className={`px-2 py-0.5 rounded-full text-xs font-bold border ${urgencyColor(row.urgency)}`}>
                        {row.urgency}/10
                      </span>
                    </td>
                    <td className="px-5 py-3 text-[#6b7a99] text-xs">{row.duration}</td>
                    <td className="px-5 py-3">
                      {row.is_scam
                        ? <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-rose-500/10 text-rose-400 border border-rose-500/20">SCAM</span>
                        : <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">CLEAN</span>
                      }
                    </td>
                    <td className="px-5 py-3 text-[#4a5568]">
                      {expandedId === row.id ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                    </td>
                  </tr>
                  {expandedId === row.id && (
                    <tr key={`${row.id}-expand`} className="border-b border-[#1e2535]">
                      <td colSpan={7} className="px-5 py-4 bg-[#090c12]">
                        <div className="rounded-lg border border-[#1e2535] p-4">
                          <p className="text-sky-400 text-xs font-semibold uppercase tracking-wider mb-2">Transcript</p>
                          <pre className="text-[#94a3b8] text-xs font-mono whitespace-pre-wrap leading-relaxed">{row.transcript}</pre>
                        </div>
                      </td>
                    </tr>
                  )}
                </>
              ))}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        <div className="flex items-center justify-between px-5 py-3 border-t border-[#1e2535]">
          <span className="text-[#4a5568] text-xs">
            Page {page} of {totalPages} · {filtered.length} total
          </span>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1}
              className="p-1.5 rounded-lg border border-[#1e2535] text-[#6b7a99] hover:text-white hover:border-sky-500/30 disabled:opacity-30 transition-all"
            >
              <ChevronLeft size={14} />
            </button>
            {Array.from({ length: Math.min(5, totalPages) }, (_, i) => {
              const pg = page <= 3 ? i + 1 : page + i - 2
              if (pg > totalPages) return null
              return (
                <button
                  key={pg}
                  onClick={() => setPage(pg)}
                  className={`w-7 h-7 rounded-lg text-xs font-medium transition-all ${pg === page ? 'bg-sky-500/20 text-sky-400 border border-sky-500/30' : 'text-[#6b7a99] hover:text-white border border-transparent hover:border-[#1e2535]'}`}
                >
                  {pg}
                </button>
              )
            })}
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page === totalPages}
              className="p-1.5 rounded-lg border border-[#1e2535] text-[#6b7a99] hover:text-white hover:border-sky-500/30 disabled:opacity-30 transition-all"
            >
              <ChevronRight size={14} />
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
