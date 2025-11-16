import { Link } from '@inertiajs/react'
import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card'
import { MessageSquare, PlusCircle } from 'lucide-react'

interface Conversation {
  id: number
  agent_class: string
  status: string
  created_at: string
}

interface Props {
  conversations: Conversation[]
}

export default function Index({ conversations }: Props) {
  return (
    <div className="min-h-screen bg-background">
      <header className="bg-primary text-primary-foreground">
        <div className="container mx-auto px-4 py-6">
          <h1 className="text-3xl font-bold flex items-center gap-2">
            <span>📖</span> Bible Study Chat
          </h1>
          <p className="text-sm opacity-90 mt-1">An ActiveIntelligence Example Application</p>
        </div>
      </header>

      <div className="container mx-auto px-4 py-8">
        <div className="mb-6 flex items-center justify-between">
          <h2 className="text-2xl font-semibold">Recent Conversations</h2>
          <Link href="/conversations" method="post">
            <Button className="flex items-center gap-2">
              <PlusCircle className="w-4 h-4" />
              New Conversation
            </Button>
          </Link>
        </div>

        {conversations.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center justify-center py-12">
              <MessageSquare className="w-16 h-16 text-muted-foreground mb-4" />
              <p className="text-muted-foreground text-center mb-4">
                No conversations yet. Start a new Bible study conversation!
              </p>
              <Link href="/conversations" method="post" as="button">
                <Button>Start New Conversation</Button>
              </Link>
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-4">
            {conversations.map((conversation) => (
              <Link key={conversation.id} href={`/conversations/${conversation.id}`}>
                <Card className="hover:shadow-md transition-shadow cursor-pointer">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                      <MessageSquare className="w-5 h-5" />
                      Conversation #{conversation.id}
                    </CardTitle>
                    <CardDescription>
                      Started {new Date(conversation.created_at).toLocaleDateString()} at{' '}
                      {new Date(conversation.created_at).toLocaleTimeString()}
                    </CardDescription>
                  </CardHeader>
                </Card>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
