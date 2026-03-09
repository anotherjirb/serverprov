# process_payment

Simulates payment processing with idempotency support via DynamoDB.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SECRET_ARN` | Yes | ARN of the Secrets Manager secret containing RDS credentials | `arn:aws:secretsmanager:us-east-1:123456789:secret:techno-rds-secret` |
| `IDEMPOTENCY_TABLE` | No | DynamoDB table name for idempotency checks. Defaults to `techno-payment-idempotency` | `techno-payment-idempotency` |

## Input (from Step Functions)

```json
{
  "orderId": "ORD-001",
  "customerId": "CUST001",
  "totalAmount": 150000,
  "items": [...]
}
```

## Output

```json
{
  "paymentResult": {
    "paymentStatus": "success",
    "transactionId": "TXN-xxxxxxxx",
    "amount": 150000
  }
}
```

The `paymentResult.paymentStatus` field is used by the Step Functions `PaymentChoice` state. Valid values: `success`, `failed`.

## IAM Permissions Required

- `secretsmanager:GetSecretValue`
- `dynamodb:GetItem`
- `dynamodb:PutItem`
