import { useEffect, useState } from 'react'
import { getCallLog } from '../services/api'
import CallTable from '../components/CallTable'

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

export default function CallsPage() {
  const [calls, setCalls] = useState(MOCK_CALLS)

  useEffect(() => {
    getCallLog()
      .then((res) => { if (res.data?.calls) setCalls(res.data.calls) })
      .catch(() => {})
  }, [])

  return (
    <div className="space-y-5">
      <div>
        <h1
          className="text-white text-2xl font-bold tracking-tight"
          style={{ fontFamily: "'DM Sans', sans-serif" }}
        >
          Call Log
        </h1>
        <p className="text-[#4a5568] text-sm mt-0.5">Browse and analyze intercepted calls</p>
      </div>

      {/* CallTable owns all filter/pagination/expand state */}
      <CallTable calls={calls} pageSize={20} />
    </div>
  )
}