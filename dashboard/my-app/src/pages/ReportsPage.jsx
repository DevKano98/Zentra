import { useEffect, useState } from 'react'
import { getReports } from '../services/api'
import { FileText, ExternalLink, Link2, Shield, Calendar, Hash } from 'lucide-react'

const MOCK_REPORTS = Array.from({ length: 12 }, (_, i) => ({
  id: i + 1,
  fir_number: `FIR-2024-${String(1000 + i).padStart(5, '0')}`,
  title: ['KYC Fraud via Fake HDFC Link', 'Investment Scam - Fake Trading App', 'Loan Fraud - Instant Loan Promise', 'Prize Lottery Scam', 'Impersonation of TRAI Official', 'Tech Support Scam'][i % 6],
  category: ['KYC Fraud', 'Investment Scam', 'Loan Fraud', 'Prize/Lottery', 'Impersonation', 'Tech Support'][i % 6],
  filed_date: new Date(Date.now() - i * 4 * 86400000).toISOString(),
  tx_hash: `0x${Math.random().toString(16).slice(2)}${Math.random().toString(16).slice(2)}`,
  pdf_url: `https://storage.example.com/firs/report-${i + 1}.pdf`,
  victim_count: Math.floor(Math.random() * 50) + 1,
  status: ['Verified', 'Pending', 'Verified', 'Under Review'][i % 4],
}))

const STATUS_COLORS = {
  'Verified': 'text-emerald-400 bg-emerald-500/10 border-emerald-500/20',
  'Pending': 'text-amber-400 bg-amber-500/10 border-amber-500/20',
  'Under Review': 'text-sky-400 bg-sky-500/10 border-sky-500/20',
}

const CATEGORY_ICONS = {
  'KYC Fraud': '🪪',
  'Investment Scam': '📈',
  'Loan Fraud': '💳',
  'Prize/Lottery': '🎰',
  'Impersonation': '🎭',
  'Tech Support': '💻',
}

export default function ReportsPage() {
  const [reports, setReports] = useState(MOCK_REPORTS)

  useEffect(() => {
    getReports().then((res) => { if (res.data?.reports) setReports(res.data.reports) }).catch(() => {})
  }, [])

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-white text-2xl font-bold tracking-tight" style={{ fontFamily: "'DM Sans', sans-serif" }}>FIR Reports</h1>
          <p className="text-[#4a5568] text-sm mt-0.5">Filed Incident Reports with blockchain verification</p>
        </div>
        <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-[#111827] border border-[#1e2535] text-xs text-[#6b7a99]">
          <Shield size={14} className="text-emerald-400" />
          {reports.filter((r) => r.status === 'Verified').length} Verified
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {reports.map((report) => (
          <div
            key={report.id}
            className="bg-[#0d1117] border border-[#1e2535] rounded-xl p-5 hover:border-sky-500/20 transition-all group"
          >
            {/* Header */}
            <div className="flex items-start justify-between mb-3">
              <div className="flex items-center gap-2">
                <span className="text-xl">{CATEGORY_ICONS[report.category] || '📋'}</span>
                <span className={`px-2 py-0.5 rounded-full text-xs font-medium border ${STATUS_COLORS[report.status] || STATUS_COLORS['Pending']}`}>
                  {report.status}
                </span>
              </div>
              <span className="text-[#4a5568] text-xs font-mono">{report.fir_number}</span>
            </div>

            {/* Title */}
            <h3 className="text-white text-sm font-semibold mb-3 leading-snug group-hover:text-sky-300 transition-colors">
              {report.title}
            </h3>

            {/* Meta */}
            <div className="space-y-1.5 mb-4">
              <div className="flex items-center gap-2 text-xs text-[#6b7a99]">
                <Calendar size={11} />
                <span>{new Date(report.filed_date).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
                <span className="text-[#2a3548]">·</span>
                <span>{report.victim_count} victim{report.victim_count !== 1 ? 's' : ''}</span>
              </div>
              <div className="flex items-center gap-2 text-xs text-[#4a5568]">
                <Hash size={11} />
                <span className="font-mono truncate">{report.tx_hash.slice(0, 20)}…</span>
              </div>
            </div>

            {/* Actions */}
            <div className="flex gap-2">
              <a
                href={report.pdf_url}
                target="_blank"
                rel="noopener noreferrer"
                className="flex-1 flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-sky-500/10 border border-sky-500/20 text-sky-400 text-xs font-medium hover:bg-sky-500/20 transition-colors"
                onClick={(e) => e.stopPropagation()}
              >
                <FileText size={12} />
                View PDF
                <ExternalLink size={10} />
              </a>
              <a
                href={`https://amoy.polygonscan.com/tx/${report.tx_hash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="flex-1 flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg bg-violet-500/10 border border-violet-500/20 text-violet-400 text-xs font-medium hover:bg-violet-500/20 transition-colors"
                onClick={(e) => e.stopPropagation()}
              >
                <Link2 size={12} />
                Verify Chain
                <ExternalLink size={10} />
              </a>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}