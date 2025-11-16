import { Card } from '@/components/ui/card'

interface BibleVerseProps {
  data: {
    reference?: string
    version?: string
    text?: string
    verses?: Array<{
      book?: string
      chapter?: number
      verse?: number
      text?: string
    }>
  }
}

export function BibleVerse({ data }: BibleVerseProps) {
  return (
    <Card className="border-2 border-primary/20 bg-gradient-to-br from-amber-50/50 to-stone-50/50 dark:from-amber-950/20 dark:to-stone-950/20 p-6 my-4">
      {/* Reference Header */}
      {data.reference && (
        <div className="flex items-center gap-2 mb-4 pb-3 border-b border-primary/20">
          <span className="text-2xl">📖</span>
          <div>
            <h3 className="font-serif text-lg font-semibold text-primary">
              {data.reference}
            </h3>
            {data.version && (
              <p className="text-sm text-muted-foreground">{data.version}</p>
            )}
          </div>
        </div>
      )}

      {/* Full text if available */}
      {data.text && !data.verses && (
        <div className="font-serif text-base leading-relaxed text-foreground/90 whitespace-pre-wrap">
          {data.text}
        </div>
      )}

      {/* Individual verses */}
      {data.verses && data.verses.length > 0 && (
        <div className="space-y-4">
          {data.verses.map((verse, index) => (
            <div key={index} className="group">
              {/* Verse reference */}
              {(verse.book || verse.chapter || verse.verse) && (
                <div className="text-xs font-medium text-primary/70 mb-1">
                  {verse.book} {verse.chapter}:{verse.verse}
                </div>
              )}
              {/* Verse text */}
              <p className="font-serif text-base leading-relaxed text-foreground/90 pl-3 border-l-2 border-primary/30">
                {verse.text}
              </p>
            </div>
          ))}
        </div>
      )}

      {/* Decorative footer */}
      <div className="mt-4 pt-3 border-t border-primary/10 flex justify-center">
        <div className="w-12 h-0.5 bg-gradient-to-r from-transparent via-primary/30 to-transparent" />
      </div>
    </Card>
  )
}
