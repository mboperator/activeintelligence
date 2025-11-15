import { useState, useRef, useEffect } from 'react'
import { Link, router } from '@inertiajs/react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { ArrowLeft, Send, Loader2 } from 'lucide-react'

interface Message {
  id: number
  role: string
  content: string
  tool_name?: string
  tool_calls?: any
  tool_result?: any
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

export default function Show({ conversation, messages: initialMessages }: Props) {
  const [messages, setMessages] = useState<Message[]>(initialMessages)
  const [input, setInput] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [streamingContent, setStreamingContent] = useState('')
  const messagesEndRef = useRef<HTMLDivElement>(null)

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [messages, streamingContent])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!input.trim() || isLoading) return

    const userMessage = input
    setInput('')
    setIsLoading(true)
    setStreamingContent('')

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

            if (data === '[DONE]') {
              // Reload the page to get updated messages
              router.reload({ only: ['messages'] })
              setStreamingContent('')
              setIsLoading(false)
              return
            }

            try {
              const parsed = JSON.parse(data)

              if (parsed.type === 'message') {
                setStreamingContent(prev => prev + (parsed.content || ''))
              } else if (parsed.type === 'tool_result') {
                // Tool result handled, continue streaming
              } else if (parsed.type === 'frontend_tool_request') {
                // Handle frontend tool request if needed
                console.log('Frontend tool requested:', parsed)
              }
            } catch (e) {
              // Skip invalid JSON
            }
          }
        }
      }
    } catch (error) {
      console.error('Error sending message:', error)
      setIsLoading(false)
      setStreamingContent('')
    }
  }

  const displayMessages = [...messages]
  if (streamingContent) {
    displayMessages.push({
      id: -1,
      role: 'assistant',
      content: streamingContent,
      created_at: new Date().toISOString(),
    })
  }

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
                    <div
                      className={`inline-block rounded-lg px-4 py-2 max-w-[80%] ${
                        message.role === 'user'
                          ? 'bg-primary text-primary-foreground'
                          : 'bg-muted'
                      }`}
                    >
                      {message.tool_name ? (
                        <div className="text-xs font-semibold mb-1 opacity-70">
                          🔧 Tool: {message.tool_name}
                        </div>
                      ) : null}
                      <div className="whitespace-pre-wrap break-words">{message.content}</div>
                    </div>
                  </div>
                </div>
              ))
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
