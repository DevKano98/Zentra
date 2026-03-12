import {
  BarChart, Bar, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid,
  Tooltip, Legend, ResponsiveContainer,
} from 'recharts'

export const CATEGORY_COLORS = {
  'KYC Fraud':       '#38bdf8',
  'Investment Scam': '#818cf8',
  'Loan Fraud':      '#fb923c',
  'Prize/Lottery':   '#34d399',
  'Impersonation':   '#f472b6',
  'Tech Support':    '#facc15',
  'Other':           '#94a3b8',
}
export const COLOR_LIST = Object.values(CATEGORY_COLORS)

const BAR_CATEGORIES = ['KYC Fraud', 'Investment Scam', 'Loan Fraud', 'Other']

/** Shared dark tooltip used by both sub-charts */
function DarkTooltip({ active, payload, label }) {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-[#0d1117] border border-[#1e2535] rounded-lg p-3 shadow-xl text-xs">
      {label && <p className="text-[#7dd3fc] font-semibold mb-2">{label}</p>}
      {payload.map((p) => (
        <div key={p.name} className="flex items-center gap-2 mb-1">
          <div className="w-2 h-2 rounded-full" style={{ background: p.fill || p.color }} />
          <span className="text-[#94a3b8]">{p.name}:</span>
          <span className="text-white font-medium">{p.value}</span>
        </div>
      ))}
    </div>
  )
}

/**
 * BarPanel — stacked bar chart of calls per day by category.
 *
 * Props:
 *   data         { date, [category]: number }[]   required
 *   title        string
 *   categories   string[]   which keys to render as bars
 *   height       number     chart height (default: 260)
 */
export function BarPanel({
  data = [],
  title = 'Calls Per Day — Last 7 Days',
  categories = BAR_CATEGORIES,
  height = 260,
}) {
  return (
    <div className="bg-[#0d1117] border border-[#1e2535] rounded-xl p-5">
      <h2 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">{title}</h2>
      <ResponsiveContainer width="100%" height={height}>
        <BarChart data={data} barSize={8} barGap={2}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1e2535" vertical={false} />
          <XAxis
            dataKey="date"
            tick={{ fill: '#6b7a99', fontSize: 11 }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fill: '#6b7a99', fontSize: 11 }}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip content={<DarkTooltip />} cursor={{ fill: 'rgba(56,189,248,0.04)' }} />
          <Legend wrapperStyle={{ paddingTop: '12px', fontSize: '11px', color: '#6b7a99' }} />
          {categories.map((cat, i) => (
            <Bar
              key={cat}
              dataKey={cat}
              stackId="a"
              fill={COLOR_LIST[i % COLOR_LIST.length]}
              radius={i === categories.length - 1 ? [3, 3, 0, 0] : [0, 0, 0, 0]}
            />
          ))}
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

/**
 * PiePanel — donut chart of category distribution with legend.
 *
 * Props:
 *   data         { name: string, value: number }[]   required
 *   title        string
 *   height       number   chart height (default: 180)
 */
export function PiePanel({
  data = [],
  title = 'Category Distribution',
  height = 180,
}) {
  return (
    <div className="bg-[#0d1117] border border-[#1e2535] rounded-xl p-5">
      <h2 className="text-white font-semibold mb-4 text-sm uppercase tracking-wider">{title}</h2>
      <ResponsiveContainer width="100%" height={height}>
        <PieChart>
          <Pie
            data={data}
            cx="50%"
            cy="50%"
            innerRadius={50}
            outerRadius={75}
            paddingAngle={3}
            dataKey="value"
          >
            {data.map((entry, i) => (
              <Cell key={entry.name} fill={COLOR_LIST[i % COLOR_LIST.length]} />
            ))}
          </Pie>
          <Tooltip content={<DarkTooltip />} />
        </PieChart>
      </ResponsiveContainer>

      {/* Manual legend */}
      <div className="space-y-1.5 mt-2">
        {data.map((entry, i) => (
          <div key={entry.name} className="flex items-center justify-between text-xs">
            <div className="flex items-center gap-2">
              <div
                className="w-2 h-2 rounded-full flex-shrink-0"
                style={{ background: COLOR_LIST[i % COLOR_LIST.length] }}
              />
              <span className="text-[#6b7a99]">{entry.name}</span>
            </div>
            <span className="text-[#94a3b8] font-medium">{entry.value}%</span>
          </div>
        ))}
      </div>
    </div>
  )
}

/**
 * CategoryChart — convenience wrapper that renders BarPanel + PiePanel
 * side by side in a responsive grid (2/3 + 1/3).
 *
 * Props:
 *   callsPerDay          data for BarPanel
 *   categoryDistribution data for PiePanel
 *   barCategories        which categories to show in the bar chart
 */
export default function CategoryChart({
  callsPerDay = [],
  categoryDistribution = [],
  barCategories = BAR_CATEGORIES,
}) {
  return (
    <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
      <div className="xl:col-span-2">
        <BarPanel data={callsPerDay} categories={barCategories} />
      </div>
      <PiePanel data={categoryDistribution} />
    </div>
  )
}