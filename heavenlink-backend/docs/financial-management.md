# Financial management

The finance API is mounted at `/api/v1/finance` and uses the existing bearer-token authentication and agent/admin roles. Agents can only read or change records for properties they own and are authorized to manage. Amounts are integer Tanzanian shillings.

## Data basis

- Rental obligations are accrued for their billing month. Rent receipts are manually reported offline receipts, not verified Haven Link payments, and are grouped by their payment date for collection and cash-flow reports.
- Stays revenue includes confirmed or completed bookings with succeeded payment transactions. Booking subtotal and verified customer payment receipts are separate measures; neither is an assumed agent payout.
- Operating profit is accrued income less recorded operating obligations. Cash flow is reported separately as cash received less recorded payments in the selected dates.
- Reversals are retained with actor, timestamp, and reason. Payment retries use idempotency keys.

## API

- `GET /dashboard?businessModel=contactUnlock|bookable&from=YYYY-MM-DD&to=YYYY-MM-DD&propertyId=...`
- `GET /admin/overview` (admin only)
- `GET /alerts` and `PATCH /alerts/:alertId/read`
- `POST /properties/:propertyId/rent` and `POST /properties/:propertyId/rent/:obligationId/receipts`
- `POST /properties/:propertyId/expenses`, `/bills`, and `/staff`
- `POST /properties/:propertyId/:recordType/:recordId/payments`
- Reversal endpoints are available for expenses, obligations, and recorded payments.

The database models are registered with the backend's existing additive Sequelize synchronization in `src/models/index.js`. The alert scheduler refreshes due and overdue financial alerts at startup and hourly; it is idempotent and uses the existing in-app notification table.
