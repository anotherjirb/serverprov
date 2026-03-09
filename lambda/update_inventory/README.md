# update_inventory

Decrements product stock quantities after a successful payment.

## Environment Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SECRET_ARN` | Yes | ARN of the Secrets Manager secret containing RDS credentials | `arn:aws:secretsmanager:us-east-1:123456789:secret:techno-rds-secret` |
| `LOW_STOCK_THRESHOLD` | No | Quantity threshold below which a product is considered low stock. Defaults to `5` | `5` |

## Input (from Step Functions)

```json
{
  "orderId": "ORD-001",
  "items": [
    { "productId": "PROD001", "quantity": 2 }
  ]
}
```

## Output

```json
{
  "inventoryResult": {
    "inventoryStatus": "updated",
    "updatedProducts": ["PROD001"],
    "lowStockProducts": []
  }
}
```

The `inventoryResult.inventoryStatus` field is used by the Step Functions `InventoryChoice` state. Valid values: `updated`, `failed`, `skipped`.

## IAM Permissions Required

- `secretsmanager:GetSecretValue`
