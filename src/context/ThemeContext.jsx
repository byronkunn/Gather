import { createContext, useContext, useEffect, useState } from 'react'

const ThemeContext = createContext(null)

const THEMES = ['light', 'dim', 'dark'] // dark = "Lights out"

export function ThemeProvider({ children }) {
  const [theme, setTheme] = useState(() => {
    try {
      const saved = window.localStorage.getItem('theme')
      return THEMES.includes(saved) ? saved : 'dim'
    } catch {
      return 'dim'
    }
  })

  useEffect(() => {
    document.documentElement.dataset.theme = theme
    try {
      window.localStorage.setItem('theme', theme)
    } catch { /* ignore */ }
  }, [theme])

  return (
    <ThemeContext.Provider value={{ theme, setTheme, themes: THEMES }}>
      {children}
    </ThemeContext.Provider>
  )
}

export const useTheme = () => useContext(ThemeContext)
