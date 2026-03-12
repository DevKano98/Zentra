import { useState } from 'react'
import { ChevronDown, ChevronUp, Filter, AlertOctagon, ChevronLeft, ChevronRight } from 'lucide-react'

const CATEGORIES = [
  'All', 'KYC Fraud', 'Investment Scam', 'Loan Fraud',
  'Prize/Lottery', 'Impersonation', 'Tech Support', 'Other',
]

const PAGE_SIZE = 20

const urgencyColor = (u) =>
  u >= 9
    ? 'text-rose-400 bg-rose-500/10 border-rose-500/20'
    : u >= 7
    ? 'text-amber-400 bg-amber-500/10 border-amber-500/20'
    : 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20'

/**
 * CallTable — filterable, paginated call log with inline transcript expansion.
 *
 * Props:
 *   calls        Call[]    array of call objects (required)
 *   pageSize     number    rows per page (default: 20)
 */
export default function CallTable({ calls = [], pageSize = PAGE_SIZE }) {
  const [category, setCategory] = useState('All')
  const [scamOnly, setScamOnly] = useState(false)
  const [expandedId, setExpandedId] = useState(null)
  const [page, setPage] = useState(1)

  const filtered = calls
    .filter((c) => category === 'All' || c.category === category)
    .filter((c) => !scamOnly || c.is_scam)

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  const paginated = filtered.slice((page - 1) * pageSize, page * pageSize)

  const handleCatChange = (cat) => { setCategory(cat); setPage(1) }
  const handleScamToggle = () => { setScamOnly((v) => !v); setPage(1) }
  const toggleRow = (id) => setExpandedId((prev) => (prev === id ? null : id))

  return (
    <div className="space-y-4">
      {/* Filter bar */}
      <div className="flex flex-wrap items-center gap-3 bg-[#0d1117] border border-[#1e2535] rounded-xl px-4 py-3">
        <Filter size={14} className="text-[#4a5568] flex-shrink-0" />
        <div className="flex flex-wrap gap-2">
          {CATEGORIES.map((cat) => (
            <button
              key={cat}
              onClick={() => handleCatChange(cat)}
              className={`px-3 py-1 rounded-full text-xs font-medium transition-all
                ${category === cat
                  ? 'bg-sky-500/20 text-sky-400 border border-sky-500/30'
                  : 'text-[#6b7a99] hover:text-[#94a3b8] border border-transparent hover:border-[#1e2535]'
                }`}
            >
              {cat}
            </button>
          ))}
        </div>
        <div className="ml-auto flex items-center gap-3">
          <button
            onClick={handleScamToggle}
            className={`flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium border transition-all
              ${scamOnly
                ? 'bg-rose-500/10 text-rose-400 border-rose-500/20'
                : 'text-[#6b7a99] border-[#1e2535] hover:text-[#94a3b8]'
              }`}
          >
            <AlertOctagon size={13} />
            Scams Only
          </button>
          <span className="text-[#4a5568] text-xs whitespace-nowrap">{filtered.length} results</span>
        </div>
      </div>

      {/* Table */}
      <div className="bg-[#0d1117] border border-[#1e2535] rounded-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-[#1e2535]">
                {['Date & Time', 'Caller', 'Category', 'Urgency', 'Duration', 'Status', ''].map((h) => (
                  <th
                    key={h}
                    className="px-5 py-3 text-left text-[#4a5568] text-xs font-medium uppercase tracking-wider whitespace-nowrap"
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {paginated.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-5 py-10 text-center text-[#4a5568] text-sm">
                    No calls match the current filters.
                  </td>
                </tr>
              ) : (
                paginated.map((row) => (
                  <>
                    <tr
                      key={row.id}
                      className="border-b border-[#111827] hover:bg-[#111827]/50 transition-colors cursor-pointer"
                      onClick={() => toggleRow(row.id)}
                    >
                      <td className="px-5 py-3 text-[#6b7a99] font-mono text-xs whitespace-nowrap">
                        {new Date(row.datetime).toLocaleString('en-IN', {
                          day: '2-digit', month: 'short',
                          hour: '2-digit', minute: '2-digit',
                        })}
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
                        {expandedId === row.id
                          ? <ChevronUp size={14} />
                          : <ChevronDown size={14} />
                        }
                      </td>
                    </tr>

                    {/* Inline transcript */}
                    {expandedId === row.id && (
                      <tr key={`${row.id}-transcript`} className="border-b border-[#1e2535]">
                        <td colSpan={7} className="px-5 py-4 bg-[#090c12]">
                          <div className="rounded-lg border border-[#1e2535] p-4">
                            <p className="text-sky-400 text-xs font-semibold uppercase tracking-wider mb-2">
                              Transcript
                            </p>
                            <pre className="text-[#94a3b8] text-xs font-mono whitespace-pre-wrap leading-relaxed">
                              {row.transcript}
                            </pre>
                          </div>
                        </td>
                      </tr>
                    )}
                  </>
                ))
              )}
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
                  className={`w-7 h-7 rounded-lg text-xs font-medium transition-all
                    ${pg === page
                      ? 'bg-sky-500/20 text-sky-400 border border-sky-500/30'
                      : 'text-[#6b7a99] hover:text-white border border-transparent hover:border-[#1e2535]'
                    }`}
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