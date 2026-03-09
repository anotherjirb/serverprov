# order_management

Handles all order CRUD operations and order validation for Step Functions.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SECRET_ARN` | Yes | ARN of the Secrets Manager secret containing RDS credentials | `arn:aws:secretsmanager:us-east-1:123456789:secret:techno-rds-secret` |
| `STEP_FUNCTIONS_ARN` | Yes | ARN of the Step Functions state machine to trigger on order creation | `arn:aws:states:us-east-1:123456789:stateMachine:techno-stepfunctions-order-workflow` |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/orders` | List all orders (supports `?limit=`, `?status=` query params) |
| `POST` | `/orders` | Create a new order and trigger Step Functions workflow |
| `GET` | `/orders/{id}` | Get a single order by ID |
| `PUT` | `/orders/{id}` | Update order status |
| `DELETE` | `/orders/{id}` | Delete an order |
| `GET` | `/status/{executionArn}` | Get Step Functions execution status and event history |
| `GET` | `/customers` | List all customers |
| `GET` | `/products` | List all products |

## Step Functions Action

When invoked by Step Functions with `action: validate`, this function validates the order payload and returns:

```json
{
  "isValid": true,
  "validationErrors": [],
  "validationMessage": "OK"
}
```

## IAM Permissions Required

- `secretsmanager:GetSecretValue`
- `states:StartExecution`
- `states:DescribeExecution`
- `states:GetExecutionHistory`
- `rds-db:connect` (via VPC)
