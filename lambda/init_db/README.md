# init_db

Initializes the PostgreSQL database schema and optionally inserts sample data.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SECRET_ARN` | Yes | ARN of the Secrets Manager secret containing RDS credentials | `arn:aws:secretsmanager:us-east-1:123456789:secret:techno-rds-secret` |

## Invocation

Invoke manually after the RDS instance is ready:

```bash
aws lambda invoke \
  --function-name techno-lambda-init-db \
  --payload '{"insert_sample_data": true}' \
  --cli-binary-format raw-in-base64-out \
  --region us-east-1 \
  /tmp/result.json && cat /tmp/result.json
```

Set `insert_sample_data` to `false` to create tables only without inserting data.

## Tables Created

- `customers` — customer profiles
- `products` — product catalog with stock quantities
- `orders` — order records linked to customers
- `order_items` — line items per order

## IAM Permissions Required

- `secretsmanager:GetSecretValue`
