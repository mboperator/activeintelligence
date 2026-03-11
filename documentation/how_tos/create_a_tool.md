---
title: Create a Tool
description: Define a tool with parameters, validation, context fields, error handling, and callbacks.
tags: [tool, how-to, parameters, error-handling]
---

## Prerequisites

- Familiarity with the [Tool concept](../key_concepts/tool)

## 1. Basic Tool

```ruby
class CalculatorTool < ActiveIntelligence::Tool
  name "calculate"
  description "Evaluate a mathematical expression and return the result."

  param :expression, type: String, required: true,
    description: "A math expression like '2 + 2' or '10 * 3.14'"

  def execute(params)
    result = eval(params[:expression])   # simplified — see safety note below
    success_response({ result: result, expression: params[:expression] })
  end
end
```

Register on an agent:

```ruby
class MyAgent < ActiveIntelligence::Agent
  tool CalculatorTool
end
```

## 2. Multiple Parameters

```ruby
class SearchTool < ActiveIntelligence::Tool
  name "search_products"
  description "Search the product catalog."

  param :query,    type: String,  required: true,  description: "Search terms"
  param :category, type: String,  required: false, description: "Filter by category",
                   enum: ["electronics", "clothing", "books"]
  param :limit,    type: Integer, required: false, description: "Max results", default: 10
  param :in_stock, type: TrueClass, required: false, description: "Only show in-stock items"

  def execute(params)
    products = Product.search(
      query:    params[:query],
      category: params[:category],
      limit:    params[:limit],
      in_stock: params[:in_stock]
    )

    success_response({
      count:    products.count,
      products: products.map { |p| { id: p.id, name: p.name, price: p.price } }
    })
  end
end
```

`default:` is applied when the param is absent. `enum:` restricts allowed values — Claude will only pass the listed options.

## 3. Error Handling

Use `rescue_from` to convert exceptions into structured error responses instead of crashing:

```ruby
class DatabaseTool < ActiveIntelligence::Tool
  name "query_db"
  description "Run a read-only query against the analytics database."

  param :sql, type: String, required: true, description: "The SQL SELECT statement"

  rescue_from ActiveRecord::StatementInvalid, with: :handle_sql_error
  rescue_from Timeout::Error do |e, params|
    error_response("Query timed out after 30s. Try simplifying the query.")
  end
  rescue_from StandardError, with: :handle_generic_error

  def execute(params)
    rows = AnalyticsDB.query(params[:sql])
    success_response({ rows: rows, count: rows.length })
  end

  private

  def handle_sql_error(e, params)
    error_response("Invalid SQL", details: { message: e.message, sql: params[:sql] })
  end

  def handle_generic_error(e, params)
    error_response("Unexpected error", details: { type: e.class.name, message: e.message })
  end
end
```

Handlers receive `(exception, params)`. Return `error_response(...)` — the agent passes this to Claude so it can communicate the failure to the user.

## 4. Context Fields

Tools can require fields from the agent's context (request-level data like the current user):

```ruby
class UserOrdersTool < ActiveIntelligence::Tool
  name "get_user_orders"
  description "Get all orders for the currently authenticated user."

  context_field :current_user, required: true

  param :status, type: String, required: false,
    description: "Filter by status", enum: ["pending", "shipped", "delivered"]

  def execute(params)
    orders = current_user.orders
    orders = orders.where(status: params[:status]) if params[:status]

    success_response({
      orders: orders.map { |o| { id: o.id, total: o.total, status: o.status } }
    })
  end
end
```

The agent must be instantiated with the context value:

```ruby
agent = MyAgent.new(context: { current_user: User.find(session[:user_id]) })
```

If `current_user` is missing from context, `validate_context!` raises a `ContextError` before `execute` runs.

Source: `tool.rb:90-101`, `tool.rb:263-278`

## 5. Before-Execute Callbacks

Run logic before `execute` — useful for audit logging, rate limiting, or auth checks:

```ruby
class SensitiveActionTool < ActiveIntelligence::Tool
  context_field :current_user, required: true

  before_execute :check_permissions
  before_execute :log_attempt

  def execute(params)
    # ... perform action
  end

  private

  def check_permissions(params)
    raise AuthorizationError, "Not allowed" unless current_user.can?(:perform_action)
  end

  def log_attempt(params)
    AuditLog.create!(user: current_user, action: self.class.tool_name, params: params)
  end
end
```

Callbacks run in declaration order. Raising inside a callback stops execution and triggers error handling.

Source: `tool.rb:116-119`

## 6. Frontend Tools

Mark a tool as requiring client-side execution:

```ruby
class OpenFileTool < ActiveIntelligence::Tool
  name "open_file"
  description "Open a file picker dialog on the user's device."
  execution_context :frontend

  param :accept, type: String, required: false, description: "Accepted MIME types"

  def execute(params)
    # This never runs on the backend — the client handles it
    success_response({})
  end
end
```

When the agent encounters a frontend tool, it pauses and returns a response describing what tool to run. The client executes it and resumes:

```ruby
result = agent.send_message("Please open a file.")
if agent.paused_for_frontend?
  # client runs the tool, then:
  agent.continue_with_tool_results({ "tool_use_id" => "...", "result" => file_contents })
end
```

See [Frontend Tools](../workflows/frontend_tools) for the complete workflow.

## 7. Convenience Base Classes

Inherit from `QueryTool` or `CommandTool` to signal intent semantically:

```ruby
# Read-only — fetches data
class GetWeatherTool < ActiveIntelligence::QueryTool
  # ...
end

# Write/side-effect
class SendEmailTool < ActiveIntelligence::CommandTool
  # ...
end
```

There's no functional difference — these are conventions for readability.

Source: `tool.rb:336-342`
