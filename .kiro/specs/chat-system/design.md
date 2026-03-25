# Chat System Design

## Architecture Overview

The chat system will be built using Flutter for the frontend with Supabase as the backend, providing real-time messaging capabilities through WebSocket connections.

### Technology Stack
- **Frontend**: Flutter with real-time subscriptions
- **Backend**: Supabase (PostgreSQL + Realtime)
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **Image Storage**: Cloudinary
- **Real-time**: Supabase Realtime (WebSocket)

## Database Design

### Core Tables

#### chat_rooms
```sql
CREATE TABLE chat_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_type VARCHAR(20) NOT NULL CHECK (room_type IN ('toko', 'tim', 'global', 'private', 'announcement')),
  name VARCHAR(255) NOT NULL,
  
  -- Context fields (nullable, depends on room_type)
  toko_id UUID REFERENCES toko(id),
  sator_id UUID REFERENCES users(id),
  user1_id UUID REFERENCES users(id), -- for private chats
  user2_id UUID REFERENCES users(id), -- for private chats
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

#### chat_members
```sql
CREATE TABLE chat_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  
  is_muted BOOLEAN DEFAULT FALSE,
  last_read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(room_id, user_id)
);
```

#### chat_messages
```sql
CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
  
  message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'system')),
  content TEXT,
  image_url TEXT,
  
  -- Message features
  mentions UUID[], -- array of mentioned user_ids
  reply_to_id UUID REFERENCES chat_messages(id),
  
  -- Edit/Delete tracking
  is_edited BOOLEAN DEFAULT FALSE,
  is_deleted BOOLEAN DEFAULT FALSE,
  edited_at TIMESTAMP WITH TIME ZONE,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE -- for auto-cleanup
);
```
#### message_reads
```sql
CREATE TABLE message_reads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  read_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(message_id, user_id)
);
```

#### message_reactions
```sql
CREATE TABLE message_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  emoji VARCHAR(10) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(message_id, user_id, emoji)
);
```

### Indexes for Performance
```sql
-- Message queries (most frequent)
CREATE INDEX idx_messages_room_time ON chat_messages(room_id, created_at DESC);
CREATE INDEX idx_messages_sender ON chat_messages(sender_id);
CREATE INDEX idx_messages_expires ON chat_messages(expires_at) WHERE expires_at IS NOT NULL;

-- Read receipts
CREATE INDEX idx_reads_message ON message_reads(message_id);
CREATE INDEX idx_reads_user ON message_reads(user_id);

-- Chat members
CREATE INDEX idx_members_room ON chat_members(room_id);
CREATE INDEX idx_members_user ON chat_members(user_id);

-- Reactions
CREATE INDEX idx_reactions_message ON message_reactions(message_id);
```

## API Design

### Core Functions

#### get_user_chat_rooms(user_id)
Returns all chat rooms accessible to the user with unread message counts.

#### get_chat_messages(room_id, limit, offset)
Returns paginated messages for a chat room with sender info and read status.

#### send_message(room_id, content, message_type, mentions, reply_to_id)
Sends a new message and triggers real-time notifications.

#### mark_messages_read(room_id, user_id)
Marks all messages in a room as read by the user.

#### get_store_daily_data(toko_id, date)
Returns daily performance data for store chat rooms.

### Real-time Subscriptions

#### chat_messages_channel
```sql
-- Subscribe to new messages in user's accessible rooms
SELECT * FROM chat_messages 
WHERE room_id IN (user_accessible_rooms)
```

#### message_reads_channel
```sql
-- Subscribe to read receipt updates
SELECT * FROM message_reads 
WHERE message_id IN (user_sent_messages)
```

## UI Component Architecture

### Chat List Screen
- **ChatListPage**: Main chat interface with room list
- **ChatRoomTile**: Individual room display with unread count
- **ChatRoomSection**: Groups rooms by type (Store, Team, Private, etc.)

### Chat Room Screen
- **ChatRoomPage**: Individual chat room interface
- **MessageBubble**: Individual message display
- **MessageInput**: Text input with attachment options
- **StoreDataCard**: Daily data display for store rooms
- **TypingIndicator**: Shows who is currently typing

### Message Components
- **TextMessage**: Regular text message bubble
- **ImageMessage**: Image message with thumbnail
- **SystemMessage**: System notifications (user joined, etc.)
- **ReplyMessage**: Message with reply context
- **MessageReactions**: Emoji reactions display

## Real-time Implementation

### Supabase Realtime Setup
```dart
// Subscribe to chat messages
final subscription = supabase
  .channel('chat_messages')
  .onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'chat_messages',
    callback: (payload) => _handleNewMessage(payload),
  )
  .subscribe();
```

### Message Flow
1. User types message in UI
2. Message sent to `send_message()` function
3. Function validates permissions and inserts message
4. Supabase triggers real-time broadcast
5. All subscribed clients receive message instantly
6. FCM push notification sent to offline users
7. UI updates with new message and read receipts

## Automatic Room Management

### Room Creation Triggers
```sql
-- Auto-create store chat room when store is created
CREATE OR REPLACE FUNCTION create_store_chat_room()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO chat_rooms (room_type, name, toko_id)
  VALUES ('toko', NEW.name, NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_create_store_chat
  AFTER INSERT ON toko
  FOR EACH ROW EXECUTE FUNCTION create_store_chat_room();
```

### Membership Management
```sql
-- Auto-manage chat room membership based on user assignments
CREATE OR REPLACE FUNCTION update_chat_memberships()
RETURNS TRIGGER AS $$
BEGIN
  -- Add/remove users from appropriate chat rooms
  -- Based on their role and store assignments
  -- Implementation details in tasks
END;
$$ LANGUAGE plpgsql;
```

## Push Notification Strategy

### FCM Integration
- Configure FCM in Flutter app
- Store FCM tokens in user profiles
- Send notifications for:
  - New messages (when app is closed)
  - Mentions (priority notifications)
  - Announcements (to all users)

### Notification Payload
```json
{
  "notification": {
    "title": "New message from Ahmad",
    "body": "Hey, how's the sales today?",
    "sound": "default"
  },
  "data": {
    "room_id": "uuid",
    "message_id": "uuid",
    "sender_id": "uuid",
    "room_type": "toko",
    "is_mention": "false"
  }
}
```

## Image Upload Flow

### Cloudinary Integration
1. User selects image from camera/gallery
2. Image is compressed locally (max 1920px, 80% quality)
3. Upload to Cloudinary with auto-generated public_id
4. Store Cloudinary URL in message
5. Display thumbnail in chat with full-size on tap

### Image Message Structure
```dart
class ImageMessage {
  final String imageUrl;
  final String? caption;
  final int? width;
  final int? height;
  final String thumbnailUrl; // Cloudinary transformation
}
```

## Correctness Properties

### Property 1: Message Delivery Consistency
**Validates: Requirements US-6**
For any message sent to a chat room, all online members of that room must receive the message within 2 seconds, and the message must be stored persistently for offline members to receive when they come online.

### Property 2: Access Control Integrity  
**Validates: Requirements BR-1**
For any chat room access attempt, a user can only read/write messages if they are a member of that room according to the access control matrix, and membership must automatically reflect their current organizational role and assignments.

### Property 3: Read Receipt Accuracy
**Validates: Requirements US-8**
For any message marked as read by a user, that user must be a member of the chat room, must have actually received the message, and the read status must be immediately visible to the message sender with correct timestamp.

### Property 4: Automatic Membership Management
**Validates: Requirements US-9**
When a user's role or store assignment changes, their chat room memberships must automatically update within 1 minute to reflect their new access rights, with no manual intervention required.

### Property 5: Message Retention Compliance
**Validates: Requirements BR-2**
All regular chat messages must be automatically deleted after exactly 30 days, announcement messages after 180 days, and no message should be accessible after its retention period expires.

## Testing Framework
- **Unit Tests**: Individual functions and components
- **Integration Tests**: Real-time message flow
- **Property-Based Tests**: Using `test` package with custom generators
- **E2E Tests**: Full user workflows with `integration_test`

## Performance Considerations

### Message Pagination
- Load 50 messages initially
- Implement infinite scroll for message history
- Cache recent messages locally

### Real-time Optimization
- Batch read receipt updates
- Debounce typing indicators
- Optimize subscription queries

### Storage Management
- Automatic cleanup of expired messages
- Compress images before upload
- Cache frequently accessed data

## Security Considerations

### Row Level Security (RLS)
```sql
-- Users can only access rooms they're members of
CREATE POLICY chat_messages_access ON chat_messages
  FOR ALL USING (
    room_id IN (
      SELECT room_id FROM chat_members 
      WHERE user_id = auth.uid()
    )
  );
```

### Input Validation
- Sanitize message content
- Validate image uploads
- Rate limiting for message sending
- Mention validation against room members

## Deployment Strategy

### Database Migrations
- Create tables and indexes
- Set up RLS policies
- Create functions and triggers
- Populate initial data (global room, etc.)

### Flutter Implementation
- Implement UI components
- Set up real-time subscriptions  
- Configure FCM
- Add image upload functionality

### Testing and Rollout
- Test with small user group
- Monitor performance metrics
- Gradual rollout to all users
- Monitor and optimize based on usage patterns