# generate_report

Generates order summary reports and uploads them to S3 as JSON files.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SECRET_ARN` | Yes | ARN of the Secrets Manager secret containing RDS credentials | `arn:aws:secretsmanager:us-east-1:123456789:secret:techno-rds-secret` |
| `SNS_TOPIC_ARN` | No | ARN of the SNS topic to notify when a report is ready | `arn:aws:sns:us-east-1:123456789:techno-sns-topic` |
| `S3_LOGS_BUCKET` | Yes | Name of the S3 bucket where reports are stored | `techno-logs-myname-01` |

## Invocation

This function is invoked directly via API Gateway or on a schedule via EventBridge.

## Output (S3 Object)

Report is saved to: `s3://{S3_LOGS_BUCKET}/reports/report-{timestamp}.json`

## IAM Permissions Required

- `secretsmanager:GetSecretValue`
- `s3:PutObject`
- `s3:GetObject`
- `s3:GeneratePresignedUrl`
- `sns:Publish`
