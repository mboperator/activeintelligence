import { useState, useEffect, useRef } from 'react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { ChevronDown, ChevronUp, X, Trash2, ChevronRight } from 'lucide-react'

interface HookEvent {
  id: string
  hook: string
  payload: any
  timestamp: string
  chunkCount?: number  // For batched chunks
  chunks?: any[]       // Store individual chunks
}

interface DebugPanelProps {
  conversationId: number
}

export function DebugPanel({ conversationId }: DebugPanelProps) {
  const [isCollapsed, setIsCollapsed] = useState(false)
  const [isVisible, setIsVisible] = useState(true)
  const [events, setEvents] = useState<HookEvent[]>([])
  const [cable, setCable] = useState<any>(null)
  const [expandedChunks, setExpandedChunks] = useState<Set<string>>(new Set())
  const eventsEndRef = useRef<HTMLDivElement>(null)

  const scrollToBottom = () => {
    eventsEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [events])

  useEffect(() => {
    let channel: any = null
    let consumer: any = null

    // Connect to ActionCable
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const wsUrl = `${protocol}//${window.location.host}/cable?conversation_id=${conversationId}`

    // Dynamic import of ActionCable
    import('@rails/actioncable').then((actionCableModule) => {
      const actionCable = actionCableModule.default || actionCableModule
      consumer = actionCable.createConsumer(wsUrl)

      channel = consumer.subscriptions.create(
        { channel: 'DebugChannel', conversation_id: conversationId },
        {
          received: (data: { hook: string; payload: any; timestamp: string }) => {
            // Special handling for on_response_chunk - batch them together
            if (data.hook === 'on_response_chunk') {
              setEvents(prev => {
                const lastEvent = prev[prev.length - 1]

                // If the last event was also a chunk batch, append to it
                if (lastEvent && lastEvent.hook === 'on_response_chunk' && lastEvent.chunkCount !== undefined) {
                  const updated = [...prev]
                  updated[updated.length - 1] = {
                    ...lastEvent,
                    chunkCount: lastEvent.chunkCount + 1,
                    chunks: [...(lastEvent.chunks || []), data.payload],
                    timestamp: data.timestamp // Update to latest timestamp
                  }
                  return updated
                } else {
                  // Start a new chunk batch
                  return [...prev, {
                    id: `${Date.now()}-${Math.random()}`,
                    hook: data.hook,
                    payload: data.payload,
                    timestamp: data.timestamp,
                    chunkCount: 1,
                    chunks: [data.payload]
                  }]
                }
              })
            } else {
              // Regular event - add normally
              const event: HookEvent = {
                id: `${Date.now()}-${Math.random()}`,
                hook: data.hook,
                payload: data.payload,
                timestamp: data.timestamp
              }
              setEvents(prev => [...prev, event])
            }
          }
        }
      )

      setCable(consumer)
    })

    return () => {
      if (channel) channel.unsubscribe()
      if (consumer) consumer.disconnect()
    }
  }, [conversationId])

  const clearEvents = () => {
    setEvents([])
    setExpandedChunks(new Set())
  }

  const toggleChunkExpansion = (eventId: string) => {
    setExpandedChunks(prev => {
      const next = new Set(prev)
      if (next.has(eventId)) {
        next.delete(eventId)
      } else {
        next.add(eventId)
      }
      return next
    })
  }

  if (!isVisible) return null

  // Hook color mapping for visual distinction
  const getHookColor = (hookName: string): string => {
    if (hookName.includes('session')) return 'text-purple-600'
    if (hookName.includes('turn')) return 'text-blue-600'
    if (hookName.includes('response')) return 'text-green-600'
    if (hookName.includes('tool')) return 'text-orange-600'
    if (hookName.includes('thinking')) return 'text-pink-600'
    if (hookName.includes('iteration')) return 'text-yellow-600'
    if (hookName.includes('error')) return 'text-red-600'
    if (hookName.includes('stop')) return 'text-gray-600'
    return 'text-indigo-600'
  }

  return (
    <div className="fixed bottom-4 right-4 z-50 w-96 max-h-[600px] flex flex-col">
      <Card className="shadow-xl border-2 flex flex-col overflow-hidden">
        {/* Header */}
        <div className="bg-slate-900 text-white px-4 py-2 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold">🔍 Observability Hooks</span>
            <span className="text-xs opacity-70">({events.length})</span>
          </div>
          <div className="flex items-center gap-1">
            <Button
              size="sm"
              variant="ghost"
              className="h-6 w-6 p-0 text-white hover:bg-slate-700"
              onClick={clearEvents}
              title="Clear events"
            >
              <Trash2 className="w-3 h-3" />
            </Button>
            <Button
              size="sm"
              variant="ghost"
              className="h-6 w-6 p-0 text-white hover:bg-slate-700"
              onClick={() => setIsCollapsed(!isCollapsed)}
            >
              {isCollapsed ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
            </Button>
            <Button
              size="sm"
              variant="ghost"
              className="h-6 w-6 p-0 text-white hover:bg-slate-700"
              onClick={() => setIsVisible(false)}
            >
              <X className="w-4 h-4" />
            </Button>
          </div>
        </div>

        {/* Events List */}
        {!isCollapsed && (
          <div className="flex-1 overflow-y-auto bg-slate-50 p-3 space-y-2" style={{ maxHeight: '500px' }}>
            {events.length === 0 ? (
              <div className="text-center text-sm text-muted-foreground py-8">
                No events yet. Start a conversation to see hooks firing.
              </div>
            ) : (
              events.map((event) => {
                // Special rendering for batched chunks
                if (event.hook === 'on_response_chunk' && event.chunkCount !== undefined) {
                  const isExpanded = expandedChunks.has(event.id)
                  return (
                    <div
                      key={event.id}
                      className="bg-white rounded-md border border-slate-200 p-2 text-xs font-mono"
                    >
                      <div className="flex items-start justify-between mb-1">
                        <button
                          onClick={() => toggleChunkExpansion(event.id)}
                          className="flex items-center gap-1 font-semibold text-green-600 hover:text-green-700"
                        >
                          <ChevronRight className={`w-3 h-3 transition-transform ${isExpanded ? 'rotate-90' : ''}`} />
                          {event.hook} ({event.chunkCount} chunks)
                        </button>
                        <span className="text-slate-400 text-[10px]">
                          {new Date(event.timestamp).toLocaleTimeString()}
                        </span>
                      </div>
                      {isExpanded && (
                        <div className="mt-2 space-y-1">
                          {event.chunks?.map((chunk, idx) => (
                            <pre key={idx} className="text-[10px] text-slate-600 overflow-x-auto bg-slate-50 p-2 rounded border border-slate-100">
                              {JSON.stringify(chunk, null, 2)}
                            </pre>
                          ))}
                        </div>
                      )}
                      {!isExpanded && (
                        <div className="text-[10px] text-slate-500 italic mt-1">
                          Click to expand {event.chunkCount} chunks
                        </div>
                      )}
                    </div>
                  )
                }

                // Regular event rendering
                return (
                  <div
                    key={event.id}
                    className="bg-white rounded-md border border-slate-200 p-2 text-xs font-mono"
                  >
                    <div className="flex items-start justify-between mb-1">
                      <span className={`font-semibold ${getHookColor(event.hook)}`}>
                        {event.hook}
                      </span>
                      <span className="text-slate-400 text-[10px]">
                        {new Date(event.timestamp).toLocaleTimeString()}
                      </span>
                    </div>
                    <pre className="text-[10px] text-slate-600 overflow-x-auto bg-slate-50 p-2 rounded border border-slate-100">
                      {JSON.stringify(event.payload, null, 2)}
                    </pre>
                  </div>
                )
              })
            )}
            <div ref={eventsEndRef} />
          </div>
        )}
      </Card>

      {/* Show button when panel is hidden */}
      {!isVisible && (
        <Button
          onClick={() => setIsVisible(true)}
          className="fixed bottom-4 right-4 shadow-lg"
          size="sm"
        >
          🔍 Show Debug Panel
        </Button>
      )}
    </div>
  )
}
