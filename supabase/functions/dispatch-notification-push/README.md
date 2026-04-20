Push dispatcher for `app_notifications`.

Environment variables required:
- `SUPABASE_URL`
- `SERVICE_ROLE_KEY`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Recommended deployment:
- Function name: `dispatch-notification-push`
- `verify_jwt`: `true`

Suggested invocation patterns:
- Specific notification:
  - `{ "notification_id": "<uuid>" }`
- Batch dispatch:
  - `{ "batch_size": 20 }`

Behavior:
- Reads unread notifications that have not been pushed yet.
- Respects `notification_preferences.push_enabled`.
- Reads active device tokens from `user_device_tokens`.
- Sends FCM HTTP v1 push.
- Writes audit rows to `notification_deliveries`.
- Updates `app_notifications.push_status` and `sent_push_at`.
