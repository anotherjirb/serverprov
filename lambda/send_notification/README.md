# send_notification

Sends order confirmation or failure notification emails via Amazon SNS.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SNS_TOPIC_ARN` | Yes | ARN of the SNS topic used to send email notifications | `arn:aws:sns:us-east-1:123456789:techno-sns-topic` |

## Input (from Step Functions)

```json
{
  "orderId": "ORD-001",
  "customerId": "CUST001",
  "totalAmount": 150000,
  "paymentResult": { "paymentStatus": "success" }
}
```

## Output

```json
{
  "notificationResult": {
    "notificationStatus": "sent",
    "messageId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}
```

## IAM Permissions Required

- `sns:Publish`
