import { useState } from 'react'
import { ChevronDown, ChevronRight, Brain } from 'lucide-react'

interface ThinkingBlockProps {
  content: string
}

export function ThinkingBlock({ content }: ThinkingBlockProps) {
  const [isExpanded, setIsExpanded] = useState(false)

  return (
    <div className="my-2 border border-purple-200 dark:border-purple-800 rounded-lg overflow-hidden bg-purple-50/50 dark:bg-purple-950">
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full flex items-center gap-2 px-3 py-2 text-sm font-medium text-purple-700 dark:text-purple-300 hover:bg-purple-100/50 dark:hover:bg-purple-900/30 transition-colors"
      >
        {isExpanded ? (
          <ChevronDown className="w-4 h-4" />
        ) : (
          <ChevronRight className="w-4 h-4" />
        )}
        <Brain className="w-4 h-4" />
        <span>Thinking...</span>
      </button>

      {isExpanded && (
        <div className="px-3 py-2 text-sm text-purple-900/80 dark:text-purple-100/80 bg-purple-50/30 dark:bg-purple-950/10 border-t border-purple-200 dark:border-purple-800">
          <pre className="whitespace-pre-wrap font-mono text-xs leading-relaxed">
            {content}
          </pre>
        </div>
      )}
    </div>
  )
}
