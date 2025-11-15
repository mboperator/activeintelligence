# Frontend Tool Integration Example

This document shows how to integrate frontend tools in your React/JavaScript application.

## Overview

When the agent needs to execute a frontend tool (like `show_emoji`), it will pause and return a response with `type: 'frontend_tool_request'`. Your frontend should:

1. Execute the tool in the browser
2. Send the result back to Rails
3. Display the final response

## Example React Implementation

```javascript
// Example React component for handling frontend tools
import { useState } from 'react';

function ChatInterface({ conversationId }) {
  const [messages, setMessages] = useState([]);

  const sendMessage = async (messageText) => {
    // Send message to Rails
    const response = await fetch(`/conversations/${conversationId}/send_message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: messageText })
    });

    const data = await response.json();

    // Handle different response types
    if (data.type === 'frontend_tool_request') {
      // Execute frontend tools
      await handleFrontendTools(data.tools, conversationId);
    } else if (data.type === 'completed') {
      // Display the completed response
      setMessages([...messages, { role: 'assistant', content: data.response }]);
    }
  };

  const handleFrontendTools = async (tools, conversationId) => {
    const toolResults = [];

    // Execute each tool
    for (const toolCall of tools) {
      let result;

      switch (toolCall.name) {
        case 'show_emoji':
          result = await executeShowEmoji(toolCall.parameters);
          break;

        case 'file_picker':
          result = await executeFilePicker(toolCall.parameters);
          break;

        case 'clipboard_read':
          result = await executeClipboardRead(toolCall.parameters);
          break;

        default:
          result = {
            error: true,
            message: `Unknown frontend tool: ${toolCall.name}`
          };
      }

      toolResults.push({
        tool_use_id: toolCall.id,
        tool_name: toolCall.name,
        result: result,
        is_error: result.error || false
      });
    }

    // Send results back to Rails to continue the conversation
    const response = await fetch(`/conversations/${conversationId}/send_message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tool_results: toolResults })
    });

    const data = await response.json();

    // Recursively handle the response (might trigger more frontend tools!)
    if (data.type === 'frontend_tool_request') {
      await handleFrontendTools(data.tools, conversationId);
    } else if (data.type === 'completed') {
      setMessages([...messages, { role: 'assistant', content: data.response }]);
    }
  };

  const executeShowEmoji = async (params) => {
    // Display the emoji in the UI
    const emojiElement = document.createElement('div');
    emojiElement.className = `emoji-display emoji-${params.size}`;
    emojiElement.innerHTML = `
      <span class="emoji">${params.emoji}</span>
      ${params.message ? `<p>${params.message}</p>` : ''}
    `;

    // Add to chat
    const chatContainer = document.getElementById('chat-messages');
    chatContainer.appendChild(emojiElement);

    // Return success
    return {
      success: true,
      data: {
        emoji: params.emoji,
        displayed: true,
        timestamp: new Date().toISOString()
      }
    };
  };

  const executeFilePicker = async (params) => {
    try {
      // Use the File System Access API
      const [fileHandle] = await window.showOpenFilePicker({
        types: [
          {
            description: 'All Files',
            accept: { 'text/*': params.accept?.split(',') || ['*'] }
          }
        ],
        multiple: params.multiple === 'true'
      });

      const file = await fileHandle.getFile();
      const content = await file.text();

      return {
        success: true,
        data: {
          name: file.name,
          size: file.size,
          type: file.type,
          content: content
        }
      };
    } catch (error) {
      return {
        error: true,
        message: `File picker failed: ${error.message}`
      };
    }
  };

  const executeClipboardRead = async (params) => {
    try {
      const text = await navigator.clipboard.readText();

      return {
        success: true,
        data: {
          text: text,
          length: text.length
        }
      };
    } catch (error) {
      return {
        error: true,
        message: `Clipboard read failed: ${error.message}`
      };
    }
  };

  return (
    <div>
      <div id="chat-messages">
        {messages.map((msg, i) => (
          <div key={i} className={`message ${msg.role}`}>
            {msg.content}
          </div>
        ))}
      </div>

      <input
        type="text"
        onKeyPress={(e) => {
          if (e.key === 'Enter') {
            sendMessage(e.target.value);
            e.target.value = '';
          }
        }}
        placeholder="Type your message..."
      />
    </div>
  );
}

export default ChatInterface;
```

## Streaming Implementation (SSE)

For streaming responses, use Server-Sent Events (SSE) and listen for the special `frontend_tool_request` event:

```javascript
function ChatInterfaceStreaming({ conversationId }) {
  const [messages, setMessages] = useState([]);
  const [currentMessage, setCurrentMessage] = useState('');

  const sendMessageStreaming = async (messageText) => {
    const eventSource = new EventSource(
      `/conversations/${conversationId}/send_message_streaming?${new URLSearchParams({
        message: messageText
      })}`
    );

    let buffer = '';

    eventSource.onmessage = (event) => {
      if (event.data === '[DONE]') {
        // Stream complete
        setMessages([...messages, { role: 'assistant', content: buffer }]);
        setCurrentMessage('');
        eventSource.close();
        return;
      }

      // Accumulate chunks
      buffer += event.data;
      setCurrentMessage(buffer);
    };

    eventSource.addEventListener('frontend_tool_request', async (event) => {
      const data = JSON.parse(event.data);
      console.log('Frontend tool request received:', data);

      // Close the current stream
      eventSource.close();

      // Save any buffered content
      if (buffer) {
        setMessages(prev => [...prev, { role: 'assistant', content: buffer }]);
        buffer = '';
      }

      // Execute frontend tools
      const toolResults = await executeFrontendTools(data.tools);

      // Resume the conversation with a new stream
      await continueStreamingWithToolResults(conversationId, toolResults);
    });

    eventSource.onerror = (error) => {
      console.error('SSE Error:', error);
      eventSource.close();
    };
  };

  const continueStreamingWithToolResults = async (conversationId, toolResults) => {
    const eventSource = new EventSource(
      `/conversations/${conversationId}/send_message_streaming`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tool_results: toolResults })
      }
    );

    // Note: EventSource doesn't support POST natively
    // You'll need to use fetch-event-source or similar library
    // Or make a custom SSE implementation

    // Alternative: Use fetch with streaming response
    const response = await fetch(
      `/conversations/${conversationId}/send_message_streaming`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tool_results: toolResults })
      }
    );

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      const chunk = decoder.decode(value, { stream: true });
      const lines = chunk.split('\n');

      for (const line of lines) {
        if (line.startsWith('event: frontend_tool_request')) {
          // Another frontend tool request!
          const nextLine = lines[lines.indexOf(line) + 1];
          if (nextLine?.startsWith('data: ')) {
            const data = JSON.parse(nextLine.substring(6));
            const toolResults = await executeFrontendTools(data.tools);
            await continueStreamingWithToolResults(conversationId, toolResults);
            return;
          }
        } else if (line.startsWith('data: ')) {
          const data = line.substring(6);
          if (data === '[DONE]') {
            setMessages(prev => [...prev, { role: 'assistant', content: buffer }]);
            return;
          }
          buffer += data;
          setCurrentMessage(buffer);
        }
      }
    }
  };

  const executeFrontendTools = async (tools) => {
    const toolResults = [];

    for (const toolCall of tools) {
      let result;

      switch (toolCall.name) {
        case 'show_emoji':
          result = await executeShowEmoji(toolCall.parameters);
          break;
        default:
          result = { error: true, message: `Unknown tool: ${toolCall.name}` };
      }

      toolResults.push({
        tool_use_id: toolCall.id,
        tool_name: toolCall.name,
        result: result,
        is_error: result.error || false
      });
    }

    return toolResults;
  };

  const executeShowEmoji = async (params) => {
    // Same implementation as before
    const emojiElement = document.createElement('div');
    emojiElement.className = `emoji-display emoji-${params.size}`;
    emojiElement.innerHTML = `
      <span class="emoji">${params.emoji}</span>
      ${params.message ? `<p>${params.message}</p>` : ''}
    `;

    const chatContainer = document.getElementById('chat-messages');
    chatContainer.appendChild(emojiElement);

    return {
      success: true,
      data: {
        emoji: params.emoji,
        displayed: true,
        timestamp: new Date().toISOString()
      }
    };
  };

  return (
    <div>
      <div id="chat-messages">
        {messages.map((msg, i) => (
          <div key={i} className={`message ${msg.role}`}>
            {msg.content}
          </div>
        ))}
        {currentMessage && (
          <div className="message assistant streaming">
            {currentMessage}
          </div>
        )}
      </div>

      <input
        type="text"
        onKeyPress={(e) => {
          if (e.key === 'Enter') {
            sendMessageStreaming(e.target.value);
            e.target.value = '';
          }
        }}
        placeholder="Type your message..."
      />
    </div>
  );
}

export default ChatInterfaceStreaming;
```

## CSS for Emoji Display

```css
.emoji-display {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 20px;
  margin: 10px 0;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  border-radius: 12px;
  animation: fadeIn 0.5s ease-in;
}

.emoji-display.emoji-small .emoji {
  font-size: 2rem;
}

.emoji-display.emoji-medium .emoji {
  font-size: 4rem;
}

.emoji-display.emoji-large .emoji {
  font-size: 6rem;
}

.emoji-display p {
  color: white;
  margin-top: 10px;
  font-size: 1.1rem;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: scale(0.8);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
```

## Testing the Feature

1. Start your Rails server:
   ```bash
   cd examples/rails_bible_chat
   rails db:migrate
   rails server
   ```

2. In the console, try sending a message that would trigger the emoji tool:
   ```ruby
   conversation = ActiveIntelligence::Conversation.create!(
     agent_class: 'BibleStudyAgent',
     objective: 'Bible study'
   )

   agent = conversation.agent
   response = agent.send_message("Show me a praying hands emoji")

   # This should return a hash with status: :awaiting_frontend_tool
   puts response.inspect
   # => { status: :awaiting_frontend_tool, tools: [{...}], conversation_id: 123 }

   # Simulate frontend executing the tool
   tool_results = [{
     tool_use_id: response[:tools].first[:id],
     tool_name: 'show_emoji',
     result: { success: true, data: { emoji: '🙏', displayed: true } }
   }]

   final_response = agent.continue_with_tool_results(tool_results)
   puts final_response
   # => "I've displayed the praying hands emoji for you..."
   ```

## Key Points

1. **Tool Execution Context**: Tools marked with `execution_context :frontend` will pause the agent and return control to React

2. **Single Conversation Thread**: The agent maintains one continuous conversation with Claude, even across frontend tool executions

3. **Message History**: All tool calls and results are persisted in the database, so the conversation can be resumed after a server restart

4. **Recursive Handling**: Frontend tools can trigger more backend tools, which can trigger more frontend tools. The system handles this automatically.

5. **Error Handling**: Always wrap frontend tool execution in try/catch and return proper error responses

## Future Frontend Tools

Here are some ideas for useful frontend tools:

- **File Picker**: Let users select files from their computer
- **Clipboard**: Read from or write to the clipboard
- **Camera**: Take a photo or scan a QR code
- **Notifications**: Show browser notifications
- **Geolocation**: Get the user's location
- **Custom UI Components**: Render complex React components inline in the chat
- **Drawing Canvas**: Let users draw or annotate
- **Audio Recording**: Record audio from the user's microphone

All of these can be implemented by:
1. Creating a new tool class with `execution_context :frontend`
2. Adding a handler in your React frontend
3. Returning the result back to Rails
