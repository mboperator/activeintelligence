import { useState, useEffect } from 'react'

interface EmojiExplosionProps {
  emoji: string
  onComplete: () => void
}

export function EmojiExplosion({ emoji, onComplete }: EmojiExplosionProps) {
  const [isVisible, setIsVisible] = useState(true)

  useEffect(() => {
    // Auto-hide after 2 seconds
    const timer = setTimeout(() => {
      setIsVisible(false)
      setTimeout(onComplete, 500) // Wait for fade out animation
    }, 2000)

    return () => clearTimeout(timer)
  }, [onComplete])

  if (!isVisible) return null

  return (
    <div className="fixed inset-0 z-50 pointer-events-none flex items-center justify-center">
      {/* Backdrop blur */}
      <div className="absolute inset-0 bg-black/20 backdrop-blur-sm animate-in fade-in duration-200" />

      {/* Main emoji with bounce and scale animation */}
      <div className="relative animate-in zoom-in-50 spin-in-180 duration-500">
        <div className="text-[200px] animate-bounce">
          {emoji}
        </div>

        {/* Sparkle particles */}
        {[...Array(12)].map((_, i) => {
          const angle = (i * 30) * (Math.PI / 180)
          const distance = 150
          const x = Math.cos(angle) * distance
          const y = Math.sin(angle) * distance

          return (
            <div
              key={i}
              className="absolute top-1/2 left-1/2 w-3 h-3 bg-yellow-400 rounded-full animate-ping"
              style={{
                transform: `translate(-50%, -50%) translate(${x}px, ${y}px)`,
                animationDelay: `${i * 50}ms`,
                animationDuration: '1s'
              }}
            />
          )
        })}

        {/* Additional sparkles */}
        {[...Array(8)].map((_, i) => {
          const angle = (i * 45) * (Math.PI / 180)
          const distance = 100
          const x = Math.cos(angle) * distance
          const y = Math.sin(angle) * distance

          return (
            <div
              key={`star-${i}`}
              className="absolute top-1/2 left-1/2 text-4xl animate-ping"
              style={{
                transform: `translate(-50%, -50%) translate(${x}px, ${y}px)`,
                animationDelay: `${i * 75}ms`,
                animationDuration: '1.2s'
              }}
            >
              ✨
            </div>
          )
        })}
      </div>
    </div>
  )
}
