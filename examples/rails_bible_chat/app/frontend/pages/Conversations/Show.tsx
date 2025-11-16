import { useState, useRef, useEffect } from 'react'
import { Link, router } from '@inertiajs/react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { ArrowLeft, Send, Loader2 } from 'lucide-react'
import { BibleVerse } from '@/components/BibleVerse'
import { ThinkingBlock } from '@/components/ThinkingBlock'
import { v4} from 'uuid'
interface Message {
  id: number
  role: string
  content: string
  tool_name?: string
  tool_calls?: any
  tool_result?: any
  tool_use_id?: string
  status?: string
  created_at: string
}

interface Conversation {
  id: number
  agent_class: string
  status: string
  created_at: string
}

interface Props {
  conversation: Conversation
  messages: Message[]
}

// Helper function to parse content and extract thinking blocks
function parseMessageContent(content: string): Array<{ type: 'text' | 'thinking', content: string }> {
  const parts: Array<{ type: 'text' | 'thinking', content: string }> = []
  const thinkingRegex = /<thinking>([\s\S]*?)<\/thinking>/g
  let lastIndex = 0
  let match

  while ((match = thinkingRegex.exec(content)) !== null) {
    // Add text before thinking block
    if (match.index > lastIndex) {
      const textContent = content.slice(lastIndex, match.index).trim()
      if (textContent) {
        parts.push({ type: 'text', content: textContent })
      }
    }
    // Add thinking block
    parts.push({ type: 'thinking', content: match[1].trim() })
    lastIndex = match.index + match[0].length
  }

  // Add remaining text
  if (lastIndex < content.length) {
    const textContent = content.slice(lastIndex).trim()
    if (textContent) {
      parts.push({ type: 'text', content: textContent })
    }
  }

  // If no thinking blocks found, return the whole content as text
  if (parts.length === 0) {
    parts.push({ type: 'text', content })
  }

  return parts
}

// Helper function to render message content based on tool type
function renderMessageContent(message: Message) {
  // Frontend tool with completed status - show result
  if (message.role === 'tool' && message.status === 'completed' && message.tool_name === 'show_emoji') {
    try {
      const result = message.tool_result || JSON.parse(message.content || '{}')
      return (
        <div className="text-xs text-muted-foreground">
          ✓ {message.tool_name} executed: {result.emoji_displayed || result.message}
        </div>
      )
    } catch (e) {
      return <div className="text-xs text-muted-foreground">✓ {message.tool_name} executed</div>
    }
  }

  // Bible lookup tool - render with BibleVerse component
  if (message.tool_name === 'bible_lookup') {
    try {
      // Try to parse from content or tool_result
      const dataStr = message.content || (message.tool_result ? JSON.stringify(message.tool_result) : null)
      if (!dataStr) {
        return <div className="text-sm text-muted-foreground">No scripture data available</div>
      }

      const data = typeof dataStr === 'string' ? JSON.parse(dataStr) : dataStr
      if (data.data) {
        return <BibleVerse data={data.data} />
      } else {
        return <BibleVerse data={data} />
      }

    } catch (e) {
      // Fallback if parsing fails
      return <div className="whitespace-pre-wrap break-words text-sm">{message.content}</div>
    }
  }

  // Other tools - show with tool header
  if (message.tool_name) {
    return (
      <div>
        <div className="text-xs font-semibold mb-2 opacity-70">
          🔧 Tool: {message.tool_name}
        </div>
        <div className="whitespace-pre-wrap break-words text-sm">{message.content}</div>
      </div>
    )
  }

  // Regular assistant message - parse for thinking blocks
  const parts = parseMessageContent(message.content || '')
  return (
    <div className="space-y-2">
      {parts.map((part, index) => {
        if (part.type === 'thinking') {
          return <ThinkingBlock key={index} content={part.content} />
        } else {
          return (
            <div key={index} className="whitespace-pre-wrap break-words">
              {part.content}
            </div>
          )
        }
      })}
    </div>
  )
}

export default function Show({ conversation, messages: initialMessages }: Props) {
  const [messages, setMessages] = useState<Message[]>(initialMessages)
  const [input, setInput] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)

  // Get pending tools from messages
  const pendingTools = messages.filter(m => m.status === 'pending' && m.tool_use_id)

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [messages])

  // Execute frontend tools and send results back
  const executeFrontendTool = async (toolMessage: Message) => {
    let result: any

    // Parse tool input from content
    let toolInput: any = {}
    try {
      toolInput = toolMessage.content ? JSON.parse(toolMessage.content) : {}
    } catch (e) {
      toolInput = {}
    }

    switch (toolMessage.tool_name) {
      case 'show_emoji':
        // Display emoji as requested
        const emoji = toolInput.emoji || '✨'
        result = {
          success: true,
          emoji_displayed: emoji,
          message: `Displayed emoji: ${emoji}`
        }
        // The emoji is already shown in the UI, no need for alert
        break

      default:
        result = {
          error: true,
          message: `Unknown frontend tool: ${toolMessage.tool_name}`
        }
    }

    return result
  }

  const sendToolResults = async (toolResults: Array<{ tool_use_id: string, result: any, message_id?: string }>) => {
    try {
      setIsLoading(true)

      const response = await fetch(
        `/conversations/${conversation.id}/send_message_streaming`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
          },
          body: JSON.stringify({ tool_results: toolResults })
        }
      )

      if (!response.body) throw new Error('No response body')

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() || ''

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6)

            // All events are now JSON
            try {
              const parsed = JSON.parse(data)

              if (parsed.type === 'done') {
                // Stream complete
                setIsLoading(false)
                return
              } else if (parsed.type === 'content_delta') {
                // Text chunk from LLM - update or create last message
                setMessages(prev => {
                  const last = prev[prev.length - 1]
                  // Check if we're continuing to stream into the last message
                  if (last?.role === 'assistant' && !last.tool_name && last.id === -1) {
                    // Update the existing streaming message
                    const updated = [...prev]
                    updated[updated.length - 1] = {
                      ...last,
                      content: last.content + (parsed.delta || '')
                    }
                    return updated
                  } else {
                    // Start a new streaming message
                    return [...prev, {
                      id: -1,
                      role: 'assistant',
                      content: parsed.delta || '',
                      created_at: new Date().toISOString()
                    }]
                  }
                })
              } else if (parsed.type === 'tool_result') {
                // Backend tool executed - add to messages
                const content = parsed.content ||
                               JSON.stringify(parsed.result || parsed.tool_result || parsed, null, 2)

                const toolResultMessage: Message = {
                  id: Date.now() + Math.random(),
                  role: 'assistant',
                  content: content,
                  tool_name: parsed.tool_name,
                  tool_result: parsed.tool_result || parsed.result,
                  created_at: new Date().toISOString(),
                }
                setMessages(prev => [...prev, toolResultMessage])
              } else if (parsed.type === 'awaiting_tool_results') {
                // Frontend tools need to be executed - add as pending messages
                const pendingToolMessages = (parsed.pending_tools || []).map((tool: any) => ({
                  id: tool.message_id || Date.now() + Math.random(),
                  role: 'tool',
                  tool_name: tool.tool_name,
                  tool_use_id: tool.tool_use_id,
                  content: JSON.stringify(tool.tool_input),
                  status: 'pending',
                  tool_result: null,
                  created_at: new Date().toISOString()
                }))
                setMessages(prev => [...prev, ...pendingToolMessages])
              }
            } catch (e) {
              console.error('Failed to parse JSON event:', e, 'Data:', data)
            }
          }
        }
      }
    } catch (error) {
      console.error('Error sending tool results:', error)
      setIsLoading(false)
    }
  }

  // Execute a specific pending tool
  const handleExecuteTool = async (toolMessage: Message) => {
    const result = await executeFrontendTool(toolMessage)

    // Update the message to be completed with the result
    setMessages(prev => prev.map(m =>
      m.tool_use_id === toolMessage.tool_use_id
        ? { ...m, status: 'completed', tool_result: result, content: JSON.stringify(result) }
        : m
    ))

    const toolResults = [{
      tool_use_id: toolMessage.tool_use_id!,
      result: result,
      message_id: toolMessage.id
    }]

    // Send result and continue conversation
    await sendToolResults(toolResults)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim() || isLoading) return

    const userMessage = input
    setInput('')
    setIsLoading(true)

    // Add user message to messages immediately
    const newUserMessage: Message = {
      id: Date.now(), // Temporary ID
      role: 'user',
      content: userMessage,
      created_at: new Date().toISOString(),
    }
    setMessages(prev => [...prev, newUserMessage])

    try {
      const response = await fetch(
        `/conversations/${conversation.id}/send_message_streaming?message=${encodeURIComponent(userMessage)}`,
        {
          method: 'POST',
          headers: {
            'Accept': 'text/event-stream',
            'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
          },
        }
      )

      if (!response.body) throw new Error('No response body')

      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n')
        buffer = lines.pop() || ''

        for (const line of lines) {
          if (line.startsWith('data: ')) {
            const data = line.slice(6)

            // All events are now JSON
            try {
              const parsed = JSON.parse(data)

              if (parsed.type === 'done') {
                // Stream complete
                setIsLoading(false)
                return
              } else if (parsed.type === 'content_delta') {
                // Text chunk from LLM - update or create last message
                setMessages(prev => {
                  const last = prev[prev.length - 1]
                  // Check if we're continuing to stream into the last message
                  if (last?.role === 'assistant' && !last.tool_name && last.id === -1) {
                    // Update the existing streaming message
                    const updated = [...prev]
                    updated[updated.length - 1] = {
                      ...last,
                      content: last.content + (parsed.delta || '')
                    }
                    return updated
                  } else {
                    // Start a new streaming message
                    return [...prev, {
                      id: -1,
                      role: 'assistant',
                      content: parsed.delta || '',
                      created_at: new Date().toISOString()
                    }]
                  }
                })
              } else if (parsed.type === 'tool_result') {
                // Backend tool executed - add to messages
                const content = parsed.content ||
                               JSON.stringify(parsed.result || parsed.tool_result || parsed, null, 2)

                const toolResultMessage: Message = {
                  id: Date.now() + Math.random(),
                  role: 'assistant',
                  content: content,
                  tool_name: parsed.tool_name,
                  tool_result: parsed.tool_result || parsed.result,
                  created_at: new Date().toISOString(),
                }
                setMessages(prev => [...prev, toolResultMessage])
              } else if (parsed.type === 'awaiting_tool_results') {
                // Frontend tools need to be executed - add as pending messages
                const pendingToolMessages = (parsed.pending_tools || []).map((tool: any) => ({
                  id: tool.message_id || Date.now() + Math.random(),
                  role: 'tool',
                  tool_name: tool.tool_name,
                  tool_use_id: tool.tool_use_id,
                  content: JSON.stringify(tool.tool_input),
                  status: 'pending',
                  tool_result: null,
                  created_at: new Date().toISOString()
                }))
                setMessages(prev => [...prev, ...pendingToolMessages])
                setIsLoading(false) // Will be re-enabled when tools execute
              }
            } catch (e) {
              console.error('Failed to parse JSON event:', e, 'Data:', data)
            }
          }
        }
      }
    } catch (error) {
      console.error('Error sending message:', error)
      setIsLoading(false)
    }
  }

  // Filter out pending tool messages from main display (they're shown separately)
  const displayMessages = messages.filter(m => !(m.status === 'pending' && m.tool_use_id))

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="bg-primary text-primary-foreground border-b">
        <div className="container mx-auto px-4 py-4 flex items-center gap-4">
          <Link href="/conversations">
            <Button variant="ghost" size="icon" className="text-primary-foreground hover:bg-primary/90">
              <ArrowLeft className="w-5 h-5" />
            </Button>
          </Link>
          <div>
            <h1 className="text-xl font-semibold">Bible Study Chat</h1>
            <p className="text-sm opacity-90">Conversation #{conversation.id}</p>
          </div>
        </div>
      </header>

      <div className="flex-1 container mx-auto px-4 py-6 flex flex-col max-w-4xl">
        <Card className="flex-1 flex flex-col overflow-hidden">
          {/* Messages Area */}
          <div className="flex-1 overflow-y-auto p-6 space-y-6">
            {displayMessages.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-center">
                <div className="text-6xl mb-4">📖</div>
                <h2 className="text-2xl font-semibold mb-2">Start a conversation</h2>
                <p className="text-muted-foreground">
                  Ask anything about the Bible, request scripture references, or explore theological concepts
                </p>
              </div>
            ) : (
              displayMessages.map((message, index) => (
                <div
                  key={message.id || `streaming-${index}`}
                  className={`flex gap-3 ${message.role === 'user' ? 'flex-row-reverse' : 'flex-row'}`}
                >
                  <Avatar className="w-8 h-8">
                    <AvatarFallback className={message.role === 'user' ? 'bg-primary text-primary-foreground' : 'bg-muted'}>
                      {message.role === 'user' ? 'U' : 'AI'}
                    </AvatarFallback>
                  </Avatar>
                  <div className={`flex-1 ${message.role === 'user' ? 'flex justify-end' : ''}`}>
                    {message.role === 'user' ? (
                      <div className="inline-block rounded-lg px-4 py-2 max-w-[80%] bg-primary text-primary-foreground">
                        <div className="whitespace-pre-wrap break-words">{message.content}</div>
                      </div>
                    ) : (
                      <div className={`${message.tool_name === 'bible_lookup' ? 'max-w-full' : 'inline-block rounded-lg px-4 py-2 max-w-[80%]'} ${message.role === 'tool' && message.status === 'completed' ? 'bg-transparent' : 'bg-muted'}`}>
                        {renderMessageContent(message)}
                      </div>
                    )}
                  </div>
                </div>
              ))
            )}
            {/* Pending Tools - Clickable */}
            {pendingTools.length > 0 && (
              <div className="flex gap-3">
                <Avatar className="w-8 h-8">
                  <AvatarFallback className="bg-muted">AI</AvatarFallback>
                </Avatar>
                <div className="flex-1">
                  <div className="space-y-2">
                    <div className="text-xs font-semibold text-muted-foreground mb-2">
                      🔧 Click to execute frontend tools:
                    </div>
                    {pendingTools.map((tool) => {
                      // Parse tool input from content
                      let toolInput: any = {}
                      try {
                        toolInput = tool.content ? JSON.parse(tool.content) : {}
                      } catch (e) {
                        toolInput = {}
                      }

                      return (
                        <button
                          key={tool.tool_use_id}
                          onClick={() => handleExecuteTool(tool)}
                          className="w-full text-left rounded-lg px-4 py-3 bg-blue-50 dark:bg-blue-950/30 border-2 border-blue-200 dark:border-blue-800 hover:bg-blue-100 dark:hover:bg-blue-900/40 hover:border-blue-300 dark:hover:border-blue-700 transition-colors"
                        >
                          <div className="flex items-center gap-2">
                            <span className="text-lg">🔧</span>
                            <div className="flex-1">
                              <div className="font-semibold text-sm text-blue-900 dark:text-blue-100">
                                {tool.tool_name}
                              </div>
                              <div className="text-xs text-blue-700 dark:text-blue-300 mt-1">
                                {tool.tool_name === 'show_emoji' && toolInput?.emoji && (
                                  <span className="text-2xl">{toolInput.emoji}</span>
                                )}
                                {tool.tool_name !== 'show_emoji' && (
                                  <span className="font-mono">{JSON.stringify(toolInput)}</span>
                                )}
                              </div>
                            </div>
                            <span className="text-blue-600 dark:text-blue-400 text-sm">Click to run →</span>
                          </div>
                        </button>
                      )
                    })}
                  </div>
                </div>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>

          {/* Input Area */}
          <div className="border-t bg-muted/50 p-4">
            <form onSubmit={handleSubmit} className="flex gap-2">
              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Ask about the Bible..."
                disabled={isLoading}
                className="flex-1 px-4 py-2 rounded-md border border-input bg-background focus:outline-none focus:ring-2 focus:ring-ring disabled:opacity-50"
              />
              <Button type="submit" disabled={isLoading || !input.trim()} size="icon">
                {isLoading ? (
                  <Loader2 className="w-4 h-4 animate-spin" />
                ) : (
                  <Send className="w-4 h-4" />
                )}
              </Button>
            </form>
          </div>
        </Card>
      </div>
    </div>
  )
}
