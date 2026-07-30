const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

// "5s", "12m", "3h", "Jul 21", "Jul 21, 2024"
export function timeAgo(dateStr) {
  const date = new Date(dateStr);
  const secs = Math.floor((Date.now() - date.getTime()) / 1000);
  if (secs < 5) return "now";
  if (secs < 60) return `${secs}s`;
  if (secs < 3600) return `${Math.floor(secs / 60)}m`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h`;
  const sameYear = date.getFullYear() === new Date().getFullYear();
  const md = `${MONTHS[date.getMonth()]} ${date.getDate()}`;
  return sameYear ? md : `${md}, ${date.getFullYear()}`;
}

// Full timestamp for tweet detail: "2:31 PM · Jul 21, 2026"
export function fullTime(dateStr) {
  const d = new Date(dateStr);
  let h = d.getHours();
  const ampm = h >= 12 ? "PM" : "AM";
  h = h % 12 || 12;
  const min = String(d.getMinutes()).padStart(2, "0");
  return `${h}:${min} ${ampm} · ${MONTHS[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}

// 1234 -> "1,234"; 12345 -> "12.3K"; 1234567 -> "1.2M"
export function compact(n) {
  n = n || 0;
  if (n < 10000) return n.toLocaleString("en-US");
  if (n < 1000000) return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}K`;
  return `${(n / 1000000).toFixed(1).replace(/\.0$/, "")}M`;
}

// "Joined July 2026"
export function joinDate(dateStr) {
  const d = new Date(dateStr);
  const full = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  return `Joined ${full[d.getMonth()]} ${d.getFullYear()}`;
}

export function normalizeExternalUrl(value) {
  if (!value) return null;
  const raw = value.trim();
  if (!raw) return null;
  const withProtocol = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
  try {
    const parsed = new URL(withProtocol);
    if (!["http:", "https:"].includes(parsed.protocol)) return null;
    return parsed.toString();
  } catch {
    return null;
  }
}
