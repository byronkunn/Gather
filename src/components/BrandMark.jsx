export default function BrandMark({ size = 28, withWord = false, className = '' }) {
  return (
    <span className={`brand-mark ${className}`.trim()}>
      <svg viewBox="0 0 256 256" width={size} height={size} aria-hidden="true">
        <defs>
          <linearGradient id="gatherBrandGradient" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#19a1f5" />
            <stop offset="100%" stopColor="#0b79bf" />
          </linearGradient>
        </defs>
        <rect x="16" y="16" width="224" height="224" rx="56" fill="currentColor" />
        <circle cx="128" cy="128" r="88" fill="url(#gatherBrandGradient)" opacity="0.18" />
        <path d="M170 92c-9-18-26-28-48-28-33 0-58 25-58 64s25 64 58 64c23 0 40-10 50-28l-23-13c-6 10-16 16-28 16-19 0-33-15-33-39s14-39 33-39c12 0 22 6 28 16h-32v23h53V92z" fill="url(#gatherBrandGradient)" />
        <circle cx="80" cy="62" r="10" fill="#5dd8ff" />
        <circle cx="186" cy="54" r="8" fill="#5dd8ff" />
        <circle cx="206" cy="134" r="9" fill="#5dd8ff" />
        <line x1="89" y1="69" x2="177" y2="56" stroke="#5dd8ff" strokeWidth="5" strokeLinecap="round" opacity="0.8" />
        <line x1="194" y1="61" x2="201" y2="125" stroke="#5dd8ff" strokeWidth="5" strokeLinecap="round" opacity="0.8" />
      </svg>
      {withWord && <span className="brand-word">Gather</span>}
    </span>
  )
}
