# health_check

Returns the health status of all downstream services: RDS, S3, and Step Functions.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SECRET_ARN` | Yes | ARN of the Secrets Manager secret containing RDS credentials | `arn:aws:secretsmanager:us-east-1:123456789:secret:techno-rds-secret` |
| `STEP_FUNCTIONS_ARN` | Yes | ARN of the Step Functions state machine to check | `arn:aws:states:us-east-1:123456789:stateMachine:techno-stepfunctions-order-workflow` |
| `FUNCTION_VERSION` | No | Display version string shown in the health response. Defaults to `$LATEST` | `1.0.0` |

## Response

```json
{
  "status": "healthy",
  "version": "$LATEST",
  "timestamp": "2026-03-07T00:00:00.000000",
  "checks": {
    "database": { "status": "healthy", "service": "rds" },
    "s3": { "status": "healthy", "service": "s3" },
    "stepfunctions": { "status": "healthy", "service": "stepfunctions" }
  }
}
```

## IAM Permissions Required

- `secretsmanager:GetSecretValue`
- `s3:ListBucket`
- `states:DescribeStateMachine`
